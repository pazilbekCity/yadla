import 'dart:typed_data';

import 'package:excel/excel.dart';

import '../models/flashcard.dart';

/// Required and optional spreadsheet column headers (matched case-insensitively
/// after trimming).
class ExcelImportColumns {
  const ExcelImportColumns._();

  static const targetText = 'target_text';
  static const associationText = 'association_text';
  static const definitionText = 'definition_text';
  static const imageFilename = 'image_filename';

  static const requiredColumns = [targetText, definitionText];
}

/// One validated spreadsheet row ready to be inserted into a deck.
class FlashcardImportRow {
  const FlashcardImportRow({
    required this.rowNumber,
    required this.targetText,
    this.associationText,
    required this.definitionText,
    this.imageFilename,
  });

  /// 1-based Excel row index.
  final int rowNumber;
  final String targetText;
  final String? associationText;
  final String definitionText;
  final String? imageFilename;

  /// Normalized key used to detect duplicate rows within the same import or
  /// against cards already present in the target deck.
  String get dedupeKey =>
      '${targetText.trim().toLowerCase()}\u0000${definitionText.trim().toLowerCase()}';
}

enum InvalidRowReason {
  missingTarget,
  missingDefinition,
}

/// One rejected spreadsheet row with its 1-based row number and reason.
class InvalidImportRow {
  const InvalidImportRow({
    required this.rowNumber,
    required this.reason,
  });

  final int rowNumber;
  final InvalidRowReason reason;
}

enum ExcelImportErrorKind {
  invalidExtension,
  corruptedOrUnreadable,
  emptyFile,
  missingColumns,
}

/// File-level validation error returned when an `.xlsx` file cannot be imported.
class ExcelImportFileError {
  const ExcelImportFileError(
    this.kind, {
    this.missingColumns = const [],
    this.details,
  });

  final ExcelImportErrorKind kind;
  final List<String> missingColumns;
  final String? details;
}

/// Result of parsing and validating an `.xlsx` file before any database write.
class ExcelImportPreview {
  const ExcelImportPreview({
    required this.fileName,
    this.fileError,
    this.validRows = const [],
    this.invalidRows = const [],
    this.skippedDuplicateCount = 0,
  });

  final String fileName;
  final ExcelImportFileError? fileError;
  final List<FlashcardImportRow> validRows;
  final List<InvalidImportRow> invalidRows;
  final int skippedDuplicateCount;

  bool get hasFileError => fileError != null;
  bool get canImport => fileError == null && validRows.isNotEmpty;
}

/// Summary returned after confirmed import writes to SQLite.
class ExcelImportCommitResult {
  const ExcelImportCommitResult({
    required this.importedCount,
    required this.skippedCount,
  });

  final int importedCount;
  final int skippedCount;
}

/// Offline `.xlsx` parser and validator. Never reads embedded binary images;
/// `image_filename` is kept strictly as a text reference for `image_path`.
class ExcelImportService {
  const ExcelImportService();

