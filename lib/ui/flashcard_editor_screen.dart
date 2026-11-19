import 'package:flutter/material.dart';

import '../data/database/app_database.dart';
import '../data/database/app_database_exception.dart';
import '../data/models/catalog_models.dart';
import '../data/models/flashcard.dart';
import '../data/services/image_storage_service.dart';
import 'app_scope.dart';
import 'common.dart';
import 'flashcard_image_view.dart';
import 'strings.dart';

/// Represents a target `Subject > Book > Topic` (and its default `Deck`) where
/// a flashcard can be created or moved.
class CardDestinationOption {
  const CardDestinationOption({
    required this.subjectId,
    required this.subjectName,
    required this.bookId,
    required this.bookName,
    required this.topicId,
    required this.topicName,
    required this.deckId,
  });

  final String subjectId;
  final String subjectName;
  final String bookId;
  final String bookName;
  final String topicId;
  final String topicName;
  final String deckId;

  String get fullLabel => '$subjectName ➔ $bookName ➔ $topicName';
}

/// Resolves available [CardDestinationOption]s across the database and auto-creates
/// a default fallback topic (`📌 Tez jazbalar` or `Ulıwma`) when the user uses
/// Quick Add (`+ Tez karta` / `+ Karta qosıw`) before creating a full hierarchy.
class QuickCardDestinationResolver {
  const QuickCardDestinationResolver._();

  static const lastActiveTopicSettingKey = 'last_active_topic_id';

  static Future<void> recordLastActiveTopic(
    AppDatabase db,
    String topicId,
  ) async {
    try {
      await db.settings.set(lastActiveTopicSettingKey, topicId);
    } catch (_) {
      // Non-fatal if settings write fails.
    }
  }

  /// Resolves the initial destination and all available destinations when
  /// tapping `+ Tez karta` or `+ Karta qosıw` from:
  /// - Home screen (no [subject] or [book] specified)
  /// - Subject screen ([subject] specified)
  /// - Book screen ([book] specified)
  static Future<({
    CardDestinationOption initial,
    List<CardDestinationOption> all,
  })> resolveForQuickAdd(
    AppDatabase db, {
    Subject? subject,
    Book? book,
  }) async {
    final lastTopicId =
        (await db.settings.get(lastActiveTopicSettingKey))?.value;

    if (book != null) {
      // Ensure this book has at least one topic
      var topics = await db.topics.listByBook(book.id);
      if (topics.isEmpty) {
        final created = await db.topics.create(
          bookId: book.id,
          name: S.generalDefaultName,
        );
        topics = [created];
      }
    } else if (subject != null) {
      // Ensure this subject has at least one book and one topic
      var books = await db.books.listBySubject(subject.id);
      if (books.isEmpty) {
        final createdBook = await db.books.create(
          subjectId: subject.id,
          name: S.generalDefaultName,
        );
        books = [createdBook];
      }
      var hasAnyTopic = false;
      for (final b in books) {
        final tList = await db.topics.listByBook(b.id);
        if (tList.isNotEmpty) {
          hasAnyTopic = true;
          break;
        }
      }
      if (!hasAnyTopic) {
        await db.topics.create(
          bookId: books.first.id,
          name: S.generalDefaultName,
        );
      }
    }

    var allOptions = await loadAllDestinations(db);
    if (allOptions.isEmpty) {
      // Database has no topics yet -> auto-create "Tez jazbalar" hierarchy
      final quickSubj = await _getOrCreateQuickNotesSubject(db);
      var books = await db.books.listBySubject(quickSubj.id);
      if (books.isEmpty) {
        books = [
          await db.books.create(
            subjectId: quickSubj.id,
            name: S.generalDefaultName,
          ),
        ];
      }
      var topics = await db.topics.listByBook(books.first.id);
      if (topics.isEmpty) {
        topics = [
          await db.topics.create(
            bookId: books.first.id,
            name: S.quickNotesSubjectName,
          ),
        ];
      }
      allOptions = await loadAllDestinations(db);
    }

    CardDestinationOption? chosen;
    if (book != null) {
      final inBook = allOptions.where((o) => o.bookId == book.id).toList();
      if (lastTopicId != null) {
        for (final o in inBook) {
          if (o.topicId == lastTopicId) {
            chosen = o;
            break;
          }
        }
      }
      chosen ??= inBook.isNotEmpty ? inBook.first : allOptions.first;
    } else if (subject != null) {
      final inSubj =
          allOptions.where((o) => o.subjectId == subject.id).toList();
      if (lastTopicId != null) {
        for (final o in inSubj) {
          if (o.topicId == lastTopicId) {
            chosen = o;
            break;
          }
        }
      }
      chosen ??= inSubj.isNotEmpty ? inSubj.first : allOptions.first;
    } else {
      if (lastTopicId != null) {
        for (final o in allOptions) {
          if (o.topicId == lastTopicId) {
            chosen = o;
            break;
          }
        }
      }
      chosen ??= allOptions.first;
    }

    return (initial: chosen, all: allOptions);
  }

