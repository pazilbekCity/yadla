import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../database/migrations.dart';
import '../models/flashcard.dart';
import '../repositories/app_settings_repository.dart';
import '../repositories/backup_repository.dart';
import '../database/app_database.dart';
import 'image_storage_service.dart';

enum BackupErrorKind {
  invalidExtension,
  corruptedJson,
  invalidSchema,
  newerSchemaVersion,
  brokenRelationships,
  corruptedImages,
}

class BackupValidationError {
  const BackupValidationError(this.kind, [this.details]);

  final BackupErrorKind kind;
  final String? details;
}

class EmbeddedBackupImage {
  const EmbeddedBackupImage({
    required this.assetKey,
    required this.fileName,
    required this.bytes,
  });

  final String assetKey;
  final String fileName;
  final Uint8List bytes;
}

class ValidatedBackupPackage {
  const ValidatedBackupPackage({
    required this.snapshot,
    required this.cardImageAssetKeys,
    required this.images,
  });

  final RawDatabaseSnapshot snapshot;

  /// Maps `flashcard.id` -> portable `assetKey` in [images] when the card has
  /// an embedded local image.
  final Map<String, String> cardImageAssetKeys;

  /// Maps portable `assetKey` -> decoded [EmbeddedBackupImage].
  final Map<String, EmbeddedBackupImage> images;

  int get subjectCount => snapshot.subjects.length;
  int get bookCount => snapshot.books.length;
  int get topicCount => snapshot.topics.length;
  int get deckCount => snapshot.decks.length;
  int get flashcardCount => snapshot.flashcards.length;
  int get reviewCount => snapshot.reviewHistory.length;
  int get settingCount => snapshot.appSettings.length;
  int get imageCount => images.length;
}

class BackupParseResult {
  const BackupParseResult._({
    required this.fileName,
    this.package,
    this.error,
  });

  factory BackupParseResult.valid({
    required String fileName,
    required ValidatedBackupPackage package,
  }) =>
      BackupParseResult._(fileName: fileName, package: package);

  factory BackupParseResult.invalid({
    required String fileName,
    required BackupValidationError error,
  }) =>
      BackupParseResult._(fileName: fileName, error: error);

  final String fileName;
  final ValidatedBackupPackage? package;
  final BackupValidationError? error;

  bool get isValid => error == null && package != null;
}

class ExportedBackupBundle {
  const ExportedBackupBundle({
    required this.fileName,
    required this.jsonString,
    required this.bytes,
    required this.savedFilePath,
    required this.subjectCount,
    required this.flashcardCount,
    required this.reviewCount,
    required this.imageCount,
  });

  final String fileName;
  final String jsonString;
  final Uint8List bytes;
  final String? savedFilePath;
  final int subjectCount;
  final int flashcardCount;
  final int reviewCount;
  final int imageCount;
}

/// Service that exports complete offline JSON backups (including embedded
/// base64 card images with portable relative keys) and validates/restores them
/// transactionally.
class BackupService {
  const BackupService({
    this.imageStorage = const ImageStorageService(),
  });

  static const backupFormatId = 'yadla_backup';
  static const backupFormatVersion = 1;
  static const backupsFolderName = 'backups';

  final ImageStorageService imageStorage;

