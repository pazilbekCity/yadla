import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:anki_apk/data/database/app_database.dart';
import 'package:anki_apk/data/models/flashcard.dart';
import 'package:anki_apk/data/services/image_storage_service.dart';
import 'package:anki_apk/ui/app_scope.dart';
import 'package:anki_apk/ui/flashcard_editor_screen.dart';
import 'package:anki_apk/ui/flashcard_preview_screen.dart';
import 'package:anki_apk/ui/strings.dart';
import 'package:anki_apk/ui/study_session_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Valid 1x1 transparent PNG image bytes.
final Uint8List kValid1x1Png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=',
);

void main() {
  sqfliteFfiInit();

  late Directory tempDir;
  late ImageStorageService imageStorage;
  late AppDatabase db;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('anki_apk_img_test_');
    imageStorage = ImageStorageService(getBaseDirectory: () async => tempDir);
    db = await AppDatabase.open(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfiNoIsolate,
    );
  });

  tearDown(() async {
    await db.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  Future<String> seedDeckId() async {
    final s = await db.subjects.create(name: 'Informatika');
    final b = await db.books.create(subjectId: s.id, name: '8-klass');
    final t = await db.topics.create(bookId: b.id, name: 'Grafika');
    final d = await db.decks.create(topicId: t.id, name: 'Formatlar');
    return d.id;
  }

  group('ImageStorageService persistence and validation', () {
    test(
        'copies picked image into persistent card_images directory and resolves existing files only',
        () async {
      final savedPath = await imageStorage.persistPickedImage(
        PickedImageFile(fileName: 'sample.png', bytes: kValid1x1Png),
      );

      expect(savedPath, contains('card_images'));
      expect(savedPath.endsWith('.png'), isTrue);
      final savedFile = File(savedPath);
      expect(savedFile.existsSync(), isTrue);
      expect(savedFile.readAsBytesSync(), kValid1x1Png);

      // Existing file resolves to File
      expect(ImageStorageService.resolveLocalImageFile(savedPath), isNotNull);

      // Persist in a file-based SQLite DB and reopen to verify durability across restarts
      final fileDbPath = p.join(tempDir.path, 'reopen_check.db');
      var fileDb = await AppDatabase.open(
        path: fileDbPath,
        factory: databaseFactoryFfiNoIsolate,
      );
      final s = await fileDb.subjects.create(name: 'Subj');
      final b = await fileDb.books.create(subjectId: s.id, name: 'Book');
      final t = await fileDb.topics.create(bookId: b.id, name: 'Topic');
      final d = await fileDb.decks.create(topicId: t.id, name: 'Deck');
      await fileDb.flashcards.create(
        deckId: d.id,
        targetText: 'DurableCard',
        imagePath: savedPath,
        imagePlacement: ImagePlacement.both,
      );
      await fileDb.close();

      fileDb = await AppDatabase.open(
        path: fileDbPath,
        factory: databaseFactoryFfiNoIsolate,
      );
      final reopenedCards = await fileDb.flashcards.listByDeck(d.id);
      expect(reopenedCards.single.imagePath, savedPath);
      expect(
        ImageStorageService.resolveLocalImageFile(reopenedCards.single.imagePath),
        isNotNull,
      );
      await fileDb.close();

      // Bare Excel image_filename that does not exist on disk returns null
      expect(
        ImageStorageService.resolveLocalImageFile('excel_only_ref.png'),
        isNull,
      );

      // Deleted file returns null without throwing
      savedFile.deleteSync();
      expect(ImageStorageService.resolveLocalImageFile(savedPath), isNull);
    });

    test('rejects unsupported extensions and empty image bytes', () async {
      await expectLater(
        imageStorage.persistPickedImage(
          PickedImageFile(
            fileName: 'bad.txt',
            bytes: Uint8List.fromList([1, 2, 3]),
          ),
        ),
        throwsA(
          isA<ImageStorageException>().having(
            (e) => e.kind,
            'kind',
            ImageStorageErrorKind.unsupportedExtension,
          ),
        ),
      );

      await expectLater(
        imageStorage.persistPickedImage(
          PickedImageFile(
            fileName: 'empty.png',
            bytes: Uint8List(0),
          ),
        ),
        throwsA(
          isA<ImageStorageException>().having(
            (e) => e.kind,
            'kind',
            ImageStorageErrorKind.emptyOrUnreadable,
          ),
        ),
      );
    });
  });

  group('FlashcardEditorScreen, Preview, StudySession, and missing-image safety',
      () {
    testWidgets(
        'selects image in editor, saves persistent path to DB, and image survives reopening DB',
        (tester) async {
      final deckId = await seedDeckId();

      await tester.pumpWidget(
        AppScope(
          database: db,
          child: MaterialApp(
            home: FlashcardEditorScreen(
              deckId: deckId,
              imageStorage: imageStorage,
              pickImageFile: () async => PickedImageFile(
                fileName: 'diagram.png',
                bytes: kValid1x1Png,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('card-target')), 'Pixel');
      await tester.enterText(
          find.byKey(const Key('card-definition')), 'Súwrettiń eń kishiaw bólegi');

      await tester.tap(find.byKey(const Key('pick-image-button')));
      await tester.pumpAndSettle();

      // Editor shows preview and fills persistent path
      expect(find.byKey(const Key('editor-image-preview')), findsOneWidget);

      await tester.tap(find.byKey(const Key('card-save')));
      await tester.pumpAndSettle();

      final cards = await db.flashcards.listByDeck(deckId);
      expect(cards, hasLength(1));
      final savedCard = cards.single;
      expect(savedCard.imagePath, isNotNull);
      expect(savedCard.imagePath, contains('card_images'));
      expect(File(savedCard.imagePath!).existsSync(), isTrue);
    });

    testWidgets(
        'renders local image on front, back, or both in Preview and Study screens, and shows Karakalpak fallback when file is deleted',
        (tester) async {
      final deckId = await seedDeckId();
      final persistentPath = await imageStorage.persistPickedImage(
        PickedImageFile(fileName: 'icon.png', bytes: kValid1x1Png),
      );

      final cardBack = await db.flashcards.create(
        deckId: deckId,
        targetText: 'BackImageCard',
        definitionText: 'Artqı súwretli kartochka',
        imagePath: persistentPath,
        imagePlacement: ImagePlacement.back,
      );

      // 1. Preview with ImagePlacement.back -> hidden on front, rendered as Image on back
      await tester.pumpWidget(
        MaterialApp(home: FlashcardPreviewScreen(card: cardBack)),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('image-placeholder-front')), findsNothing);
      expect(find.byType(Image), findsNothing);

      await tester.tap(find.byKey(const Key('toggle-definition')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('image-placeholder-back')), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);

      // 2. Delete the underlying file on disk -> Study screen must not crash and must show Karakalpak fallback message
      File(persistentPath).deleteSync();
      await db.flashcards.update(
        cardBack.copyWith(imagePlacement: ImagePlacement.both),
      );

      await tester.pumpWidget(
        AppScope(
          database: db,
          child: MaterialApp(
            home: StudySessionScreen.forDeck(
              deckId: deckId,
              deckName: 'Formatlar',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('study-image-front')), findsOneWidget);
      expect(find.text(S.imageMissingOrUnreadable), findsOneWidget);

      await tester.tap(find.byKey(const Key('study-toggle-definition')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('study-image-back')), findsOneWidget);
      expect(find.text(S.imageMissingOrUnreadable), findsNWidgets(2));
    });
  });
}
