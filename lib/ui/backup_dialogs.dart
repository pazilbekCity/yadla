import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../data/database/app_database_exception.dart';
import '../data/repositories/backup_repository.dart';
import '../data/services/backup_service.dart';
import 'app_scope.dart';
import 'common.dart';
import 'strings.dart';

/// Raw `.json` backup file selected by the user.
class PickedBackupFile {
  const PickedBackupFile({
    required this.fileName,
    required this.bytes,
  });

  final String fileName;
  final Uint8List bytes;
}

typedef BackupFilePicker = Future<PickedBackupFile?> Function();

/// Opens the native device file picker for `.json` backup files.
Future<PickedBackupFile?> defaultBackupFilePicker() async {
  final file = await FilePicker.pickFile(
    type: FileType.custom,
    allowedExtensions: const ['json'],
  );
  if (file == null) return null;
  final bytes = await file.readAsBytes();
  return PickedBackupFile(
    fileName: file.name,
    bytes: bytes,
  );
}

/// Exports a full offline JSON backup and displays a localized confirmation
/// message with the saved path and item counts.
Future<ExportedBackupBundle?> runBackupExportFlow(
  BuildContext context, {
  BackupService backupService = const BackupService(),
}) async {
  final db = AppScope.of(context);
  try {
    final bundle = await backupService.exportBackup(db);
    if (context.mounted) {
      showMessage(
        context,
        S.backupExportSuccess(
          bundle.savedFilePath ?? bundle.fileName,
          bundle.flashcardCount,
          bundle.imageCount,
        ),
      );
    }
    return bundle;
  } on AppDatabaseException catch (e) {
    if (context.mounted) {
      showMessage(context, dbErrorMessage(e));
    }
    return null;
  } catch (e) {
    if (context.mounted) {
      showMessage(context, S.loadError(e));
    }
    return null;
  }
}

/// Runs the full offline JSON backup restore workflow:
/// 1. Picks a `.json` file (or uses [pickFile] in tests).
/// 2. Validates format, schema version, relationships, and embedded images in
///    memory without modifying the database.
/// 3. Shows a confirmation dialog (with merge vs. replace choice if the
///    database already contains user data).
/// 4. Executes the transactional restore only when the user confirms.
Future<bool> runBackupRestoreFlow(
  BuildContext context, {
  BackupFilePicker? pickFile,
  BackupService backupService = const BackupService(),
}) async {
  final db = AppScope.of(context);
  final picker = pickFile ?? defaultBackupFilePicker;
  final picked = await picker();
  if (picked == null || !context.mounted) return false;

  final parseResult = backupService.parseAndValidate(
    fileName: picked.fileName,
    bytes: picked.bytes,
  );
  final hasExistingData = await db.backups.hasExistingUserData();
  if (!context.mounted) return false;

  final commitSummary = await showDialog<RestoreCommitSummary>(
    context: context,
    barrierDismissible: false,
    builder: (_) => BackupRestorePreviewDialog(
      parseResult: parseResult,
      hasExistingData: hasExistingData,
      backupService: backupService,
    ),
  );

  if (commitSummary != null && context.mounted) {
    await AppScope.syncLanguageFromDatabase(context);
    if (context.mounted) {
      showMessage(
        context,
        S.restoreSuccessSummary(
          commitSummary.flashcardsRestored,
          commitSummary.reviewsRestored,
          commitSummary.imagesRestored,
        ),
      );
    }
    return true;
  }
  return false;
}

class BackupRestorePreviewDialog extends StatefulWidget {
  const BackupRestorePreviewDialog({
    super.key,
    required this.parseResult,
    required this.hasExistingData,
    this.backupService = const BackupService(),
  });

  final BackupParseResult parseResult;
  final bool hasExistingData;
  final BackupService backupService;

  @override
  State<BackupRestorePreviewDialog> createState() =>
      _BackupRestorePreviewDialogState();
}

