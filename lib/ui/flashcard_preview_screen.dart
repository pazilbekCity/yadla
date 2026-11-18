import 'package:flutter/material.dart';

import '../data/models/flashcard.dart';
import 'common.dart';
import 'flashcard_image_view.dart';
import 'strings.dart';

/// Basic preview of a [Flashcard]: shows the front (target word, association,
/// and front image if configured) and reveals the back (definition and back
/// image if configured) when the button is pressed.
class FlashcardPreviewScreen extends StatefulWidget {
  const FlashcardPreviewScreen({super.key, required this.card});

  final Flashcard card;

  @override
  State<FlashcardPreviewScreen> createState() => _FlashcardPreviewScreenState();
}

class _FlashcardPreviewScreenState extends State<FlashcardPreviewScreen> {
  bool _revealed = false;
  bool _associationExpanded = false;

  bool get _hasImage {
    final path = widget.card.imagePath;
    return path != null && path.trim().isNotEmpty;
  }

  bool get _showFrontImage =>
      _hasImage &&
      (widget.card.imagePlacement == ImagePlacement.front ||
          widget.card.imagePlacement == ImagePlacement.both);

  bool get _showBackImage =>
      _hasImage &&
      (widget.card.imagePlacement == ImagePlacement.back ||
          widget.card.imagePlacement == ImagePlacement.both);

  @override
  Widget build(BuildContext context) {
    final c = widget.card;
    final assoc = c.associationText;
    final def = c.definitionText;

    return Scaffold(
      appBar: AppBar(title: Text(S.previewTitle)),
      body: CenteredBody(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // 1. Gilt sóz (Target word)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      c.targetText,
                      style: Theme.of(context).textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                    if (_showFrontImage) ...[
                      const SizedBox(height: 16),
                      FlashcardImageView(
                        key: const Key('image-placeholder-front'),
                        path: c.imagePath!,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.tonal(
              key: const Key('toggle-definition'),
              onPressed: () => setState(() => _revealed = !_revealed),
              child: Text(_revealed ? S.hideDefinition : S.showDefinition),
            ),
            // 2. Anıqlama (Definition)
            if (_revealed) ...[
              const SizedBox(height: 16),
              Card(
                key: const Key('definition-card'),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        (def == null || def.isEmpty) ? S.noDefinition : def,
                        style: Theme.of(context).textTheme.bodyLarge,
                        textAlign: TextAlign.center,
                      ),
                      if (c.pageNumber != null &&
                          c.pageNumber!.trim().isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Center(
                          child: Container(
                            key: const Key('preview-page-badge'),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .primaryContainer,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.menu_book_outlined,
                                  size: 14,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onPrimaryContainer,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  S.bookPageBadge(c.pageNumber!.trim()),
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelMedium
                                      ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onPrimaryContainer,
                                        fontWeight: FontWeight.w600,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                      if (_showBackImage) ...[
                        const SizedBox(height: 16),
                        FlashcardImageView(
                          key: const Key('image-placeholder-back'),
                          path: c.imagePath!,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
            // 3. Assotsiaciya (Association) — 3rd in order, collapsible by user
            if (assoc != null && assoc.isNotEmpty) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                key: const Key('toggle-association'),
                onPressed: () => setState(
                  () => _associationExpanded = !_associationExpanded,
                ),
                icon: Icon(
                  _associationExpanded
                      ? Icons.expand_less
                      : Icons.lightbulb_outline,
                ),
                label: Text(
                  _associationExpanded
                      ? S.hideAssociation
                      : S.showAssociation,
                ),
              ),
              if (_associationExpanded) ...[
                const SizedBox(height: 8),
                Card(
                  key: const Key('association-card'),
                  color: Theme.of(context)
                      .colorScheme
                      .secondaryContainer
                      .withValues(alpha: 0.5),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      assoc,
                      style: Theme.of(context).textTheme.bodyLarge,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
