import 'dart:typed_data';

import 'package:anki_apk/data/database/app_database.dart';
import 'package:anki_apk/data/models/catalog_models.dart';
import 'package:anki_apk/data/models/review_and_settings.dart';
import 'package:anki_apk/data/services/excel_import_service.dart';
import 'package:anki_apk/ui/app_scope.dart';
import 'package:anki_apk/ui/deck_screen.dart';
import 'package:anki_apk/ui/excel_import_dialog.dart';
import 'package:anki_apk/ui/strings.dart';
import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Uint8List buildXlsxBytes(List<List<String?>> rows) {
  final excel = Excel.createExcel();
  final sheet = excel[excel.getDefaultSheet()!];
  for (var r = 0; r < rows.length; r++) {
    final row = rows[r];
    for (var c = 0; c < row.length; c++) {
      final cellVal = row[c];
      if (cellVal != null) {
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r))
            .value = TextCellValue(cellVal);
      }
    }
  }
  return Uint8List.fromList(excel.encode()!);
}

void main() {
  sqfliteFfiInit();

  const service = ExcelImportService();
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

  Future<Deck> seedDeck() async {
    final s = await db.subjects.create(name: 'Informatika');
    final b = await db.books.create(subjectId: s.id, name: '8-klass');
    final t = await db.topics.create(bookId: b.id, name: 'Word');
    return db.decks.create(topicId: t.id, name: 'Terminler');
  }

  group('ExcelImportService parsing and validation', () {
    test('parses valid .xlsx rows including optional association and image_filename',
        () {
      final bytes = buildXlsxBytes([
        ['target_text', 'association_text', 'definition_text', 'image_filename'],
        ['Ribbon', 'Joqarǵı lenta', 'Buyrıqlar paneli', 'ribbon.png'],
        ['Clipboard', null, 'Almasıw buferi', ''],
      ]);

      final preview = service.parseXlsxBytes(
        fileName: 'words.xlsx',
        bytes: bytes,
      );

      expect(preview.hasFileError, isFalse);
      expect(preview.canImport, isTrue);
      expect(preview.validRows, hasLength(2));
      expect(preview.invalidRows, isEmpty);
      expect(preview.skippedDuplicateCount, 0);

      expect(preview.validRows[0].targetText, 'Ribbon');
      expect(preview.validRows[0].associationText, 'Joqarǵı lenta');
      expect(preview.validRows[0].definitionText, 'Buyrıqlar paneli');
      expect(preview.validRows[0].imageFilename, 'ribbon.png');

      expect(preview.validRows[1].targetText, 'Clipboard');
      expect(preview.validRows[1].associationText, isNull);
      expect(preview.validRows[1].definitionText, 'Almasıw buferi');
      expect(preview.validRows[1].imageFilename, isNull);
    });

    test('rejects missing required columns (target_text or definition_text)',
        () {
      final bytes = buildXlsxBytes([
        ['target_text', 'association_text'],
        ['Ribbon', 'Lenta'],
      ]);

      final preview = service.parseXlsxBytes(
        fileName: 'bad_columns.xlsx',
        bytes: bytes,
      );

      expect(preview.hasFileError, isTrue);
      expect(preview.canImport, isFalse);
      expect(
        preview.fileError!.kind,
        ExcelImportErrorKind.missingColumns,
      );
      expect(preview.fileError!.missingColumns, ['definition_text']);
      expect(preview.validRows, isEmpty);
    });

    test('rejects non-.xlsx extension, corrupted bytes, and empty sheets', () {
      final badExt = service.parseXlsxBytes(
        fileName: 'cards.csv',
        bytes: Uint8List.fromList([1, 2, 3]),
      );
      expect(
        badExt.fileError!.kind,
        ExcelImportErrorKind.invalidExtension,
      );

      final corrupted = service.parseXlsxBytes(
        fileName: 'broken.xlsx',
        bytes: Uint8List.fromList([10, 20, 30, 40]),
      );
      expect(
        corrupted.fileError!.kind,
        ExcelImportErrorKind.corruptedOrUnreadable,
      );

      final headerOnly = buildXlsxBytes([
        ['target_text', 'definition_text'],
        ['', ''],
      ]);
      final emptySheet = service.parseXlsxBytes(
        fileName: 'empty.xlsx',
        bytes: headerOnly,
      );
      expect(
        emptySheet.fileError!.kind,
        ExcelImportErrorKind.emptyFile,
      );
    });

    test('identifies invalid rows and deduplicates repeated rows within same file',
        () {
      final bytes = buildXlsxBytes([
        ['target_text', 'definition_text'],
        ['', 'Maqset sózi joq qatar'], // row 2 -> invalid (missing target)
        ['Anıqlaması joq', '   '], // row 3 -> invalid (missing definition)
        ['ValidWord', 'ValidDef'], // row 4 -> valid
        ['validword', 'VALIDDEF'], // row 5 -> duplicate of row 4
      ]);

      final preview = service.parseXlsxBytes(
        fileName: 'mixed.xlsx',
        bytes: bytes,
      );

      expect(preview.hasFileError, isFalse);
      expect(preview.validRows, hasLength(1));
      expect(preview.validRows.single.targetText, 'ValidWord');
      expect(preview.skippedDuplicateCount, 1);
      expect(preview.invalidRows, hasLength(2));
      expect(preview.invalidRows[0].rowNumber, 2);
      expect(preview.invalidRows[0].reason, InvalidRowReason.missingTarget);
      expect(preview.invalidRows[1].rowNumber, 3);
      expect(preview.invalidRows[1].reason, InvalidRowReason.missingDefinition);
    });
  });

  group('database persistence and UI preview-confirm workflow', () {
    test(
        'importBatch preserves existing cards and review history and skips duplicates',
        () async {
      final deck = await seedDeck();
      final existing = await db.flashcards.create(
        deckId: deck.id,
        targetText: 'ExistingWord',
        definitionText: 'ExistingDef',
      );
      await db.reviews.recordScheduledReview(
        flashcardId: existing.id,
        rating: ReviewRating.good,
        sessionId: 'prior-sess',
      );

      final bytes = buildXlsxBytes([
        ['target_text', 'association_text', 'definition_text', 'image_filename'],
        ['ExistingWord', 'NewAssoc', 'ExistingDef', null], // duplicate of existing
        ['NewWord1', 'Assoc1', 'Def1', 'pic1.png'],
        ['NewWord1', 'Assoc1', 'Def1', 'pic1.png'], // duplicate in file
        ['NewWord2', null, 'Def2', null],
      ]);

      final existingCards = await db.flashcards.listByDeck(deck.id);
      final preview = service.parseXlsxBytes(
        fileName: 'import.xlsx',
        bytes: bytes,
        existingDeckCards: existingCards,
      );
      expect(preview.validRows, hasLength(2));
      expect(preview.skippedDuplicateCount, 2);

      final commit = await db.flashcards.importBatch(
        deckId: deck.id,
        rows: preview.validRows,
        preSkippedCount: preview.skippedDuplicateCount,
      );
      expect(commit.importedCount, 2);
      expect(commit.skippedCount, 2);

      final allCards = await db.flashcards.listByDeck(deck.id);
      expect(allCards, hasLength(3));

      // Verify existing card and its review history are untouched
      final reloadedExisting = (await db.flashcards.getById(existing.id))!;
      expect(reloadedExisting.targetText, 'ExistingWord');
      expect(await db.reviews.listForFlashcard(existing.id), hasLength(1));

      // Verify image_filename was stored in imagePath
      final newCard1 =
          allCards.firstWhere((c) => c.targetText == 'NewWord1');
      expect(newCard1.imagePath, 'pic1.png');
    });

    testWidgets(
        'DeckScreen shows preview counts before DB write, cancels cleanly, and imports only on confirm',
        (tester) async {
      final deck = await seedDeck();
      final xlsxBytes = buildXlsxBytes([
        ['target_text', 'association_text', 'definition_text', 'image_filename'],
        ['CPU', 'Miy', 'Oraylıq processor', 'cpu.png'],
        ['RAM', 'Jedel yad', 'Waqıtsha yad', null],
        ['', 'Qáte', 'Atı joq', null], // invalid row
      ]);

      await tester.pumpWidget(
        AppScope(
          database: db,
          child: MaterialApp(
            home: DeckScreen(
              deck: deck,
              pickXlsxFile: () async => PickedXlsxFile(
                fileName: 'hardware.xlsx',
                bytes: xlsxBytes,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap import button -> preview dialog opens, DB STILL HAS 0 CARDS
      await tester.tap(find.byKey(const Key('import-excel-button')));
      await tester.pumpAndSettle();

      expect(find.text(S.importPreviewTitle), findsOneWidget);
      expect(find.text(S.importValidRows(2)), findsOneWidget);
      expect(find.text(S.importInvalidRows(1)), findsOneWidget);
      expect(await db.flashcards.listByDeck(deck.id), isEmpty);

      // Cancel -> nothing written to DB
      await tester.tap(find.byKey(const Key('cancel-import-button')));
      await tester.pumpAndSettle();
      expect(await db.flashcards.listByDeck(deck.id), isEmpty);

      // Open preview again and confirm -> 2 cards inserted, 1 invalid skipped
      await tester.tap(find.byKey(const Key('import-excel-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm-import-button')));
      await tester.pumpAndSettle();

      final savedCards = await db.flashcards.listByDeck(deck.id);
      expect(savedCards, hasLength(2));
      expect(find.text(S.cardCount(2)), findsOneWidget);
      expect(find.text('CPU'), findsOneWidget);
      expect(find.text('RAM'), findsOneWidget);
      expect(find.text(S.importSuccessSummary(2, 1)), findsOneWidget);
    });
  });
}
