import 'dart:io';

import 'package:anki_apk/data/database/app_database.dart';
import 'package:anki_apk/data/models/flashcard.dart';
import 'package:anki_apk/main.dart';
import 'package:anki_apk/ui/app_scope.dart';
import 'package:anki_apk/ui/deck_screen.dart';
import 'package:anki_apk/ui/flashcard_editor_screen.dart';
import 'package:anki_apk/ui/flashcard_preview_screen.dart';
import 'package:anki_apk/ui/strings.dart';
import 'package:anki_apk/ui/study_session_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  late AppDatabase db;

  setUp(() async {
    S.setLanguage(AppLanguage.kaa);
    db = await AppDatabase.open(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfiNoIsolate,
    );
  });

  tearDown(() async {
    S.setLanguage(AppLanguage.kaa);
    await db.close();
  });

  group('String translations across Karakalpak (kaa), Uzbek (uz), Russian (ru)',
      () {
    test('provides complete translations for all three supported languages',
        () {
      // 1. Karakalpak (default)
      S.setLanguage(AppLanguage.kaa);
      expect(S.currentLanguage, AppLanguage.kaa);
      expect(S.addSubject, 'Pán qosıw');
      expect(S.subjectsEmpty, contains('Áli pánler joq'));
      expect(S.rateAgain, 'Qayta');
      expect(S.rateHard, 'Qıyın');
      expect(S.rateGood, 'Jaqsı');
      expect(S.rateEasy, 'Ańsat');
      expect(S.markMastered, 'Yad boldı');
      expect(S.restoreToLearning, 'Úyreniwge qaytarıw');
      expect(S.importPreviewTitle, 'Excel importın aldınnan kóriw');
      expect(S.pickImage, 'Súwret tańlaw');
      expect(S.imageMissingOrUnreadable,
          'Súwret faylı tabılmadı yamasa oqıp bolmadı.');
      expect(S.confirmDelete('Test'), '«Test» óshirilsin be?');

      // 2. Uzbek
      S.setLanguage(AppLanguage.uz);
      expect(S.currentLanguage, AppLanguage.uz);
      expect(S.addSubject, 'Fan qoʻshish');
      expect(S.subjectsEmpty, contains('Hali fanlar yoʻq'));
      expect(S.rateAgain, 'Qayta');
      expect(S.rateHard, 'Qiyin');
      expect(S.rateGood, 'Yaxshi');
      expect(S.rateEasy, 'Oson');
      expect(S.markMastered, 'Yod boʻldi');
      expect(S.restoreToLearning, 'Oʻrganishga qaytarish');
      expect(S.importPreviewTitle, 'Excel importini oldindan koʻrish');
      expect(S.pickImage, 'Rasm tanlash');
      expect(
          S.imageMissingOrUnreadable, 'Rasm fayli topilmadi yoki oʻqib boʻlmadi.');
      expect(S.confirmDelete('Test'), '«Test» oʻchirilsinmi?');

      // 3. Russian
      S.setLanguage(AppLanguage.ru);
      expect(S.currentLanguage, AppLanguage.ru);
      expect(S.addSubject, 'Добавить предмет');
      expect(S.subjectsEmpty, contains('Предметов пока нет'));
      expect(S.rateAgain, 'Снова');
      expect(S.rateHard, 'Трудно');
      expect(S.rateGood, 'Хорошо');
      expect(S.rateEasy, 'Легко');
      expect(S.markMastered, 'Выучено');
      expect(S.restoreToLearning, 'Вернуть к изучению');
      expect(S.importPreviewTitle, 'Предпросмотр импорта Excel');
      expect(S.pickImage, 'Выбрать изображение');
      expect(
          S.imageMissingOrUnreadable, 'Файл изображения не найден или не читается.');
      expect(S.confirmDelete('Test'), 'Удалить «Test»?');
    });

    test('persists interface_language in file database and survives restart',
        () async {
      final tempDir =
          Directory.systemTemp.createTempSync('anki_apk_l10n_test_');
      try {
        final dbPath = p.join(tempDir.path, 'l10n.db');
        var fileDb = await AppDatabase.open(
          path: dbPath,
          factory: databaseFactoryFfiNoIsolate,
        );

        // Default when unset is null -> resolves to kaa
        expect(await fileDb.settings.getInterfaceLanguage(), isNull);
        expect(
          AppLanguage.fromCode(await fileDb.settings.getInterfaceLanguage()),
          AppLanguage.kaa,
        );

        // Persist Russian ('ru'), close and reopen DB
        await fileDb.settings.setInterfaceLanguage('ru');
        await fileDb.close();

        fileDb = await AppDatabase.open(
          path: dbPath,
          factory: databaseFactoryFfiNoIsolate,
        );
        final storedAfterReopen = await fileDb.settings.getInterfaceLanguage();
        expect(storedAfterReopen, 'ru');
        expect(AppLanguage.fromCode(storedAfterReopen), AppLanguage.ru);
        await fileDb.close();
      } finally {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      }
    });
  });

  group('UI language selector, live switching, and localized screens', () {
    testWidgets(
        'defaults to Karakalpak, switches live to Uzbek and Russian via AppBar selector, persists to DB, and restores on app restart',
        (tester) async {
      await tester.pumpWidget(AnkiApp(openDatabase: () async => db));
      await tester.pumpAndSettle();

      // 1. Default is Karakalpak (kaa)
      expect(
        find.text('Áli pánler joq. «Pán qosıw» túymesin basıń.'),
        findsOneWidget,
      );
      expect(find.text('Pán qosıw'), findsOneWidget);

      // 2. Open language menu and switch to Uzbek (uz)
      await tester.tap(find.byKey(const Key('language-selector-button')));
      await tester.pumpAndSettle();
      expect(find.text('Qaraqalpaqsha'), findsOneWidget);
      expect(find.text('Oʻzbekcha'), findsOneWidget);
      expect(find.text('Русский'), findsOneWidget);

      await tester.tap(find.byKey(const Key('lang-option-uz')));
      await tester.pumpAndSettle();

      expect(
        find.text('Hali fanlar yoʻq. «Fan qoʻshish» tugmasini bosing.'),
        findsOneWidget,
      );
      expect(find.text('Fan qoʻshish'), findsOneWidget);
      expect(await db.settings.getInterfaceLanguage(), 'uz');

      // 3. Switch live to Russian (ru)
      await tester.tap(find.byKey(const Key('language-selector-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('lang-option-ru')));
      await tester.pumpAndSettle();

      expect(
        find.text('Предметов пока нет. Нажмите «Добавить предмет».'),
        findsOneWidget,
      );
      expect(find.text('Добавить предмет'), findsOneWidget);
      expect(await db.settings.getInterfaceLanguage(), 'ru');

      // 4. Simulate app restart with a new AnkiApp instance sharing the same DB
      S.setLanguage(AppLanguage.kaa); // reset in-memory state before restart
      await tester.pumpWidget(
        AnkiApp(
          key: UniqueKey(),
          openDatabase: () async => db,
        ),
      );
      await tester.pumpAndSettle();

      // Restores Russian from persisted app_settings
      expect(
        find.text('Предметов пока нет. Нажмите «Добавить предмет».'),
        findsOneWidget,
      );
      expect(find.text('Добавить предмет'), findsOneWidget);
    });

    testWidgets(
        'renders localized Deck, Editor, Preview, and StudySession screens in Uzbek and Russian',
        (tester) async {
      final subj = await db.subjects.create(name: 'Informatika');
      final book = await db.books.create(subjectId: subj.id, name: '8-sinf');
      final topic = await db.topics.create(bookId: book.id, name: 'Grafika');
      final deck = await db.decks.create(topicId: topic.id, name: 'Atamalar');
      final card = await db.flashcards.create(
        deckId: deck.id,
        targetText: 'Piksel',
        definitionText: 'Tasvirning eng kichik nuqtasi',
        imagePath: 'missing_sample.png',
        imagePlacement: ImagePlacement.front,
      );

      // Test in Uzbek (uz)
      await db.settings.setInterfaceLanguage('uz');
      await tester.pumpWidget(
        AppScope(
          database: db,
          initialLanguage: AppLanguage.uz,
          child: MaterialApp(
            home: DeckScreen(deck: deck),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Kartochkalar soni: 1'), findsOneWidget);
      expect(find.text('Toʻplamni oʻrganish'), findsOneWidget);
      expect(find.text('Kartochka qoʻshish'), findsOneWidget);

      // StudySession in Russian (ru)
      await tester.pumpWidget(
        AppScope(
          database: db,
          initialLanguage: AppLanguage.ru,
          child: MaterialApp(
            home: StudySessionScreen.forDeck(
              deckId: deck.id,
              deckName: deck.name,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Показать определение'), findsOneWidget);
      expect(find.text('Выучено'), findsOneWidget);
      expect(find.text('Снова'), findsOneWidget);
      expect(find.text('Трудно'), findsOneWidget);
      expect(find.text('Хорошо'), findsOneWidget);
      expect(find.text('Легко'), findsOneWidget);
      expect(
        find.text('Файл изображения не найден или не читается.'),
        findsOneWidget,
      );

      // FlashcardEditorScreen & Preview in Russian (ru)
      await tester.pumpWidget(
        AppScope(
          database: db,
          initialLanguage: AppLanguage.ru,
          child: MaterialApp(
            home: FlashcardEditorScreen(deckId: deck.id, existing: card),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Изменить карточку'), findsOneWidget);
      expect(find.text('Заменить изображение'), findsOneWidget);
      expect(find.text('Спереди'), findsOneWidget);
      expect(find.text('Сзади'), findsOneWidget);
      expect(find.text('С обеих сторон'), findsOneWidget);

      await tester.pumpWidget(
        AppScope(
          database: db,
          initialLanguage: AppLanguage.ru,
          child: MaterialApp(
            home: FlashcardPreviewScreen(card: card),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Просмотр карточки'), findsOneWidget);
    });
  });
}
