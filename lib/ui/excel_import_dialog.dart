import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../data/database/app_database_exception.dart';
import '../data/services/excel_import_service.dart';
import 'app_scope.dart';
import 'common.dart';
import 'strings.dart';

/// Raw `.xlsx` file selected by the user.
class PickedXlsxFile {
  const PickedXlsxFile({
    required this.fileName,
    required this.bytes,
  });

  final String fileName;
  final Uint8List bytes;
}

typedef XlsxFilePicker = Future<PickedXlsxFile?> Function();

/// Opens the native device file picker for `.xlsx` files.
Future<PickedXlsxFile?> defaultXlsxFilePicker() async {
  final file = await FilePicker.pickFile(
    type: FileType.custom,
    allowedExtensions: const ['xlsx'],
  );
  if (file == null) return null;
  final bytes = await file.readAsBytes();
  return PickedXlsxFile(
    fileName: file.name,
    bytes: bytes,
  );
}

/// Runs the full Excel import workflow for [deckId]:
/// 1. Pick file (or use injected [pickFile] in tests).
/// 2. Parse & validate rows against existing deck cards without touching DB.
/// 3. Show preview dialog with valid/invalid/duplicate counts.
/// 4. Commit inside a transaction only when the user presses Confirm.
Future<bool> runExcelImportFlow(
  BuildContext context, {
  required String deckId,
  XlsxFilePicker? pickFile,
}) async {
  final db = AppScope.of(context);
  final picker = pickFile ?? defaultXlsxFilePicker;
  final picked = await picker();
  if (picked == null || !context.mounted) return false;

  final existingCards = await db.flashcards.listByDeck(deckId);
  if (!context.mounted) return false;

  final preview = const ExcelImportService().parseXlsxBytes(
    fileName: picked.fileName,
    bytes: picked.bytes,
    existingDeckCards: existingCards,
  );

  final commitResult = await showDialog<ExcelImportCommitResult>(
    context: context,
    barrierDismissible: false,
    builder: (_) => ExcelImportPreviewDialog(
      deckId: deckId,
      preview: preview,
    ),
  );

  if (commitResult != null && context.mounted) {
    final totalSkipped =
        commitResult.skippedCount + preview.invalidRows.length;
    showMessage(
      context,
      S.importSuccessSummary(commitResult.importedCount, totalSkipped),
    );
    return commitResult.importedCount > 0;
  }
  return false;
}

class ExcelImportPreviewDialog extends StatefulWidget {
  const ExcelImportPreviewDialog({
    super.key,
    required this.deckId,
    required this.preview,
  });

  final String deckId;
  final ExcelImportPreview preview;

  @override
  State<ExcelImportPreviewDialog> createState() =>
      _ExcelImportPreviewDialogState();
}

class _ExcelImportPreviewDialogState extends State<ExcelImportPreviewDialog> {
  bool _busy = false;
  String? _dbError;

  static String _fileErrorText(ExcelImportFileError error) {
    switch (error.kind) {
      case ExcelImportErrorKind.invalidExtension:
        return S.errExcelExtension;
      case ExcelImportErrorKind.corruptedOrUnreadable:
        return S.errExcelCorrupted;
      case ExcelImportErrorKind.emptyFile:
        return S.errExcelEmpty;
      case ExcelImportErrorKind.missingColumns:
        return S.errExcelMissingColumns(error.missingColumns);
    }
  }

  static String _rowReasonText(InvalidRowReason reason) {
    switch (reason) {
      case InvalidRowReason.missingTarget:
        return S.reasonMissingTarget;
      case InvalidRowReason.missingDefinition:
        return S.reasonMissingDefinition;
    }
  }

  Future<void> _confirm() async {
    if (_busy || !widget.preview.canImport) return;
    setState(() {
      _busy = true;
      _dbError = null;
    });
    try {
      final result = await AppScope.of(context).flashcards.importBatch(
            deckId: widget.deckId,
            rows: widget.preview.validRows,
            preSkippedCount: widget.preview.skippedDuplicateCount,
          );
      if (mounted) Navigator.pop(context, result);
    } on AppDatabaseException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _dbError = dbErrorMessage(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.preview;
    final fileErr = p.fileError;

    return AlertDialog(
      title: Text(S.importPreviewTitle),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 420),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                S.importFileName(p.fileName),
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 12),
              if (fileErr != null)
                Text(
                  _fileErrorText(fileErr),
                  key: const Key('excel-file-error'),
                  style:
                      TextStyle(color: Theme.of(context).colorScheme.error),
                )
              else ...[
                Text(
                  S.importValidRows(p.validRows.length),
                  key: const Key('preview-valid-count'),
                ),
                const SizedBox(height: 4),
                Text(
                  S.importInvalidRows(p.invalidRows.length),
                  key: const Key('preview-invalid-count'),
                ),
                const SizedBox(height: 4),
                Text(
                  S.importDuplicateRows(p.skippedDuplicateCount),
                  key: const Key('preview-duplicate-count'),
                ),
                if (p.invalidRows.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Divider(),
                  for (final inv in p.invalidRows.take(10))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text(
                        S.importInvalidRowItem(
                          inv.rowNumber,
                          _rowReasonText(inv.reason),
                        ),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                          fontSize: 13,
                        ),
                      ),
                    ),
                ],
                if (p.validRows.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Divider(),
                  for (final row in p.validRows.take(5))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text(
                        '• ${row.targetText} — ${row.definitionText}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                ],
              ],
              if (_dbError != null) ...[
                const SizedBox(height: 12),
                Text(
                  _dbError!,
                  style:
                      TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        if (fileErr != null)
          TextButton(
            key: const Key('close-import-error-button'),
            onPressed: () => Navigator.pop(context),
            child: Text(S.close),
          )
        else ...[
          TextButton(
            key: const Key('cancel-import-button'),
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: Text(S.cancel),
          ),
          FilledButton(
            key: const Key('confirm-import-button'),
            onPressed: (_busy || !p.canImport) ? null : _confirm,
            child: Text(S.confirmImport),
          ),
        ],
      ],
    );
  }
}