  static Future<Subject> _getOrCreateQuickNotesSubject(AppDatabase db) async {
    final subjects = await db.subjects.getAll();
    final targetLower = S.quickNotesSubjectName.toLowerCase();
    for (final s in subjects) {
      if (s.name.trim().toLowerCase() == targetLower) {
        return s;
      }
    }
    return db.subjects.create(name: S.quickNotesSubjectName);
  }

  /// Loads every existing `Subject > Book > Topic` in the database and ensures
  /// each topic has a default `Deck`.
  static Future<List<CardDestinationOption>> loadAllDestinations(
    AppDatabase db,
  ) async {
    final result = <CardDestinationOption>[];
    final subjects = await db.subjects.getAll();
    for (final s in subjects) {
      final books = await db.books.listBySubject(s.id);
      for (final b in books) {
        final topics = await db.topics.listByBook(b.id);
        for (final t in topics) {
          final deck = await db.decks.getOrCreateDefaultForTopic(
            t.id,
            defaultName: t.name,
          );
          result.add(
            CardDestinationOption(
              subjectId: s.id,
              subjectName: s.name,
              bookId: b.id,
              bookName: b.name,
              topicId: t.id,
              topicName: t.name,
              deckId: deck.id,
            ),
          );
        }
      }
    }
    return result;
  }
}

/// Shows a dialog allowing the user to pick a target `Subject > Book > Topic`
/// destination (used both in Quick-Add and when moving an existing flashcard).
Future<CardDestinationOption?> showSelectDestinationDialog(
  BuildContext context, {
  required List<CardDestinationOption> options,
  String? currentTopicId,
}) {
  return showDialog<CardDestinationOption>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(S.selectDestinationTopic),
      content: SizedBox(
        width: 400,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 360),
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: options.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (_, index) {
              final opt = options[index];
              final isSelected = opt.topicId == currentTopicId;
              return ListTile(
                key: Key('destination-option-${opt.topicId}'),
                dense: true,
                selected: isSelected,
                leading: Icon(
                  isSelected
                      ? Icons.radio_button_checked
                      : Icons.folder_outlined,
                  size: 20,
                ),
                title: Text(
                  opt.topicName,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text('${opt.subjectName} ➔ ${opt.bookName}'),
                onTap: () => Navigator.pop(ctx, opt),
              );
            },
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(S.cancel),
        ),
      ],
    ),
  );
}

/// Full-screen form for creating or editing a [Flashcard].
class FlashcardEditorScreen extends StatefulWidget {
  const FlashcardEditorScreen({
    super.key,
    required this.deckId,
    this.existing,
    this.pickImageFile,
    this.imageStorage = const ImageStorageService(),
    this.initialDestination,
    this.availableDestinations = const [],
  });

  final String deckId;
  final Flashcard? existing;
  final ImageFilePicker? pickImageFile;
  final ImageStorageService imageStorage;
  final CardDestinationOption? initialDestination;
  final List<CardDestinationOption> availableDestinations;

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
  late CardDestinationOption? _selectedDestination = widget.initialDestination;
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

  Future<void> _changeDestination() async {
    if (_busy || widget.availableDestinations.isEmpty) return;
    final picked = await showSelectDestinationDialog(
      context,
      options: widget.availableDestinations,
      currentTopicId: _selectedDestination?.topicId,
    );
    if (picked != null && mounted) {
      setState(() => _selectedDestination = picked);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final db = AppScope.of(context);
    final repo = db.flashcards;
    final target = _target.text.trim();
    final assoc = _association.text.trim();
    final def = _definition.text.trim();
    final img = _image.text.trim();
    final targetDeckId = _selectedDestination?.deckId ?? widget.deckId;

    try {
      final existing = widget.existing;
      if (existing == null) {
        await repo.create(
          deckId: targetDeckId,
          targetText: target,
          associationText: assoc.isEmpty ? null : assoc,
          definitionText: def.isEmpty ? null : def,
          imagePath: img.isEmpty ? null : img,
          imagePlacement: _placement,
        );
      } else {
        await repo.update(
          existing.copyWith(
            deckId: targetDeckId,
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
      if (_selectedDestination != null) {
        await QuickCardDestinationResolver.recordLastActiveTopic(
          db,
          _selectedDestination!.topicId,
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
                    if (_selectedDestination != null) ...[
                      InkWell(
                        key: const Key('card-destination-selector'),
                        borderRadius: BorderRadius.circular(10),
                        onTap: widget.availableDestinations.length > 1
                            ? _changeDestination
                            : null,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .primaryContainer
                                .withValues(alpha: 0.45),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color:
                                  Theme.of(context).colorScheme.outlineVariant,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.place_outlined,
                                size: 18,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '${S.cardDestinationLabel} ',
                                style: Theme.of(context)
                                    .textTheme
                                    .labelMedium
                                    ?.copyWith(fontWeight: FontWeight.w600),
                              ),
                              Expanded(
                                child: Text(
                                  _selectedDestination!.fullLabel,
                                  key: const Key('card-destination-label'),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelLarge
                                      ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary,
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                              ),
                              if (widget.availableDestinations.length > 1)
                                Icon(
                                  Icons.arrow_drop_down,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
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