  /// Exports all database tables and locally stored card images into an
  /// offline JSON backup bundle. If [saveToAppDirectory] is true, also writes
  /// the `.json` file into `<appDocsDir>/backups/`.
  Future<ExportedBackupBundle> exportBackup(
    AppDatabase db, {
    bool saveToAppDirectory = true,
  }) async {
    final snapshot = await db.backups.exportRawSnapshot();

    final imagesPayload = <String, Map<String, Object?>>{};
    final sourcePathToAssetKey = <String, String>{};
    final usedAssetKeys = <String>{};

    final exportedFlashcards = <Map<String, Object?>>[];
    for (final rawCard in snapshot.flashcards) {
      final cardMap = Map<String, Object?>.of(rawCard);
      final cardId = cardMap['id'] as String;
      final rawImagePath = cardMap['image_path'] as String?;

      final resolvedFile = ImageStorageService.resolveLocalImageFile(
        rawImagePath,
      );
      if (resolvedFile != null) {
        final canonicalPath = resolvedFile.path;
        var assetKey = sourcePathToAssetKey[canonicalPath];
        if (assetKey == null) {
          final baseName = p.basename(canonicalPath);
          var candidateName = baseName;
          var candidateKey = 'card_images/$candidateName';
          if (usedAssetKeys.contains(candidateKey)) {
            candidateName = '${cardId}_$baseName';
            candidateKey = 'card_images/$candidateName';
          }
          usedAssetKeys.add(candidateKey);
          assetKey = candidateKey;
          sourcePathToAssetKey[canonicalPath] = assetKey;

          final fileBytes = resolvedFile.readAsBytesSync();
          imagesPayload[assetKey] = {
            'file_name': candidateName,
            'bytes_base64': base64Encode(fileBytes),
          };
        }
        // Store portable relative reference instead of device-specific path.
        cardMap['image_path'] = assetKey;
        cardMap['image_asset_key'] = assetKey;
      } else {
        cardMap['image_asset_key'] = null;
      }
      exportedFlashcards.add(cardMap);
    }

    final payload = <String, Object?>{
      'format': backupFormatId,
      'format_version': backupFormatVersion,
      'schema_version': snapshot.schemaVersion,
      'exported_at': snapshot.exportedAtMs,
      'subjects': snapshot.subjects,
      'books': snapshot.books,
      'topics': snapshot.topics,
      'decks': snapshot.decks,
      'flashcards': exportedFlashcards,
      'review_history': snapshot.reviewHistory,
      'app_settings': snapshot.appSettings,
      'images': imagesPayload,
    };

    final jsonString = const JsonEncoder.withIndent('  ').convert(payload);
    final bytes = Uint8List.fromList(utf8.encode(jsonString));
    final fileName = 'yadla_backup_${snapshot.exportedAtMs}.json';

    String? savedPath;
    if (saveToAppDirectory) {
      final baseDir = await imageStorage.getBaseDirectory();
      final backupsDir = Directory(p.join(baseDir.path, backupsFolderName));
      if (!backupsDir.existsSync()) {
        backupsDir.createSync(recursive: true);
      }
      final outFile = File(p.join(backupsDir.path, fileName));
      outFile.writeAsBytesSync(bytes, flush: true);
      savedPath = outFile.path;
    }

    return ExportedBackupBundle(
      fileName: fileName,
      jsonString: jsonString,
      bytes: bytes,
      savedFilePath: savedPath,
      subjectCount: snapshot.subjects.length,
      flashcardCount: snapshot.flashcards.length,
      reviewCount: snapshot.reviewHistory.length,
      imageCount: imagesPayload.length,
    );
  }