  ExcelImportPreview parseXlsxBytes({
    required String fileName,
    required Uint8List bytes,
    Iterable<Flashcard> existingDeckCards = const [],
  }) {
    final trimmedName = fileName.trim();
    if (!trimmedName.toLowerCase().endsWith('.xlsx')) {
      return ExcelImportPreview(
        fileName: trimmedName,
        fileError: const ExcelImportFileError(
          ExcelImportErrorKind.invalidExtension,
        ),
      );
    }

    if (bytes.isEmpty) {
      return ExcelImportPreview(
        fileName: trimmedName,
        fileError: const ExcelImportFileError(ExcelImportErrorKind.emptyFile),
      );
    }

    final Excel workbook;
    try {
      workbook = Excel.decodeBytes(bytes);
    } catch (e) {
      return ExcelImportPreview(
        fileName: trimmedName,
        fileError: ExcelImportFileError(
          ExcelImportErrorKind.corruptedOrUnreadable,
          details: e.toString(),
        ),
      );
    }

    if (workbook.tables.isEmpty) {
      return ExcelImportPreview(
        fileName: trimmedName,
        fileError: const ExcelImportFileError(ExcelImportErrorKind.emptyFile),
      );
    }

    final sheet = workbook.tables.values.first;
    if (sheet.rows.isEmpty) {
      return ExcelImportPreview(
        fileName: trimmedName,
        fileError: const ExcelImportFileError(ExcelImportErrorKind.emptyFile),
      );
    }

    // Parse header row (row index 0 -> Excel row 1)
    final headerRow = sheet.rows.first;
    final columnIndex = <String, int>{};
    for (var col = 0; col < headerRow.length; col++) {
      final headerText = _cellText(headerRow[col]).toLowerCase();
      if (headerText.isNotEmpty && !columnIndex.containsKey(headerText)) {
        columnIndex[headerText] = col;
      }
    }

    final missing = <String>[
      for (final req in ExcelImportColumns.requiredColumns)
        if (!columnIndex.containsKey(req)) req,
    ];
    if (missing.isNotEmpty) {
      return ExcelImportPreview(
        fileName: trimmedName,
        fileError: ExcelImportFileError(
          ExcelImportErrorKind.missingColumns,
          missingColumns: missing,
        ),
      );
    }

    final targetCol = columnIndex[ExcelImportColumns.targetText]!;
    final assocCol = columnIndex[ExcelImportColumns.associationText];
    final defCol = columnIndex[ExcelImportColumns.definitionText]!;
    final imgCol = columnIndex[ExcelImportColumns.imageFilename];

    final seenKeys = <String>{
      for (final c in existingDeckCards)
        '${c.targetText.trim().toLowerCase()}\u0000${(c.definitionText ?? '').trim().toLowerCase()}',
    };

    final validRows = <FlashcardImportRow>[];
    final invalidRows = <InvalidImportRow>[];
    var skippedDuplicates = 0;

    for (var r = 1; r < sheet.rows.length; r++) {
      final row = sheet.rows[r];
      final excelRowNumber = r + 1;

      final target = _cellAt(row, targetCol);
      final assoc = assocCol == null ? '' : _cellAt(row, assocCol);
      final def = _cellAt(row, defCol);
      final img = imgCol == null ? '' : _cellAt(row, imgCol);

      // Completely blank row -> ignore
      if (target.isEmpty && assoc.isEmpty && def.isEmpty && img.isEmpty) {
        continue;
      }

      if (target.isEmpty) {
        invalidRows.add(
          InvalidImportRow(
            rowNumber: excelRowNumber,
            reason: InvalidRowReason.missingTarget,
          ),
        );
        continue;
      }

      if (def.isEmpty) {
        invalidRows.add(
          InvalidImportRow(
            rowNumber: excelRowNumber,
            reason: InvalidRowReason.missingDefinition,
          ),
        );
        continue;
      }

      final candidate = FlashcardImportRow(
        rowNumber: excelRowNumber,
        targetText: target,
        associationText: assoc.isEmpty ? null : assoc,
        definitionText: def,
        imageFilename: img.isEmpty ? null : img,
      );

      if (!seenKeys.add(candidate.dedupeKey)) {
        skippedDuplicates++;
        continue;
      }

      validRows.add(candidate);
    }

    if (validRows.isEmpty && invalidRows.isEmpty && skippedDuplicates == 0) {
      return ExcelImportPreview(
        fileName: trimmedName,
        fileError: const ExcelImportFileError(ExcelImportErrorKind.emptyFile),
      );
    }

    return ExcelImportPreview(
      fileName: trimmedName,
      validRows: validRows,
      invalidRows: invalidRows,
      skippedDuplicateCount: skippedDuplicates,
    );
  }

  static String _cellAt(List<Data?> row, int col) {
    if (col < 0 || col >= row.length) return '';
    return _cellText(row[col]);
  }

  static String _cellText(Data? cell) {
    final val = cell?.value;
    if (val == null) return '';
    return switch (val) {
      TextCellValue(:final value) => value.text?.trim() ?? '',
      IntCellValue(:final value) => value.toString().trim(),
      DoubleCellValue(:final value) => value.toString().trim(),
      BoolCellValue(:final value) => value.toString().trim(),
      DateCellValue() => val.asDateTimeLocal().toIso8601String(),
      TimeCellValue() => val.toString().trim(),
      DateTimeCellValue() => val.asDateTimeLocal().toIso8601String(),
      FormulaCellValue(:final formula) => formula.trim(),
    };
  }
}
