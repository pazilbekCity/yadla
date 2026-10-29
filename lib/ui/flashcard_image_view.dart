import 'package:flutter/material.dart';

import '../data/services/image_storage_service.dart';
import 'strings.dart';

/// Displays a flashcard's local image from disk when the referenced file
/// exists and is readable, or a safe Karakalpak fallback placeholder when the
/// path is a bare Excel `image_filename`, missing, deleted, or unreadable.
class FlashcardImageView extends StatelessWidget {
  const FlashcardImageView({
    super.key,
    required this.path,
    this.maxHeight = 220,
  });

  final String path;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    final file = ImageStorageService.resolveLocalImageFile(path);
    if (file == null) {
      return _ImageFallbackBox(path: path);
    }

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.file(
          file,
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) => _ImageFallbackBox(path: path),
        ),
      ),
    );
  }
}

class _ImageFallbackBox extends StatelessWidget {
  const _ImageFallbackBox({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.broken_image_outlined, size: 28),
          const SizedBox(height: 4),
          Text(
            S.imagePlaceholder,
            textAlign: TextAlign.center,
          ),
          Text(
            S.imageMissingOrUnreadable,
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
          Text(
            path,
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
