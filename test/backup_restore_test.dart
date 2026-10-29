import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:anki_apk/data/database/app_database.dart';
import 'package:anki_apk/data/models/flashcard.dart';
import 'package:anki_apk/data/models/review_and_settings.dart';
import 'package:anki_apk/data/repositories/backup_repository.dart';
import 'package:anki_apk/data/services/backup_service.dart';
import 'package:anki_apk/data/services/image_storage_service.dart';
import 'package:anki_apk/ui/app_scope.dart';
import 'package:anki_apk/ui/backup_dialogs.dart';
import 'package:anki_apk/ui/catalog_screens.dart';
import 'package:anki_apk/ui/strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final Uint8List kSamplePngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=',
);

void main() {
  sqfliteFfiInit();

  late Directory deviceADir;
  late Directory deviceBDir;
  late ImageStorageService imageStorageA;
  late ImageStorageService imageStorageB;
  late BackupService backupServiceA;
  late BackupService backupServiceB;
  late AppDatabase db;

  setUp(() async {
    S.setLanguage(AppLanguage.kaa);
    deviceADir = Directory.systemTemp.createTempSync('anki_backup_devA_');
    deviceBDir = Directory.systemTemp.createTempSync('anki_backup_devB_');
    imageStorageA = ImageStorageService(getBaseDirectory: () async => deviceADir);
    imageStorageB = ImageStorageService(getBaseDirectory: () async => deviceBDir);
    backupServiceA = BackupService(imageStorage: imageStorageA);
    backupServiceB = BackupService(imageStorage: imageStorageB);

    db = await AppDatabase.open(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfiNoIsolate,
    );
  });

  tearDown(() async {
    S.setLanguage(AppLanguage.kaa);
    await db.close();
    if (deviceADir.existsSync()) deviceADir.deleteSync(recursive: true);
    if (deviceBDir.existsSync()) deviceBDir.deleteSync(recursive: true);
  });

  /// Resets the in-memory database to simulate moving to a clean second device.
  Future<void> reopenFreshDatabase() async {
    await db.close();
    db = await AppDatabase.open(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfiNoIsolate,
    );
  }

  group('Full backup export/import round-trip and portable image handling', () {
    test(
        'exports all hierarchy records, IDs, review history, scheduling, settings, and embedded images, and restores onto a different device directory after original image is deleted',
        () async {
      // 1. Seed full data on Device A
      await db.settings.setInterfaceLanguage('uz');
      final subj = await db.subjects.create(
        name: 'Tarix',
        description: 'Jahon tarixi',
      );
      final book = await db.books.create(
        subjectId: subj.id,
        name: '9-sinf',
        description: 'Darslik',
      );
      final topic = await db.topics.create(
        bookId: book.id,
        name: 'Uygʻonish davri',
      );
      final deck = await db.decks.create(
        topicId: topic.id,
        name: 'Asosiy sanalar',
      );

      final deviceAImagePath = await imageStorageA.persistPickedImage(
        PickedImageFile(fileName: 'map.png', bytes: kSamplePngBytes),
      );
      expect(File(deviceAImagePath).existsSync(), isTrue);

      final cardWithLocalImage = await db.flashcards.create(
        deckId: deck.id,
        targetText: 'Renessans',
        associationText: 'Uygʻonish',
        definitionText: 'Madaniy yuksalish davri',
        imagePath: deviceAImagePath,
        imagePlacement: ImagePlacement.both,
      );
      final cardWithExcelRef = await db.flashcards.create(
        deckId: deck.id,
        targetText: 'Gumanizm',
        definitionText: 'Insonparvarlik oqimi',
        imagePath: 'excel_only_ref.png',
        imagePlacement: ImagePlacement.back,
      );
      await db.flashcards.setStatus(cardWithExcelRef.id, CardStatus.mastered);

      // Record scheduled reviews on cardWithLocalImage
      final review1 = await db.reviews.recordScheduledReview(
        flashcardId: cardWithLocalImage.id,
        rating: ReviewRating.good,
        sessionId: 'sess-101',
        reviewedAt: DateTime.utc(2026, 5, 1, 10, 0),
      );
      final review2 = await db.reviews.recordScheduledReview(
        flashcardId: cardWithLocalImage.id,
        rating: ReviewRating.easy,
        sessionId: 'sess-102',
        reviewedAt: DateTime.utc(2026, 5, 2, 10, 0),
      );

      // 2. Export backup from Device A
      final bundle = await backupServiceA.exportBackup(db);
      expect(bundle.savedFilePath, isNotNull);
      expect(File(bundle.savedFilePath!).existsSync(), isTrue);
      expect(bundle.subjectCount, 1);
      expect(bundle.flashcardCount, 2);
      expect(bundle.reviewCount, 2);
      expect(bundle.imageCount, 1);

      // Verify JSON does NOT depend on Device A's absolute path
      expect(bundle.jsonString.contains(deviceADir.path), isFalse);
      expect(bundle.jsonString, contains('card_images/'));

      // 3. Delete Device A's image file and open a fresh empty DB on Device B
      File(deviceAImagePath).deleteSync();
      expect(File(deviceAImagePath).existsSync(), isFalse);
      await reopenFreshDatabase();
      expect(await db.subjects.getAll(), isEmpty);

      // 4. Parse, validate, and restore onto Device B
      final parseResult = backupServiceB.parseAndValidate(
        fileName: bundle.fileName,
        bytes: bundle.bytes,
      );
      expect(parseResult.isValid, isTrue);

      final summary = await backupServiceB.restoreValidatedBackup(
        db: db,
        package: parseResult.package!,
        mode: RestoreMode.replaceAll,
      );
      expect(summary.subjectsRestored, 1);
      expect(summary.booksRestored, 1);
      expect(summary.topicsRestored, 1);
      expect(summary.decksRestored, 1);
      expect(summary.flashcardsRestored, 2);
      expect(summary.reviewsRestored, 2);
      expect(summary.imagesRestored, 1);

      // 5. Verify restored records, IDs, relationships, settings, and scheduling on Device B
      expect(await db.settings.getInterfaceLanguage(), 'uz');

      final restoredSubjects = await db.subjects.getAll();
      expect(restoredSubjects.single.id, subj.id);
      expect(restoredSubjects.single.name, 'Tarix');

      final restoredBooks = await db.books.listBySubject(subj.id);
      expect(restoredBooks.single.id, book.id);

      final restoredTopics = await db.topics.listByBook(book.id);
      expect(restoredTopics.single.id, topic.id);

      final restoredDecks = await db.decks.listByTopic(topic.id);
      expect(restoredDecks.single.id, deck.id);

      final restoredCard1 =
          (await db.flashcards.getById(cardWithLocalImage.id))!;
      expect(restoredCard1.targetText, 'Renessans');
      expect(restoredCard1.imagePlacement, ImagePlacement.both);
      expect(restoredCard1.imagePath, isNotNull);
      expect(restoredCard1.imagePath, startsWith(deviceBDir.path));
      final restoredImageFile =
          ImageStorageService.resolveLocalImageFile(restoredCard1.imagePath);
      expect(restoredImageFile, isNotNull);
      expect(restoredImageFile!.readAsBytesSync(), kSamplePngBytes);

      final restoredCard2 =
          (await db.flashcards.getById(cardWithExcelRef.id))!;
      expect(restoredCard2.status, CardStatus.mastered);
      expect(restoredCard2.imagePath, 'excel_only_ref.png');

      final restoredReviews =
          await db.reviews.listForFlashcard(cardWithLocalImage.id);
      expect(restoredReviews, hasLength(2));
      expect(restoredReviews[0].id, review1.entry.id);
      expect(restoredReviews[0].sessionId, 'sess-101');
      expect(restoredReviews[1].id, review2.entry.id);
      expect(restoredReviews[1].dueAt, review2.entry.dueAt);
      expect(restoredReviews[1].intervalDays, review2.entry.intervalDays);
      expect(restoredReviews[1].easeFactor, review2.entry.easeFactor);
    });
  });

  group('Validation of invalid, corrupted, and broken backup files', () {
    test('rejects wrong extensions, corrupted JSON, newer schema, broken FK relationships, and bad images',
        () {
      // 1. Wrong extension
      final badExt = backupServiceA.parseAndValidate(
        fileName: 'backup.txt',
        bytes: Uint8List.fromList(utf8.encode('{}')),
      );
      expect(badExt.isValid, isFalse);
      expect(badExt.error!.kind, BackupErrorKind.invalidExtension);

      // 2. Corrupted JSON
      final badJson = backupServiceA.parseAndValidate(
        fileName: 'backup.json',
        bytes: Uint8List.fromList(utf8.encode('{not valid json')),
      );
      expect(badJson.isValid, isFalse);
      expect(badJson.error!.kind, BackupErrorKind.corruptedJson);

      // 3. Newer schema version
      final newerSchemaJson = jsonEncode({
        'format': 'yadla_backup',
        'format_version': 1,
        'schema_version': 99,
        'exported_at': 1700000000000,
        'subjects': [],
        'books': [],
        'topics': [],
        'decks': [],
        'flashcards': [],
        'review_history': [],
        'app_settings': [],
        'images': {},
      });
      final newerSchema = backupServiceA.parseAndValidate(
        fileName: 'newer.json',
        bytes: Uint8List.fromList(utf8.encode(newerSchemaJson)),
      );
      expect(newerSchema.isValid, isFalse);
      expect(newerSchema.error!.kind, BackupErrorKind.newerSchemaVersion);

      // 4. Broken foreign-key relationship (book references missing subject_id)
      final brokenFkJson = jsonEncode({
        'format': 'yadla_backup',
        'format_version': 1,
        'schema_version': 2,
        'exported_at': 1700000000000,
        'subjects': [],
        'books': [
          {
            'id': 'b1',
            'subject_id': 'missing-subject',
            'name': 'Book 1',
            'created_at': 100,
            'updated_at': 100,
          }
        ],
        'topics': [],
        'decks': [],
        'flashcards': [],
        'review_history': [],
        'app_settings': [],
        'images': {},
      });
      final brokenFk = backupServiceA.parseAndValidate(
        fileName: 'broken_fk.json',
        bytes: Uint8List.fromList(utf8.encode(brokenFkJson)),
      );
      expect(brokenFk.isValid, isFalse);
      expect(brokenFk.error!.kind, BackupErrorKind.brokenRelationships);

      // 5. Corrupted base64 image entry
      final badImageJson = jsonEncode({
        'format': 'yadla_backup',
        'format_version': 1,
        'schema_version': 2,
        'exported_at': 1700000000000,
        'subjects': [],
        'books': [],
        'topics': [],
        'decks': [],
        'flashcards': [],
        'review_history': [],
        'app_settings': [],
        'images': {
          'card_images/bad.png': {
            'file_name': 'bad.png',
            'bytes_base64': '!!!not_base64!!!',
          }
        },
      });
      final badImg = backupServiceA.parseAndValidate(
        fileName: 'bad_img.json',
        bytes: Uint8List.fromList(utf8.encode(badImageJson)),
      );
      expect(badImg.isValid, isFalse);
      expect(badImg.error!.kind, BackupErrorKind.corruptedImages);
    });
  });

  group('Safe restore behavior and UI confirmation dialog', () {
    testWidgets(
        'never silently overwrites existing data: shows warning, allows cancel, merges safely by default, or replaces when chosen',
        (tester) async {
      // Prepare a backup with Subject "Biologiya" and Russian language setting
      await db.settings.setInterfaceLanguage('ru');
      final sA = await db.subjects.create(name: 'Biologiya');
      final bA = await db.books.create(subjectId: sA.id, name: '7-klass');
      final tA = await db.topics.create(bookId: bA.id, name: 'Botanika');
      final dA = await db.decks.create(topicId: tA.id, name: 'Ósimlikler');
      await db.flashcards.create(
        deckId: dA.id,
        targetText: 'Fotosintez',
        definitionText: 'Jaqtılıq járdeminde organikalıq zat payda bolıwı',
      );
      final backupBundle = await backupServiceA.exportBackup(
        db,
        saveToAppDirectory: false,
      );

      // Reopen a fresh DB and seed existing data ("Matematika") so DB is non-empty
      await reopenFreshDatabase();
      await db.subjects.create(name: 'Matematika');

      await tester.pumpWidget(
        AppScope(
          database: db,
          child: MaterialApp(
            home: SubjectsScreen(
              backupService: backupServiceB,
              pickBackupFile: () async => PickedBackupFile(
                fileName: backupBundle.fileName,
                bytes: backupBundle.bytes,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Matematika'), findsOneWidget);
      expect(find.text('Biologiya'), findsNothing);

      // 1. Open backup menu -> Import backup -> Cancel before confirming
      await tester.tap(find.byKey(const Key('backup-menu-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('import-backup-menu-item')));
      await tester.pumpAndSettle();

      // Preview dialog warns that existing data is present
      expect(
        find.byKey(const Key('backup-existing-data-warning')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('backup-preview-summary')), findsOneWidget);

      await tester.tap(find.byKey(const Key('cancel-restore-button')));
      await tester.pumpAndSettle();

      // Database was NOT modified on cancel
      expect(await db.subjects.getAll(), hasLength(1));
      expect(find.text('Biologiya'), findsNothing);

      // 2. Open Import backup again and confirm with default Merge mode
      await tester.tap(find.byKey(const Key('backup-menu-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('import-backup-menu-item')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('confirm-restore-button')));
      await tester.pumpAndSettle();

      // Both existing "Matematika" and restored "Biologiya" are present!
      expect(find.text('Matematika'), findsOneWidget);
      expect(find.text('Biologiya'), findsOneWidget);
      // Interface language updated to Russian ('ru') from backup
      expect(find.text('Добавить предмет'), findsOneWidget);

      // 3. Open Import backup again, choose Replace All mode, and confirm
      await tester.tap(find.byKey(const Key('backup-menu-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('import-backup-menu-item')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('restore-mode-replace')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm-restore-button')));
      await tester.pumpAndSettle();

      // Now only "Biologiya" from the backup remains
      expect(find.text('Biologiya'), findsOneWidget);
      expect(find.text('Matematika'), findsNothing);

      // 4. Selecting an invalid/corrupted backup in UI shows localized error and leaves data intact
      await tester.pumpWidget(
        AppScope(
          database: db,
          child: MaterialApp(
            home: SubjectsScreen(
              backupService: backupServiceB,
              pickBackupFile: () async => PickedBackupFile(
                fileName: 'corrupted.json',
                bytes: Uint8List.fromList(utf8.encode('{broken')),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('backup-menu-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('import-backup-menu-item')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('backup-error-text')), findsOneWidget);
      await tester.tap(find.byKey(const Key('close-backup-error-button')));
      await tester.pumpAndSettle();

      expect(find.text('Biologiya'), findsOneWidget);
    });
  });
}
