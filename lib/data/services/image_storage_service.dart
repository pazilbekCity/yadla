import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../database/ids.dart';

/// Allowed image file extensions for flashcard images.
const Set<String> kAllowedImageExtensions = {
  'png',
  'jpg',
  'jpeg',
  'webp',
  'gif',
  'bmp',
};

/// Raw image picked by the user from device storage.
class PickedImageFile {
  const PickedImageFile({
    required this.fileName,
    required this.bytes,
  });

  final String fileName;
  final Uint8List bytes;
}

typedef ImageFilePicker = Future<PickedImageFile?> Function();
typedef DirectoryProvider = Future<Directory> Function();

/// Opens the native file picker for supported image files.
Future<PickedImageFile?> defaultImageFilePicker() async {
  final file = await FilePicker.pickFile(
    type: FileType.custom,
    allowedExtensions: kAllowedImageExtensions.toList(),
  );
  if (file == null) return null;
  final bytes = await file.readAsBytes();
  return PickedImageFile(
    fileName: file.name,
    bytes: bytes,
  );
}

enum ImageStorageErrorKind {
  unsupportedExtension,
  emptyOrUnreadable,
  writeFailed,
}

class ImageStorageException implements Exception {
  const ImageStorageException(this.kind, [this.cause]);

  final ImageStorageErrorKind kind;
  final Object? cause;
}

/// Manages copying user-selected images into the app's persistent local
/// directory (`<appDocsDir>/card_images/`) and resolving stored image paths.
class ImageStorageService {
  const ImageStorageService({
    DirectoryProvider? getBaseDirectory,
  }) : _getBaseDirectory = getBaseDirectory ?? getApplicationDocumentsDirectory;

  static const folderName = 'card_images';

  final DirectoryProvider _getBaseDirectory;

  /// Returns the base application documents directory.
  Future<Directory> getBaseDirectory() => _getBaseDirectory();

  /// Validates [picked] and copies its bytes into persistent app storage,
  /// returning the absolute persistent file path to store in
  /// `Flashcard.imagePath`.
  Future<String> persistPickedImage(PickedImageFile picked) async {
    final extRaw = p.extension(picked.fileName).toLowerCase();
    final ext = extRaw.startsWith('.') ? extRaw.substring(1) : extRaw;
    if (ext.isEmpty || !kAllowedImageExtensions.contains(ext)) {
      throw const ImageStorageException(
        ImageStorageErrorKind.unsupportedExtension,
      );
    }
    if (picked.bytes.isEmpty) {
      throw const ImageStorageException(
        ImageStorageErrorKind.emptyOrUnreadable,
      );
    }

    try {
      final baseDir = await _getBaseDirectory();
      final imagesDir = Directory(p.join(baseDir.path, folderName));
      if (!imagesDir.existsSync()) {
        imagesDir.createSync(recursive: true);
      }
      final storedFileName = '${generateId()}.$ext';
      final destination = File(p.join(imagesDir.path, storedFileName));
      destination.writeAsBytesSync(picked.bytes, flush: true);
      return destination.path;
    } catch (e) {
      throw ImageStorageException(ImageStorageErrorKind.writeFailed, e);
    }
  }

  /// Resolves [imagePath] to a readable local [File] only if the file
  /// actually exists on disk and is non-empty.
  ///
  /// - Bare filenames imported from Excel (`image_filename`) that do not match
  ///   an actual file on disk return `null` so the UI shows a safe placeholder
  ///   instead of treating them as valid local paths.
  static File? resolveLocalImageFile(String? imagePath) {
    final trimmed = imagePath?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    try {
      final file = File(trimmed);
      if (file.existsSync() && file.lengthSync() > 0) {
        return file;
      }
    } on FileSystemException {
      return null;
    }
    return null;
  }
}