class _BackupRestorePreviewDialogState
    extends State<BackupRestorePreviewDialog> {
  late RestoreMode _mode = widget.hasExistingData
      ? RestoreMode.mergeKeepExisting
      : RestoreMode.replaceAll;
  bool _busy = false;
  String? _dbError;

  static String _validationErrorText(BackupValidationError error) {
    switch (error.kind) {
      case BackupErrorKind.invalidExtension:
        return S.errBackupExtension;
      case BackupErrorKind.corruptedJson:
        return S.errBackupCorruptedJson;
      case BackupErrorKind.invalidSchema:
        return S.errBackupInvalidSchema;
      case BackupErrorKind.newerSchemaVersion:
        return S.errBackupNewerSchema;
      case BackupErrorKind.brokenRelationships:
        return S.errBackupBrokenRelationships;
      case BackupErrorKind.corruptedImages:
        return S.errBackupCorruptedImages;
    }
  }

  Future<void> _confirm() async {
    final pkg = widget.parseResult.package;
    if (_busy || pkg == null) return;
    setState(() {
      _busy = true;
      _dbError = null;
    });
    final db = AppScope.of(context);
    try {
      final summary = await widget.backupService.restoreValidatedBackup(
        db: db,
        package: pkg,
        mode: _mode,
      );
      if (mounted) Navigator.pop(context, summary);
    } on AppDatabaseException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _dbError = dbErrorMessage(e);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _dbError = S.loadError(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    AppScope.languageOf(context);
    final res = widget.parseResult;
    final valErr = res.error;
    final pkg = res.package;

    return AlertDialog(
      title: Text(S.restorePreviewTitle),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 420),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                S.importFileName(res.fileName),
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 12),
              if (valErr != null)
                Text(
                  _validationErrorText(valErr),
                  key: const Key('backup-error-text'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                )
              else if (pkg != null) ...[
                Text(
                  S.restoreSummaryCounts(
                    pkg.subjectCount,
                    pkg.deckCount,
                    pkg.flashcardCount,
                    pkg.reviewCount,
                    pkg.imageCount,
                  ),
                  key: const Key('backup-preview-summary'),
                ),
                if (widget.hasExistingData) ...[
                  const SizedBox(height: 16),
                  Text(
                    S.restoreExistingDataWarning,
                    key: const Key('backup-existing-data-warning'),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 8),
                  _RestoreModeTile(
                    tileKey: const Key('restore-mode-merge'),
                    title: S.restoreModeMerge,
                    selected: _mode == RestoreMode.mergeKeepExisting,
                    enabled: !_busy,
                    onTap: () =>
                        setState(() => _mode = RestoreMode.mergeKeepExisting),
                  ),
                  _RestoreModeTile(
                    tileKey: const Key('restore-mode-replace'),
                    title: S.restoreModeReplace,
                    selected: _mode == RestoreMode.replaceAll,
                    enabled: !_busy,
                    onTap: () =>
                        setState(() => _mode = RestoreMode.replaceAll),
                  ),
                ],
              ],
              if (_dbError != null) ...[
                const SizedBox(height: 12),
                Text(
                  _dbError!,
                  key: const Key('backup-db-error-text'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        if (valErr != null)
          TextButton(
            key: const Key('close-backup-error-button'),
            onPressed: () => Navigator.pop(context),
            child: Text(S.close),
          )
        else ...[
          TextButton(
            key: const Key('cancel-restore-button'),
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: Text(S.cancel),
          ),
          FilledButton(
            key: const Key('confirm-restore-button'),
            onPressed: (_busy || !res.isValid) ? null : _confirm,
            child: Text(S.confirmRestore),
          ),
        ],
      ],
    );
  }
}

class _RestoreModeTile extends StatelessWidget {
  const _RestoreModeTile({
    required this.tileKey,
    required this.title,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final Key tileKey;
  final String title;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: tileKey,
      contentPadding: EdgeInsets.zero,
      dense: true,
      enabled: enabled,
      onTap: enabled ? onTap : null,
      leading: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
        color: selected ? Theme.of(context).colorScheme.primary : null,
      ),
      title: Text(title),
    );
  }
}