  /// Parses and validates a `.json` backup file in memory without touching the
  /// database or disk.
  BackupParseResult parseAndValidate({
    required String fileName,
    required Uint8List bytes,
  }) {
    if (!fileName.trim().toLowerCase().endsWith('.json')) {
      return BackupParseResult.invalid(
        fileName: fileName,
        error: const BackupValidationError(BackupErrorKind.invalidExtension),
      );
    }
    if (bytes.isEmpty) {
      return BackupParseResult.invalid(
        fileName: fileName,
        error: const BackupValidationError(BackupErrorKind.corruptedJson),
      );
    }

    final Map<String, Object?> root;
    try {
      final decodedText = utf8.decode(bytes);
      final decodedJson = jsonDecode(decodedText);
      if (decodedJson is! Map) {
        return BackupParseResult.invalid(
          fileName: fileName,
          error: const BackupValidationError(BackupErrorKind.corruptedJson),
        );
      }
      root = decodedJson.cast<String, Object?>();
    } catch (_) {
      return BackupParseResult.invalid(
        fileName: fileName,
        error: const BackupValidationError(BackupErrorKind.corruptedJson),
      );
    }

    if (root['format'] != backupFormatId ||
        root['format_version'] != backupFormatVersion) {
      return BackupParseResult.invalid(
        fileName: fileName,
        error: const BackupValidationError(BackupErrorKind.invalidSchema),
      );
    }

    final schemaVersion = root['schema_version'];
    final maxSupportedSchema = allMigrations.last.version;
    if (schemaVersion is! int || schemaVersion < 1) {
      return BackupParseResult.invalid(
        fileName: fileName,
        error: const BackupValidationError(BackupErrorKind.invalidSchema),
      );
    }
    if (schemaVersion > maxSupportedSchema) {
      return BackupParseResult.invalid(
        fileName: fileName,
        error: BackupValidationError(
          BackupErrorKind.newerSchemaVersion,
          'v$schemaVersion > v$maxSupportedSchema',
        ),
      );
    }

    final exportedAt = root['exported_at'];
    if (exportedAt is! int) {
      return BackupParseResult.invalid(
        fileName: fileName,
        error: const BackupValidationError(BackupErrorKind.invalidSchema),
      );
    }

    final subjectsRaw = root['subjects'];
    final booksRaw = root['books'];
    final topicsRaw = root['topics'];
    final decksRaw = root['decks'];
    final flashcardsRaw = root['flashcards'];
    final reviewsRaw = root['review_history'];
    final settingsRaw = root['app_settings'];
    final imagesRaw = root['images'] ?? const <String, Object?>{};

    if (subjectsRaw is! List ||
        booksRaw is! List ||
        topicsRaw is! List ||
        decksRaw is! List ||
        flashcardsRaw is! List ||
        reviewsRaw is! List ||
        settingsRaw is! List ||
        imagesRaw is! Map) {
      return BackupParseResult.invalid(
        fileName: fileName,
        error: const BackupValidationError(BackupErrorKind.invalidSchema),
      );
    }

    // 1. Validate embedded images first.
    final parsedImages = <String, EmbeddedBackupImage>{};
    for (final entry in imagesRaw.entries) {
      final key = entry.key;
      final val = entry.value;
      if (key is! String || key.trim().isEmpty || val is! Map) {
        return BackupParseResult.invalid(
          fileName: fileName,
          error: const BackupValidationError(BackupErrorKind.corruptedImages),
        );
      }
      final fileNameField = val['file_name'];
      final base64Field = val['bytes_base64'];
      if (fileNameField is! String ||
          fileNameField.trim().isEmpty ||
          base64Field is! String ||
          base64Field.trim().isEmpty) {
        return BackupParseResult.invalid(
          fileName: fileName,
          error: const BackupValidationError(BackupErrorKind.corruptedImages),
        );
      }
      final extRaw = p.extension(fileNameField).toLowerCase();
      final ext = extRaw.startsWith('.') ? extRaw.substring(1) : extRaw;
      if (ext.isEmpty || !kAllowedImageExtensions.contains(ext)) {
        return BackupParseResult.invalid(
          fileName: fileName,
          error: const BackupValidationError(BackupErrorKind.corruptedImages),
        );
      }
      try {
        final decodedBytes = base64Decode(base64Field);
        if (decodedBytes.isEmpty) {
          return BackupParseResult.invalid(
            fileName: fileName,
            error: const BackupValidationError(BackupErrorKind.corruptedImages),
          );
        }
        parsedImages[key] = EmbeddedBackupImage(
          assetKey: key,
          fileName: p.basename(fileNameField.trim()),
          bytes: decodedBytes,
        );
      } catch (_) {
        return BackupParseResult.invalid(
          fileName: fileName,
          error: const BackupValidationError(BackupErrorKind.corruptedImages),
        );
      }
    }

    // 2. Validate subjects.
    final subjects = <Map<String, Object?>>[];
    final subjectIds = <String>{};
    final subjectNames = <String>{};
    for (final item in subjectsRaw) {
      if (item is! Map) {
        return BackupParseResult.invalid(
          fileName: fileName,
          error: const BackupValidationError(BackupErrorKind.invalidSchema),
        );
      }
      final m = item.cast<String, Object?>();
      final id = _nonEmptyString(m['id']);
      final name = _nonEmptyString(m['name']);
      final createdAt = m['created_at'];
      final updatedAt = m['updated_at'];
      final desc = m['description'];
      if (id == null ||
          name == null ||
          createdAt is! int ||
          updatedAt is! int ||
          (desc != null && desc is! String)) {
        return BackupParseResult.invalid(
          fileName: fileName,
          error: const BackupValidationError(BackupErrorKind.invalidSchema),
        );
      }
      if (!subjectIds.add(id) || !subjectNames.add(name)) {
        return BackupParseResult.invalid(
          fileName: fileName,
          error: const BackupValidationError(BackupErrorKind.invalidSchema),
        );
      }
      subjects.add({
        'id': id,
        'name': name,
        'description': desc,
        'created_at': createdAt,
        'updated_at': updatedAt,
      });
    }

    // 3. Validate books.
    final books = <Map<String, Object?>>[];
    final bookIds = <String>{};
    final bookSiblingKeys = <String>{};
    for (final item in booksRaw) {
      if (item is! Map) {
        return BackupParseResult.invalid(
          fileName: fileName,
          error: const BackupValidationError(BackupErrorKind.invalidSchema),
        );
      }
      final m = item.cast<String, Object?>();
      final id = _nonEmptyString(m['id']);
      final subjectId = _nonEmptyString(m['subject_id']);
      final name = _nonEmptyString(m['name']);
      final createdAt = m['created_at'];
      final updatedAt = m['updated_at'];
      final desc = m['description'];
      if (id == null ||
          subjectId == null ||
          name == null ||
          createdAt is! int ||
          updatedAt is! int ||
          (desc != null && desc is! String)) {
        return BackupParseResult.invalid(
          fileName: fileName,
          error: const BackupValidationError(BackupErrorKind.invalidSchema),
        );
      }
      if (!subjectIds.contains(subjectId)) {
        return BackupParseResult.invalid(
          fileName: fileName,
          error:
              const BackupValidationError(BackupErrorKind.brokenRelationships),
        );
      }
      if (!bookIds.add(id) || !bookSiblingKeys.add('$subjectId\u0000$name')) {
        return BackupParseResult.invalid(
          fileName: fileName,
          error: const BackupValidationError(BackupErrorKind.invalidSchema),
        );
      }
      books.add({
        'id': id,
        'subject_id': subjectId,
        'name': name,
        'description': desc,
        'created_at': createdAt,
        'updated_at': updatedAt,
      });
    }

    // 4. Validate topics.
    final topics = <Map<String, Object?>>[];
    final topicIds = <String>{};
    final topicSiblingKeys = <String>{};
    for (final item in topicsRaw) {
      if (item is! Map) {
        return BackupParseResult.invalid(
          fileName: fileName,
          error: const BackupValidationError(BackupErrorKind.invalidSchema),
        );
      }
      final m = item.cast<String, Object?>();
      final id = _nonEmptyString(m['id']);
      final bookId = _nonEmptyString(m['book_id']);
      final name = _nonEmptyString(m['name']);
      final createdAt = m['created_at'];
      final updatedAt = m['updated_at'];
      final desc = m['description'];
      if (id == null ||
          bookId == null ||
          name == null ||
          createdAt is! int ||
          updatedAt is! int ||
          (desc != null && desc is! String)) {
        return BackupParseResult.invalid(
          fileName: fileName,
          error: const BackupValidationError(BackupErrorKind.invalidSchema),
        );
      }
      if (!bookIds.contains(bookId)) {
        return BackupParseResult.invalid(
          fileName: fileName,
          error:
              const BackupValidationError(BackupErrorKind.brokenRelationships),
        );
      }
      if (!topicIds.add(id) || !topicSiblingKeys.add('$bookId\u0000$name')) {
        return BackupParseResult.invalid(
          fileName: fileName,
          error: const BackupValidationError(BackupErrorKind.invalidSchema),
        );
      }
      topics.add({
        'id': id,
        'book_id': bookId,
        'name': name,
        'description': desc,
        'created_at': createdAt,
        'updated_at': updatedAt,
      });
    }

    // 5. Validate decks.
    final decks = <Map<String, Object?>>[];
    final deckIds = <String>{};
    final deckSiblingKeys = <String>{};
    for (final item in decksRaw) {
      if (item is! Map) {
        return BackupParseResult.invalid(
          fileName: fileName,
          error: const BackupValidationError(BackupErrorKind.invalidSchema),
        );
      }
      final m = item.cast<String, Object?>();
      final id = _nonEmptyString(m['id']);
      final topicId = _nonEmptyString(m['topic_id']);
      final name = _nonEmptyString(m['name']);
      final createdAt = m['created_at'];
      final updatedAt = m['updated_at'];
      final desc = m['description'];
      if (id == null ||
          topicId == null ||
          name == null ||
          createdAt is! int ||
          updatedAt is! int ||
          (desc != null && desc is! String)) {
        return BackupParseResult.invalid(
          fileName: fileName,
          error: const BackupValidationError(BackupErrorKind.invalidSchema),
        );
      }
      if (!topicIds.contains(topicId)) {
        return BackupParseResult.invalid(
          fileName: fileName,
          error:
              const BackupValidationError(BackupErrorKind.brokenRelationships),
        );
      }
      if (!deckIds.add(id) || !deckSiblingKeys.add('$topicId\u0000$name')) {
        return BackupParseResult.invalid(
          fileName: fileName,
          error: const BackupValidationError(BackupErrorKind.invalidSchema),
        );
      }
      decks.add({
        'id': id,
        'topic_id': topicId,
        'name': name,
        'description': desc,
        'created_at': createdAt,
        'updated_at': updatedAt,
      });
    }

    // 6. Validate flashcards & image asset references.
    final flashcards = <Map<String, Object?>>[];
    final flashcardIds = <String>{};
    final cardImageAssetKeys = <String, String>{};
    for (final item in flashcardsRaw) {
      if (item is! Map) {
        return BackupParseResult.invalid(
          fileName: fileName,
          error: const BackupValidationError(BackupErrorKind.invalidSchema),
        );
      }
      final m = item.cast<String, Object?>();
      final id = _nonEmptyString(m['id']);
      final deckId = _nonEmptyString(m['deck_id']);
      final targetText = _nonEmptyString(m['target_text']);
      final assoc = m['association_text'];
      final def = m['definition_text'];
      final imgPath = m['image_path'];
      final imgAssetKey = m['image_asset_key'];
      final placementStr = m['image_placement'] ?? 'front';
      final statusStr = m['status'] ?? 'learning';
      final statusChangedAt = m['status_changed_at'];
      final createdAt = m['created_at'];
      final updatedAt = m['updated_at'];

      if (id == null ||
          deckId == null ||
          targetText == null ||
          (assoc != null && assoc is! String) ||
          (def != null && def is! String) ||
          (imgPath != null && _nonEmptyString(imgPath) == null) ||
          (imgAssetKey != null && imgAssetKey is! String) ||
          placementStr is! String ||
          statusStr is! String ||
          (statusChangedAt != null && statusChangedAt is! int) ||
          createdAt is! int ||
          updatedAt is! int) {
        return BackupParseResult.invalid(
          fileName: fileName,
          error: const BackupValidationError(BackupErrorKind.invalidSchema),
        );
      }
      if (!deckIds.contains(deckId)) {
        return BackupParseResult.invalid(
          fileName: fileName,
          error:
              const BackupValidationError(BackupErrorKind.brokenRelationships),
        );
      }
      try {
        ImagePlacement.parse(placementStr);
        CardStatus.parse(statusStr);
      } on FormatException {
        return BackupParseResult.invalid(
          fileName: fileName,
          error: const BackupValidationError(BackupErrorKind.invalidSchema),
        );
      }
      if (!flashcardIds.add(id)) {
        return BackupParseResult.invalid(
          fileName: fileName,
          error: const BackupValidationError(BackupErrorKind.invalidSchema),
        );
      }

      final resolvedAssetKey = _nonEmptyString(imgAssetKey) ??
          (imgPath is String && parsedImages.containsKey(imgPath)
              ? imgPath
              : null);
      if (resolvedAssetKey != null) {
        if (!parsedImages.containsKey(resolvedAssetKey)) {
          return BackupParseResult.invalid(
            fileName: fileName,
            error: const BackupValidationError(BackupErrorKind.corruptedImages),
          );
        }
        cardImageAssetKeys[id] = resolvedAssetKey;
      }

      flashcards.add({
        'id': id,
        'deck_id': deckId,
        'target_text': targetText,
        'association_text': _nonEmptyString(assoc),
        'definition_text': _nonEmptyString(def),
        'image_path': _nonEmptyString(imgPath),
        'image_placement': placementStr,
        'status': statusStr,
        'status_changed_at': statusChangedAt,
        'created_at': createdAt,
        'updated_at': updatedAt,
      });
    }

    // 7. Validate review_history.
    final reviewHistory = <Map<String, Object?>>[];
    final reviewIds = <String>{};
    for (final item in reviewsRaw) {
      if (item is! Map) {
        return BackupParseResult.invalid(
          fileName: fileName,
          error: const BackupValidationError(BackupErrorKind.invalidSchema),
        );
      }
      final m = item.cast<String, Object?>();
      final id = _nonEmptyString(m['id']);
      final flashcardId = _nonEmptyString(m['flashcard_id']);
      final reviewedAt = m['reviewed_at'];
      final rating = m['rating'];
      final dueAt = m['due_at'];
      final intervalDays = m['interval_days'];
      final easeFactor = m['ease_factor'];
      final responseTimeMs = m['response_time_ms'];
      final sessionId = m['session_id'];

      if (id == null ||
          flashcardId == null ||
          reviewedAt is! int ||
          rating is! int ||
          rating < 1 ||
          rating > 4 ||
          (dueAt != null && dueAt is! int) ||
          (intervalDays != null &&
              (intervalDays is! int || intervalDays < 0)) ||
          (easeFactor != null &&
              (easeFactor is! num || easeFactor.toDouble() <= 0)) ||
          (responseTimeMs != null &&
              (responseTimeMs is! int || responseTimeMs < 0)) ||
          (sessionId != null && sessionId is! String)) {
        return BackupParseResult.invalid(
          fileName: fileName,
          error: const BackupValidationError(BackupErrorKind.invalidSchema),
        );
      }
      if (!flashcardIds.contains(flashcardId)) {
        return BackupParseResult.invalid(
          fileName: fileName,
          error:
              const BackupValidationError(BackupErrorKind.brokenRelationships),
        );
      }
      if (!reviewIds.add(id)) {
        return BackupParseResult.invalid(
          fileName: fileName,
          error: const BackupValidationError(BackupErrorKind.invalidSchema),
        );
      }
      reviewHistory.add({
        'id': id,
        'flashcard_id': flashcardId,
        'reviewed_at': reviewedAt,
        'rating': rating,
        'due_at': dueAt,
        'interval_days': intervalDays,
        'ease_factor': (easeFactor as num?)?.toDouble(),
        'response_time_ms': responseTimeMs,
        'session_id': _nonEmptyString(sessionId),
      });
    }

    // 8. Validate app_settings.
    final appSettings = <Map<String, Object?>>[];
    final settingKeys = <String>{};
    for (final item in settingsRaw) {
      if (item is! Map) {
        return BackupParseResult.invalid(
          fileName: fileName,
          error: const BackupValidationError(BackupErrorKind.invalidSchema),
        );
      }
      final m = item.cast<String, Object?>();
      final key = _nonEmptyString(m['key']);
      final value = m['value'];
      final updatedAt = m['updated_at'];
      if (key == null || value is! String || updatedAt is! int) {
        return BackupParseResult.invalid(
          fileName: fileName,
          error: const BackupValidationError(BackupErrorKind.invalidSchema),
        );
      }
      if (key == AppSettingsRepository.interfaceLanguageKey &&
          !AppSettingsRepository.supportedLanguages.contains(value)) {
        return BackupParseResult.invalid(
          fileName: fileName,
          error: const BackupValidationError(BackupErrorKind.invalidSchema),
        );
      }
      if (!settingKeys.add(key)) {
        return BackupParseResult.invalid(
          fileName: fileName,
          error: const BackupValidationError(BackupErrorKind.invalidSchema),
        );
      }
      appSettings.add({
        'key': key,
        'value': value,
        'updated_at': updatedAt,
      });
    }

    final snapshot = RawDatabaseSnapshot(
      schemaVersion: schemaVersion,
      exportedAtMs: exportedAt,
      subjects: subjects,
      books: books,
      topics: topics,
      decks: decks,
      flashcards: flashcards,
      reviewHistory: reviewHistory,
      appSettings: appSettings,
    );

    return BackupParseResult.valid(
      fileName: fileName,
      package: ValidatedBackupPackage(
        snapshot: snapshot,
        cardImageAssetKeys: cardImageAssetKeys,
        images: parsedImages,
      ),
    );
  }

