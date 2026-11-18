import 'package:yadla/data/database/app_database.dart';
import 'package:yadla/data/models/flashcard.dart';
import 'package:yadla/data/services/preset_catalog_service.dart';
import 'package:yadla/main.dart';
import 'package:yadla/ui/app_scope.dart';
import 'package:yadla/ui/catalog_screens.dart';
import 'package:yadla/ui/strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  late AppDatabase db;

  setUp(() async {
    db = await AppDatabase.open(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfiNoIsolate,
    );
  });

  tearDown(() async {
    await db.close();
  });

  testWidgets('Home shows app title and Karakalpak empty state, can add/edit/delete subject',
      (tester) async {
    await tester.pumpWidget(YadlaApp(openDatabase: () async => db));
    await tester.pumpAndSettle();

    expect(find.text('Yadla'), findsOneWidget);
    expect(find.text(S.subjectsEmpty), findsOneWidget);

    // Open Add Subject dialog and check Karakalpak validation on empty submit
    await tester.tap(find.byKey(const Key('fab-add-subject')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('dialog-save')));
    await tester.pumpAndSettle();
    expect(find.text(S.nameRequired), findsOneWidget);

    // Enter valid subject name and description
    await tester.enterText(find.byKey(const Key('field-name')), 'Informatika');
    await tester.enterText(
        find.byKey(const Key('field-description')), '8-klass kursı');
    await tester.tap(find.byKey(const Key('dialog-save')));
    await tester.pumpAndSettle();

    expect(find.text('Informatika'), findsOneWidget);
    expect(find.text('8-klass kursı'), findsOneWidget);

    // Duplicate subject name shows Karakalpak error and keeps dialog open
    await tester.tap(find.byKey(const Key('fab-add-subject')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('field-name')), 'Informatika');
    await tester.tap(find.byKey(const Key('dialog-save')));
    await tester.pumpAndSettle();
    expect(find.text(S.errDuplicate), findsOneWidget);
    await tester.tap(find.text(S.cancel));
    await tester.pumpAndSettle();

    // Edit subject
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('field-name')), 'Informatika 8');
    await tester.tap(find.byKey(const Key('dialog-save')));
    await tester.pumpAndSettle();
    expect(find.text('Informatika 8'), findsOneWidget);

    // Delete subject: cancel keeps it, confirm deletes it
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    expect(find.text(S.confirmDelete('Informatika 8')), findsOneWidget);
    await tester.tap(find.text(S.cancel));
    await tester.pumpAndSettle();
    expect(find.text('Informatika 8'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.text(S.delete));
    await tester.pumpAndSettle();
    expect(find.text('Informatika 8'), findsNothing);
    expect(find.text(S.subjectsEmpty), findsOneWidget);
  });

  testWidgets(
      'Deleting a parent with children shows 2-step warning with Karakalpak explanation; cancel keeps it, confirming deletes subtree, and theme toggles Day/Night',
      (tester) async {
    final s = await db.subjects.create(name: 'Tariyx');
    await db.books.create(subjectId: s.id, name: 'Qaraqalpaqstan tariyxı');

    await tester.pumpWidget(YadlaApp(openDatabase: () async => db));
    await tester.pumpAndSettle();

    // Toggle Day -> Night theme and verify persistence in app_settings
    expect(find.byKey(const Key('theme-mode-button')), findsOneWidget);
    await tester.tap(find.byKey(const Key('theme-mode-button')));
    await tester.pumpAndSettle();
    expect(await db.settings.getThemeMode(), 'dark');

    // Step 1: tap delete -> first confirmation dialog -> tap Óshiriw
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.text(S.delete));
    await tester.pumpAndSettle();

    // Step 2: 2nd warning dialog appears (not deleted immediately!)
    expect(find.text(S.deleteBlocked('Tariyx')), findsOneWidget);
    expect(find.byKey(const Key('confirm-cascade-delete')), findsOneWidget);

    // Cancel keeps the subject and its books intact
    await tester.tap(find.text(S.cancel));
    await tester.pumpAndSettle();
    expect(find.text('Tariyx'), findsOneWidget);
    expect(await db.subjects.getAll(), hasLength(1));

    // Confirming the 2nd dialog deletes the subject and its subtree
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.text(S.delete));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-cascade-delete')));
    await tester.pumpAndSettle();

    expect(find.text('Tariyx'), findsNothing);
    expect(await db.subjects.getAll(), isEmpty);
  });

  testWidgets(
      'Shortened hierarchy navigation Subject -> Book (with year & cover) -> Topic -> Flashcards CRUD, Preview, and Study buttons',
      (tester) async {
    await tester.pumpWidget(YadlaApp(openDatabase: () async => db));
    await tester.pumpAndSettle();

    // 1. Add Subject
    await tester.tap(find.byKey(const Key('fab-add-subject')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('field-name')), 'Informatics');
    await tester.tap(find.byKey(const Key('dialog-save')));
    await tester.pumpAndSettle();

    // Subject row has its own ▶ Study button
    final createdSubject = (await db.subjects.getAll()).single;
    expect(find.byKey(Key('study-subject-${createdSubject.id}')), findsOneWidget);

    // Navigate to Books
    await tester.tap(find.text('Informatics'));
    await tester.pumpAndSettle();
    expect(find.text(S.booksEmpty), findsOneWidget);

    // 2. Add Book with publication year
    await tester.tap(find.byKey(const Key('fab-add-book')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('field-name')), 'Grade 8');
    await tester.enterText(find.byKey(const Key('field-book-year')), '2024');
    await tester.tap(find.byKey(const Key('dialog-save')));
    await tester.pumpAndSettle();

    // Book row displays cover placeholder, separate year badge, and ▶ Study button
    final createdBook = (await db.books.listBySubject(createdSubject.id)).single;
    expect(find.byKey(Key('book-cover-${createdBook.id}')), findsOneWidget);
    expect(find.byKey(Key('book-year-badge-${createdBook.id}')), findsOneWidget);
    expect(find.text(S.bookYearBadge(2024)), findsOneWidget);
    expect(find.byKey(Key('study-book-${createdBook.id}')), findsOneWidget);

    // Navigate to Topics
    await tester.tap(find.text('Grade 8'));
    await tester.pumpAndSettle();
    expect(find.text(S.topicsEmpty), findsOneWidget);
    expect(find.byKey(const Key('study-book-button')), findsOneWidget);

    // 3. Add Topic
    await tester.tap(find.byKey(const Key('fab-add-topic')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('field-name')), 'MS Word');
    await tester.tap(find.byKey(const Key('dialog-save')));
    await tester.pumpAndSettle();

    final createdTopic = (await db.topics.listByBook(createdBook.id)).single;
    expect(find.byKey(Key('study-topic-${createdTopic.id}')), findsOneWidget);

    // 4. Tapping Topic opens Flashcards directly (no intermediate Deck screen!)
    await tester.tap(find.text('MS Word'));
    await tester.pumpAndSettle();
    expect(find.text(S.cardCount(0)), findsOneWidget);
    expect(find.text(S.flashcardsEmpty), findsOneWidget);

    // 5. Open Flashcard Editor & test validation
    await tester.tap(find.byKey(const Key('fab-add-flashcard')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('card-save')));
    await tester.pumpAndSettle();
    expect(find.text(S.targetRequired), findsOneWidget);

    // Fill flashcard fields with imagePlacement = both
    await tester.enterText(find.byKey(const Key('card-target')), 'Ribbon');
    await tester.enterText(
        find.byKey(const Key('card-association')), 'Lenta panel');
    await tester.enterText(
        find.byKey(const Key('card-definition')), 'Buyrıqlar paneli');
    await tester.enterText(
        find.byKey(const Key('card-image')), 'images/ribbon.png');
    await tester.tap(find.text(S.placementBoth));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('card-save')));
    await tester.pumpAndSettle();

    // DeckScreen updated with count 1 and card listed
    expect(find.text(S.cardCount(1)), findsOneWidget);
    expect(find.text('Ribbon'), findsOneWidget);
    expect(find.text('Buyrıqlar paneli'), findsOneWidget);

    // 6. Preview card (imagePlacement = both)
    await tester.tap(find.text('Ribbon'));
    await tester.pumpAndSettle();
    expect(find.text(S.previewTitle), findsOneWidget);
    expect(find.text('Ribbon'), findsOneWidget);
    expect(find.byKey(const Key('image-placeholder-front')), findsOneWidget);
    expect(find.byKey(const Key('definition-card')), findsNothing);

    // Association is 3rd and collapsible (closed initially, opens on tap)
    expect(find.text('Lenta panel'), findsNothing);
    await tester.tap(find.byKey(const Key('toggle-association')));
    await tester.pumpAndSettle();
    expect(find.text('Lenta panel'), findsOneWidget);

    // Reveal definition & back image placeholder
    await tester.tap(find.byKey(const Key('toggle-definition')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('definition-card')), findsOneWidget);
    expect(find.text('Buyrıqlar paneli'), findsOneWidget);
    expect(find.byKey(const Key('image-placeholder-back')), findsOneWidget);

    // Go back to Flashcards screen and edit card to placement = back
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text(S.placementBack));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('card-save')));
    await tester.pumpAndSettle();

    // Verify in DB and in Preview that front placeholder is gone and back is shown
    final cards = await db.flashcards.listByTopic(createdTopic.id);
    expect(cards.single.imagePlacement, ImagePlacement.back);

    await tester.tap(find.text('Ribbon'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('image-placeholder-front')), findsNothing);
    await tester.tap(find.byKey(const Key('toggle-definition')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('image-placeholder-back')), findsOneWidget);
  });

  testWidgets(
      'Add Subject dialog offers 1. Preset Google Sheets download (Informatika with Col G Assosaciya) and 2. Create from 0',
      (tester) async {
    const sampleTemalarCsv = '''
Klass,Tema atı
7-klass,5-sabaq Hújjetke Header hám Footer maydanların qosıw
10-klass,15-sabaq Tarmaq kompyuterleri
''';
    var currentJuwaplarCsv = '''
Klass,Tema,Gilt sóz,Anıqlama / Túsinik,Sáne,,Assosaciya
10-klass,15-sabaq Tarmaq kompyuterleri,Server,Klient qurılması paydalanıw múmkin bolǵan resurslardı támiynlewshi tarmaq kompyuteri,11.11.2026 10:05:35,, Bas kompyuter
7-klass,5-sabaq Hújjetke Header hám Footer maydanların qosıw,Header,Hújjettiń joqarǵı bólimindegi maydan,19,16.11.2026 14:49:18,
''';

    const sampleReklamaCsv = '''
Reklama,Tekst,Baylanıs
«Bilim» oqıw orayı,Matematika hám Informatika DTM kursları,@bilim_nokis
''';

    final mockPresetService = PresetCatalogService(
      fetchText: (uri) async {
        final u = uri.toString();
        if (u.contains('sheet=Reklama')) return sampleReklamaCsv;
        if (u.contains('gid=0') || u.contains('sheet=P')) {
          return sampleTemalarCsv;
        }
        return currentJuwaplarCsv;
      },
    );

    await tester.pumpWidget(
      AppScope(
        database: db,
        child: MaterialApp(
          home: SubjectsScreen(presetCatalogService: mockPresetService),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Open "+ Pán qosıw" dialog -> both Option 1 and Option 2 are shown
    await tester.tap(find.byKey(const Key('fab-add-subject')));
    await tester.pumpAndSettle();
    expect(find.text(S.addSubjectFromDatabase), findsOneWidget);
    expect(find.text(S.addSubjectFromScratch), findsOneWidget);
    expect(find.byKey(const Key('preset-subject-informatika')), findsOneWidget);

    // Tap Option 1: download Informatika from preset database
    await tester.tap(find.byKey(const Key('preset-subject-informatika')));
    await tester.pumpAndSettle();

    // Verify Subject, Books, Topics, and Flashcards (with and without Col G Assosaciya) are imported
    final subjects = await db.subjects.getAll();
    expect(subjects, hasLength(1));
    expect(subjects.single.name, 'Informatika');

    final books = await db.books.listBySubject(subjects.single.id);
    expect(books.map((b) => b.name).toSet(), {'7-klass', '10-klass'});

    final allCards = await db.flashcards.listBySubject(subjects.single.id);
    expect(allCards, hasLength(2));
    final serverCard =
        allCards.firstWhere((c) => c.targetText == 'Server');
    final headerCard =
        allCards.firstWhere((c) => c.targetText == 'Header');
    expect(serverCard.associationText, 'Bas kompyuter');
    expect(serverCard.pageNumber, isNull); // timestamp in Col E is ignored
    expect(headerCard.associationText, isNull);
    expect(headerCard.pageNumber, '19'); // page number in Col E is captured

    // Simulate user deleting 7-klass book (cascade) and sheet updating Server's page & Header's association
    final book7 = books.firstWhere((b) => b.name == '7-klass');
    await db.books.delete(book7.id, cascade: true);
    currentJuwaplarCsv = '''
Klass,Tema,Gilt sóz,Anıqlama / Túsinik,Sáne,,Assosaciya
10-klass,15-sabaq Tarmaq kompyuterleri,Server,Jańalanǵan server anıqlaması,25,11.11.2026 10:05:35,Bas kompyuter
7-klass,5-sabaq Hújjetke Header hám Footer maydanların qosıw,Header,Hújjettiń joqarǵı bólimindegi maydan,19,16.11.2026 14:49:18,Joqarǵı kolontitul
''';

    // Once Informatika is already downloaded, opening "+ Pán qosıw" again hides it
    // and shows only "Jańa pán jaratıw"
    await tester.tap(find.byKey(const Key('fab-add-subject')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('preset-subject-informatika')), findsNothing);
    expect(find.text(S.addSubjectFromScratch), findsOneWidget);
    await tester.tap(find.text(S.cancel));
    await tester.pumpAndSettle();

    // Enter Informatika and tap "Bazadan jańalaw" (sync-preset-subject-button)
    await tester.tap(find.text('Informatika'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sync-preset-subject-button')));
    await tester.pumpAndSettle();

    final booksAfterSync = await db.books.listBySubject(subjects.single.id);
    expect(booksAfterSync.map((b) => b.name).toSet(), {'7-klass', '10-klass'});
    final cardsAfterSync = await db.flashcards.listBySubject(subjects.single.id);
    expect(cardsAfterSync, hasLength(2));
    final updatedServer =
        cardsAfterSync.firstWhere((c) => c.targetText == 'Server');
    final restoredHeader =
        cardsAfterSync.firstWhere((c) => c.targetText == 'Header');
    expect(updatedServer.definitionText, 'Jańalanǵan server anıqlaması');
    expect(updatedServer.pageNumber, '25');
    expect(restoredHeader.associationText, 'Joqarǵı kolontitul');

    // Open 10-klass Book -> tap 🔍 Search button -> search by Gilt sóz ("Serv")
    // and verify the found card displays its textbook page number ("25-bet")
    await tester.tap(find.text('10-klass'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('search-book-cards-button')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('search-cards-field')), 'Serv');
    await tester.pumpAndSettle();
    expect(find.text('Server'), findsOneWidget);
    expect(find.byKey(Key('card-page-badge-${updatedServer.id}')), findsOneWidget);
    expect(find.text(S.bookPageBadge('25')), findsOneWidget);

    // Mark Server as mastered -> Subject (1/2 = 0.5) and 10-klass Book (1/1 = 1.0)
    // render left-to-right green progress fills!
    await db.flashcards.setStatus(updatedServer.id, CardStatus.mastered);
    await tester.pageBack(); // back to TopicsScreen (10-klass)
    await tester.pumpAndSettle();
    await tester.pageBack(); // back to BooksScreen (Informatika)
    await tester.pumpAndSettle();

    final book10 =
        booksAfterSync.firstWhere((b) => b.name == '10-klass');
    final book10ProgressBox = tester.widget<FractionallySizedBox>(
      find.byKey(Key('book-progress-${book10.id}')),
    );
    expect(book10ProgressBox.widthFactor, 1.0);

    await tester.pageBack(); // back to SubjectsScreen
    await tester.pumpAndSettle();
    final subjectProgressBox = tester.widget<FractionallySizedBox>(
      find.byKey(Key('subject-progress-${subjects.single.id}')),
    );
    expect(subjectProgressBox.widthFactor, 0.5);

    // Verify 🔥 Daily Streak (1 day), 📅 Due Today (1 remaining card), and 📢 Reklama/Daǵaza banner
    expect(find.byKey(const Key('home-streak-badge')), findsOneWidget);
    expect(find.text(S.streakDaysBadge(1)), findsOneWidget);
    expect(find.byKey(const Key('home-due-today-badge')), findsOneWidget);
    expect(find.text(S.dueTodayBadge(1)), findsOneWidget);
    expect(find.byKey(const Key('promo-banner-card')), findsOneWidget);
    expect(find.text('«Bilim» oqıw orayı'), findsOneWidget);

    // Dismiss promo banner
    await tester.tap(find.byKey(const Key('dismiss-promo-banner')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('promo-banner-card')), findsNothing);
  });

  testWidgets('APK expires 20 days after install and blocks app with admin notice', (tester) async {
    var fakeNow = DateTime.utc(2026, 11, 1, 10, 0);
    final customDb = await AppDatabase.open(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfiNoIsolate,
      clock: () => fakeNow,
    );
    addTearDown(() async => customDb.close());

    // Day 0: initial install -> not expired
    expect(await customDb.settings.checkIsApkExpired(), isFalse);

    // Day 19: still active
    fakeNow = DateTime.utc(2026, 11, 20, 9, 59);
    expect(await customDb.settings.checkIsApkExpired(), isFalse);

    // Day 20: expired!
    fakeNow = DateTime.utc(2026, 11, 21, 10, 0);
    expect(await customDb.settings.checkIsApkExpired(), isTrue);

    // Rolling device clock backwards to Day 5 does not bypass expiration
    fakeNow = DateTime.utc(2026, 11, 6, 10, 0);
    expect(await customDb.settings.checkIsApkExpired(), isTrue);

    // Launching YadlaApp shows ExpiredVersionScreen and blocks SubjectsScreen
    await tester.pumpWidget(YadlaApp(openDatabase: () async => customDb));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('expired-version-screen')), findsOneWidget);
    expect(
      find.text(
        'Eskirgen versiya!\n'
        'Jańalaw ushın adminge xabarlasıń.\n'
        'Admin: https://t.me/Xayratdin',
      ),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.add), findsNothing);

    // Installing a newer APK release resets the 20-day window while keeping data
    fakeNow = DateTime.utc(2026, 11, 22, 10, 0);
    expect(
      await customDb.settings.checkIsApkExpired(releaseId: 'yadla-1.0.0+2'),
      isFalse,
    );
  });
}
