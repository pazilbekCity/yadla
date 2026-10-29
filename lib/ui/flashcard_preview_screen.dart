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
                    if (assoc != null && assoc.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        assoc,
                        style: Theme.of(context).textTheme.bodyLarge,
                        textAlign: TextAlign.center,
                      ),
                    ],
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
          ],
        ),
      ),
    );
  }
}
