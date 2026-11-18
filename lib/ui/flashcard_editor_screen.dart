import 'package:flutter/material.dart';

import '../data/database/app_database_exception.dart';
import '../data/models/flashcard.dart';
import '../data/services/image_storage_service.dart';
import 'app_scope.dart';
import 'common.dart';
import 'flashcard_image_view.dart';
import 'strings.dart';

/// Full-screen form for creating or editing a [Flashcard].
class FlashcardEditorScreen extends StatefulWidget {
  const FlashcardEditorScreen({
    super.key,
    required this.deckId,
    this.existing,
    this.pickImageFile,
    this.imageStorage = const ImageStorageService(),
  });

  final String deckId;
  final Flashcard? existing;
  final ImageFilePicker? pickImageFile;
  final ImageStorageService imageStorage;

  @override
  State<FlashcardEditorScreen> createState() => _FlashcardEditorScreenState();
}

class _FlashcardEditorScreenState extends State<FlashcardEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _target =
      TextEditingController(text: widget.existing?.targetText ?? '');
  late final _association =
      TextEditingController(text: widget.existing?.associationText ?? '');
  late final _definition =
      TextEditingController(text: widget.existing?.definitionText ?? '');
  late final _image =
      TextEditingController(text: widget.existing?.imagePath ?? '');
  late ImagePlacement _placement =
      widget.existing?.imagePlacement ?? ImagePlacement.front;
  bool _associationExpanded = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _image.addListener(_onImageTextChanged);
  }

  void _onImageTextChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _image.removeListener(_onImageTextChanged);
    _target.dispose();
    _association.dispose();
    _definition.dispose();
    _image.dispose();
    super.dispose();
  }

  static String _imageErrorMessage(ImageStorageException e) {
    switch (e.kind) {
      case ImageStorageErrorKind.unsupportedExtension:
        return S.errImageExtension;
      case ImageStorageErrorKind.emptyOrUnreadable:
        return S.errImageEmpty;
      case ImageStorageErrorKind.writeFailed:
        return S.errImageSaveFailed;
    }
  }

  Future<void> _pickImage() async {
    if (_busy) return;
    setState(() => _error = null);
    final picker = widget.pickImageFile ?? defaultImageFilePicker;
    try {
      final picked = await picker();
      if (picked == null || !mounted) return;
      final persistentPath =
          await widget.imageStorage.persistPickedImage(picked);
      if (!mounted) return;
      setState(() {
        _image.text = persistentPath;
      });
    } on ImageStorageException catch (e) {
      if (mounted) {
        setState(() => _error = _imageErrorMessage(e));
      }
    }
  }

  void _clearImage() {
    setState(() {
      _image.clear();
      _error = null;
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final repo = AppScope.of(context).flashcards;
    final target = _target.text.trim();
    final assoc = _association.text.trim();
    final def = _definition.text.trim();
    final img = _image.text.trim();

    try {
      final existing = widget.existing;
      if (existing == null) {
        await repo.create(
          deckId: widget.deckId,
          targetText: target,
          associationText: assoc.isEmpty ? null : assoc,
          definitionText: def.isEmpty ? null : def,
          imagePath: img.isEmpty ? null : img,
          imagePlacement: _placement,
        );
      } else {
        await repo.update(
          existing.copyWith(
            targetText: target,
            associationText: assoc,
            clearAssociation: assoc.isEmpty,
            definitionText: def,
            clearDefinition: def.isEmpty,
            imagePath: img,
            clearImage: img.isEmpty,
            imagePlacement: _placement,
          ),
        );
      }
      if (mounted) Navigator.pop(context, true);
    } on AppDatabaseException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = dbErrorMessage(e);
        });
      }
    }
  }

  static String _placementLabel(ImagePlacement p) {
    switch (p) {
      case ImagePlacement.front:
        return S.placementFront;
      case ImagePlacement.back:
        return S.placementBack;
      case ImagePlacement.both:
        return S.placementBoth;
    }
  }

  @override
  Widget build(BuildContext context) {
    AppScope.languageOf(context);
    final isEdit = widget.existing != null;
    final currentImagePath = _image.text.trim();
    final hasImage = currentImagePath.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? S.editFlashcard : S.addFlashcard),
      ),
      body: CenteredBody(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ListView(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  children: [
                    // 1. Gilt sóz (Target word)
                    TextFormField(
                      key: const Key('card-target'),
                      controller: _target,
                      decoration: InputDecoration(
                        labelText: S.fieldTarget,
                        isDense: true,
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? S.targetRequired
                          : null,
                    ),
                    const SizedBox(height: 8),
                    // 2. Anıqlama (Definition)
                    TextFormField(
                      key: const Key('card-definition'),
                      controller: _definition,
                      decoration: InputDecoration(
                        labelText: S.fieldDefinition,
                        isDense: true,
                      ),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 8),
                    // 3. Assotsiaciya (Association) — collapsible by user
                    if (_associationExpanded)
                      TextFormField(
                        key: const Key('card-association'),
                        controller: _association,
                        decoration: InputDecoration(
                          labelText: S.fieldAssociation,
                          isDense: true,
                          suffixIcon: IconButton(
                            key: const Key('editor-toggle-association'),
                            tooltip: S.hideAssociation,
                            icon: const Icon(Icons.expand_less),
                            onPressed: () => setState(
                              () => _associationExpanded = false,
                            ),
                          ),
                        ),
                        maxLines: 2,
                      )
                    else
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          key: const Key('editor-toggle-association'),
                          onPressed: () => setState(
                            () => _associationExpanded = true,
                          ),
                          icon: const Icon(Icons.lightbulb_outline, size: 18),
                          label: Text(S.showAssociation),
                        ),
                      ),
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: TextFormField(
                            key: const Key('card-image'),
                            controller: _image,
                            decoration: InputDecoration(
                              labelText: S.fieldImage,
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          key: const Key('pick-image-button'),
                          onPressed: _busy ? null : _pickImage,
                          icon: const Icon(Icons.photo_library_outlined),
                          label: Text(hasImage ? S.changeImage : S.pickImage),
                        ),
                        if (hasImage)
                          IconButton(
                            key: const Key('clear-image-button'),
                            tooltip: S.removeImage,
                            onPressed: _busy ? null : _clearImage,
                            icon: const Icon(Icons.clear),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(S.fieldPlacement,
                        style: Theme.of(context).textTheme.labelLarge),
                    const SizedBox(height: 6),
                    SegmentedButton<ImagePlacement>(
                      segments: [
                        for (final p in ImagePlacement.values)
                          ButtonSegment<ImagePlacement>(
                            value: p,
                            label: Text(_placementLabel(p)),
                          ),
                      ],
                      selected: {_placement},
                      onSelectionChanged: (s) =>
                          setState(() => _placement = s.first),
                    ),
                    if (hasImage) ...[
                      const SizedBox(height: 12),
                      FlashcardImageView(
                        key: const Key('editor-image-preview'),
                        path: currentImagePath,
                        maxHeight: 120,
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        key: const Key('editor-error-text'),
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error),
                      ),
                    ],
                  ],
                ),
              ),
              Material(
                color: Theme.of(context).colorScheme.surface,
                elevation: 4,
                child: SafeArea(
                  top: false,
                  minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton(
                      key: const Key('card-save'),
                      onPressed: _busy ? null : _save,
                      child: Text(
                        S.save,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