  /// Restores a validated backup [package] into [db] using [mode].
  ///
  /// 1. Writes embedded images into the current device's persistent
  ///    `<appDocsDir>/card_images/` directory so restored cards have valid
  ///    local image paths independent of the original device.
  /// 2. Commits all database changes inside a single SQLite transaction. If
  ///    the transaction fails, newly written image files are cleaned up and
  ///    existing database data remains untouched.
  Future<RestoreCommitSummary> restoreValidatedBackup({
    required AppDatabase db,
    required ValidatedBackupPackage package,
    required RestoreMode mode,
  }) async {
    final writtenFiles = <File>[];
    final assetKeyToNewLocalPath = <String, String>{};

    try {
      for (final entry in package.images.entries) {
        final newLocalPath = await imageStorage.persistPickedImage(
          PickedImageFile(
            fileName: entry.value.fileName,
            bytes: entry.value.bytes,
          ),
        );
        writtenFiles.add(File(newLocalPath));
        assetKeyToNewLocalPath[entry.key] = newLocalPath;
      }

      final resolvedCardImagePaths = <String, String>{};
      for (final entry in package.cardImageAssetKeys.entries) {
        final localPath = assetKeyToNewLocalPath[entry.value];
        if (localPath != null) {
          resolvedCardImagePaths[entry.key] = localPath;
        }
      }

      return await db.backups.restoreRawSnapshot(
        snapshot: package.snapshot,
        mode: mode,
        resolvedCardImagePaths: resolvedCardImagePaths,
        imagesRestoredCount: assetKeyToNewLocalPath.length,
      );
    } catch (_) {
      for (final f in writtenFiles) {
        try {
          if (f.existsSync()) f.deleteSync();
        } catch (_) {}
      }
      rethrow;
    }
  }

  static String? _nonEmptyString(Object? v) {
    if (v is! String) return null;
    final t = v.trim();
    return t.isEmpty ? null : t;
  }
}
