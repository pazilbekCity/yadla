import 'package:anki_apk/data/database/app_database.dart';
import 'package:anki_apk/data/models/flashcard.dart';
import 'package:anki_apk/main.dart';
import 'package:anki_apk/ui/strings.dart';
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
    await tester.pumpWidget(AnkiApp(openDatabase: () async => db));
    await tester.pumpAndSettle();

    expect(find.text('Anki APK'), findsOneWidget);
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

  testWidgets('Deleting a parent with children is blocked with Karakalpak explanation',
      (tester) async {
    final s = await db.subjects.create(name: 'Tariyx');
    await db.books.create(subjectId: s.id, name: 'Qaraqalpaqstan tariyxı');

    await tester.pumpWidget(AnkiApp(openDatabase: () async => db));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.text(S.delete));
    await tester.pumpAndSettle();

    expect(find.text(S.deleteBlocked('Tariyx')), findsOneWidget);
    expect(find.text('Tariyx'), findsOneWidget);
  });

  testWidgets(
      'Hierarchy navigation Subject -> Book -> Topic -> Deck -> Flashcard CRUD and Preview',
      (tester) async {
    await tester.pumpWidget(AnkiApp(openDatabase: () async => db));
    await tester.pumpAndSettle();

    // 1. Add Subject
    await tester.tap(find.byKey(const Key('fab-add-subject')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('field-name')), 'Informatics');
    await tester.tap(find.byKey(const Key('dialog-save')));
    await tester.pumpAndSettle();

    // Navigate to Books
    await tester.tap(find.text('Informatics'));
    await tester.pumpAndSettle();
    expect(find.text(S.booksEmpty), findsOneWidget);

    // 2. Add Book
    await tester.tap(find.byKey(const Key('fab-add-book')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('field-name')), 'Grade 8');
    await tester.tap(find.byKey(const Key('dialog-save')));
    await tester.pumpAndSettle();

    // Navigate to Topics
    await tester.tap(find.text('Grade 8'));
    await tester.pumpAndSettle();
    expect(find.text(S.topicsEmpty), findsOneWidget);

    // 3. Add Topic
    await tester.tap(find.byKey(const Key('fab-add-topic')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('field-name')), 'MS Word');
    await tester.tap(find.byKey(const Key('dialog-save')));
    await tester.pumpAndSettle();

    // Navigate to Decks
    await tester.tap(find.text('MS Word'));
    await tester.pumpAndSettle();
    expect(find.text(S.decksEmpty), findsOneWidget);

    // 4. Add Deck
    await tester.tap(find.byKey(const Key('fab-add-deck')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('field-name')), 'Vocabulary');
    await tester.tap(find.byKey(const Key('dialog-save')));
    await tester.pumpAndSettle();

    // Navigate to DeckScreen (Flashcards)
    await tester.tap(find.text('Vocabulary'));
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
    expect(find.text('Lenta panel'), findsOneWidget);
    expect(find.byKey(const Key('image-placeholder-front')), findsOneWidget);
    expect(find.byKey(const Key('definition-card')), findsNothing);

    // Reveal definition & back image placeholder
    await tester.tap(find.byKey(const Key('toggle-definition')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('definition-card')), findsOneWidget);
    expect(find.text('Buyrıqlar paneli'), findsOneWidget);
    expect(find.byKey(const Key('image-placeholder-back')), findsOneWidget);

    // Go back to DeckScreen and edit card to placement = back
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text(S.placementBack));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('card-save')));
    await tester.pumpAndSettle();

    // Verify in DB and in Preview that front placeholder is gone and back is shown
    final cards = await db.flashcards
        .listByDeck((await db.decks.listByTopic((await db.topics.listByBook((await db.books.listBySubject((await db.subjects.getAll()).first.id)).first.id)).first.id)).first.id);
    expect(cards.single.imagePlacement, ImagePlacement.back);

    await tester.tap(find.text('Ribbon'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('image-placeholder-front')), findsNothing);
    await tester.tap(find.byKey(const Key('toggle-definition')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('image-placeholder-back')), findsOneWidget);
  });
}
