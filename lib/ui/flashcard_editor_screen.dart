import 'package:flutter/material.dart';

import '../data/database/app_database.dart';
import '../data/database/app_database_exception.dart';
import '../data/models/catalog_models.dart';
import '../data/models/flashcard.dart';
import '../data/repositories/repository_base.dart';
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

  Subject? _selectedSubject;
  Book? _selectedBook;
  Topic? _selectedTopic;
  bool _hierarchyInitialized = false;

  bool _associationExpanded = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _image.addListener(_onImageTextChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_hierarchyInitialized) {
      _hierarchyInitialized = true;
      _initHierarchy();
    }
  }

  Future<List<Book>> _loadAllBooks(AppDatabase db) async {
    final subjects = await db.subjects.getAll();
    final allBooks = <Book>[];
    for (final s in subjects) {
      allBooks.addAll(await db.books.listBySubject(s.id));
    }
    return allBooks;
  }

  Future<List<Topic>> _loadAllTopics(AppDatabase db) async {
    final books = await _loadAllBooks(db);
    final allTopics = <Topic>[];
    for (final b in books) {
      allTopics.addAll(await db.topics.listByBook(b.id));
    }
    return allTopics;
  }

  Future<void> _initHierarchy() async {
    final db = AppScope.of(context);

    if (widget.initialDestination != null) {
      final dest = widget.initialDestination!;
      final s = await db.subjects.getById(dest.subjectId);
      final b = await db.books.getById(dest.bookId);
      final t = await db.topics.getById(dest.topicId);
      if (mounted) {
        setState(() {
          _selectedSubject = s;
          _selectedBook = b;
          _selectedTopic = t;
        });
      }
      return;
    }

    if (widget.deckId.isNotEmpty) {
      try {
        final deck = await db.decks.getById(widget.deckId);
        if (deck != null) {
          final topic = await db.topics.getById(deck.topicId);
          if (topic != null) {
            final book = await db.books.getById(topic.bookId);
            final subject =
                book != null ? await db.subjects.getById(book.subjectId) : null;
            if (mounted) {
              setState(() {
                _selectedTopic = topic;
                _selectedBook = book;
                _selectedSubject = subject;
              });
            }
          }
        }
      } catch (_) {
        // Fallback gracefully if deck resolution fails.
      }
    }
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

  void _clearAllSelections() {
    setState(() {
      _selectedSubject = null;
      _selectedBook = null;
      _selectedTopic = null;
    });
  }

  Future<void> _pickSubject() async {
    final db = AppScope.of(context);
    final subjects = await db.subjects.getAll();
    if (!mounted) return;
    if (subjects.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.noClassesFound)),
      );
      return;
    }

    final picked = await showDialog<Subject>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(S.selectBookDialogTitle),
        content: SizedBox(
          width: 400,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 360),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: subjects.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (_, index) {
                final s = subjects[index];
                final isSelected = s.id == _selectedSubject?.id;
                return ListTile(
                  dense: true,
                  selected: isSelected,
                  leading: Icon(
                    isSelected
                        ? Icons.radio_button_checked
                        : Icons.menu_book_outlined,
                    size: 20,
                  ),
                  title: Text(
                    s.name,
                    style: TextStyle(
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.w600,
                    ),
                  ),
                  onTap: () => Navigator.pop(ctx, s),
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

    if (picked != null && mounted) {
      setState(() {
        _selectedSubject = picked;
        if (_selectedBook != null && _selectedBook!.subjectId != picked.id) {
          _selectedBook = null;
          _selectedTopic = null;
        }
      });
    }
  }

  Future<void> _pickBook() async {
    final db = AppScope.of(context);
    List<Book> books;
    if (_selectedSubject != null) {
      books = await db.books.listBySubject(_selectedSubject!.id);
    } else {
      books = await _loadAllBooks(db);
    }
    books.sort((a, b) => compareNaturalNames(a.name, b.name));

    if (!mounted) return;
    if (books.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.noClassesFound)),
      );
      return;
    }

    final allSubjects = await db.subjects.getAll();
    final subjectMap = {for (final s in allSubjects) s.id: s.name};

    if (!mounted) return;
    final picked = await showDialog<Book>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(S.selectClassDialogTitle),
        content: SizedBox(
          width: 400,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 360),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: books.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (_, index) {
                final b = books[index];
                final isSelected = b.id == _selectedBook?.id;
                final subjName = subjectMap[b.subjectId];
                return ListTile(
                  dense: true,
                  selected: isSelected,
                  leading: Icon(
                    isSelected
                        ? Icons.radio_button_checked
                        : Icons.folder_outlined,
                    size: 20,
                  ),
                  title: Text(
                    b.name,
                    style: TextStyle(
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.w600,
                    ),
                  ),
                  subtitle: (_selectedSubject == null && subjName != null)
                      ? Text(subjName)
                      : null,
                  onTap: () => Navigator.pop(ctx, b),
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

    if (picked != null && mounted) {
      Subject? newSubj = _selectedSubject;
      if (newSubj == null || newSubj.id != picked.subjectId) {
        newSubj = await db.subjects.getById(picked.subjectId);
      }
      setState(() {
        _selectedBook = picked;
        _selectedSubject = newSubj;
        if (_selectedTopic != null && _selectedTopic!.bookId != picked.id) {
          _selectedTopic = null;
        }
      });
    }
  }

  Future<void> _pickTopic() async {
    final db = AppScope.of(context);
    List<Topic> topics;
    if (_selectedBook != null) {
      topics = await db.topics.listByBook(_selectedBook!.id);
    } else if (_selectedSubject != null) {
      final books = await db.books.listBySubject(_selectedSubject!.id);
      topics = [];
      for (final b in books) {
        topics.addAll(await db.topics.listByBook(b.id));
      }
    } else {
      topics = await _loadAllTopics(db);
    }
    topics.sort((a, b) => compareNaturalNames(a.name, b.name));

    if (!mounted) return;
    if (topics.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.noTopicsFound)),
      );
      return;
    }

    final allBooks = await _loadAllBooks(db);
    final bookMap = {for (final b in allBooks) b.id: b};

    if (!mounted) return;
    final picked = await showDialog<Topic>(
      context: context,
      builder: (ctx) {
        var query = '';
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            final filtered = query.isEmpty
                ? topics
                : topics
                    .where((t) =>
                        t.name.toLowerCase().contains(query.toLowerCase()))
                    .toList();

            return AlertDialog(
              title: Text(S.selectTopicDialogTitle),
              content: SizedBox(
                width: 400,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 420),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        autofocus: false,
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.search, size: 20),
                          hintText: S.searchTopicHint,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onChanged: (val) {
                          setDialogState(() => query = val.trim());
                        },
                      ),
                      const SizedBox(height: 10),
                      if (filtered.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Text(
                            S.noTopicsFound,
                            style: TextStyle(
                              color: Theme.of(context).hintColor,
                            ),
                          ),
                        )
                      else
                        Flexible(
                          child: ListView.separated(
                            shrinkWrap: true,
                            itemCount: filtered.length,
                            separatorBuilder: (_, _) =>
                                const Divider(height: 1),
                            itemBuilder: (_, index) {
                              final t = filtered[index];
                              final isSelected = t.id == _selectedTopic?.id;
                              final parentBook = bookMap[t.bookId];
                              return ListTile(
                                dense: true,
                                selected: isSelected,
                                leading: Icon(
                                  isSelected
                                      ? Icons.radio_button_checked
                                      : Icons.description_outlined,
                                  size: 20,
                                ),
                                title: Text(
                                  t.name,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontWeight: isSelected
                                        ? FontWeight.bold
                                        : FontWeight.w600,
                                  ),
                                ),
                                subtitle: parentBook != null
                                    ? Text(parentBook.name)
                                    : null,
                                onTap: () => Navigator.pop(ctx, t),
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(S.cancel),
                ),
              ],
            );
          },
        );
      },
    );

    if (picked != null && mounted) {
      Book? newBook = _selectedBook;
      if (newBook == null || newBook.id != picked.bookId) {
        newBook = await db.books.getById(picked.bookId);
      }
      Subject? newSubj = _selectedSubject;
      if (newBook != null &&
          (newSubj == null || newSubj.id != newBook.subjectId)) {
        newSubj = await db.subjects.getById(newBook.subjectId);
      }
      setState(() {
        _selectedTopic = picked;
        _selectedBook = newBook;
        _selectedSubject = newSubj;
      });
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

    try {
      String targetDeckId;
      if (_selectedTopic != null) {
        final deck = await db.decks.getOrCreateDefaultForTopic(
          _selectedTopic!.id,
          defaultName: _selectedTopic!.name,
        );
        targetDeckId = deck.id;
        await QuickCardDestinationResolver.recordLastActiveTopic(
          db,
          _selectedTopic!.id,
        );
      } else if (_selectedBook != null) {
        var topics = await db.topics.listByBook(_selectedBook!.id);
        if (topics.isEmpty) {
          final t = await db.topics.create(
            bookId: _selectedBook!.id,
            name: S.generalDefaultName,
          );
          topics = [t];
        }
        final deck = await db.decks.getOrCreateDefaultForTopic(
          topics.first.id,
          defaultName: topics.first.name,
        );
        targetDeckId = deck.id;
        await QuickCardDestinationResolver.recordLastActiveTopic(
          db,
          topics.first.id,
        );
      } else if (_selectedSubject != null) {
        var books = await db.books.listBySubject(_selectedSubject!.id);
        if (books.isEmpty) {
          final b = await db.books.create(
            subjectId: _selectedSubject!.id,
            name: S.generalDefaultName,
          );
          books = [b];
        }
        var topics = await db.topics.listByBook(books.first.id);
        if (topics.isEmpty) {
          final t = await db.topics.create(
            bookId: books.first.id,
            name: S.generalDefaultName,
          );
          topics = [t];
        }
        final deck = await db.decks.getOrCreateDefaultForTopic(
          topics.first.id,
          defaultName: topics.first.name,
        );
        targetDeckId = deck.id;
        await QuickCardDestinationResolver.recordLastActiveTopic(
          db,
          topics.first.id,
        );
      } else {
        if (widget.deckId.isNotEmpty) {
          targetDeckId = widget.deckId;
        } else {
          final resolved =
              await QuickCardDestinationResolver.resolveForQuickAdd(db);
          targetDeckId = resolved.initial.deckId;
        }
      }

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
    final hasSelection = _selectedSubject != null ||
        _selectedBook != null ||
        _selectedTopic != null;

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
                    // Top row: Kitap tańlaw, Klass tańlaw, Tema tańlaw, hám qızıl ✕ túyme
                    Container(
                      key: const Key('card-destination-selector'),
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: _DestinationButton(
                              key: const Key('card-select-book'),
                              title:
                                  _selectedSubject?.name ?? S.selectBookLabel,
                              isSelected: _selectedSubject != null,
                              onTap: _pickSubject,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: _DestinationButton(
                              key: const Key('card-select-class'),
                              title: _selectedBook?.name ?? S.selectClassLabel,
                              isSelected: _selectedBook != null,
                              onTap: _pickBook,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: _DestinationButton(
                              key: const Key('card-select-topic'),
                              title: _selectedTopic?.name ?? S.selectTopicLabel,
                              isSelected: _selectedTopic != null,
                              onTap: _pickTopic,
                            ),
                          ),
                          const SizedBox(width: 6),
                          _ClearDestinationSquareButton(
                            key: const Key('card-clear-destination'),
                            onPressed:
                                hasSelection ? _clearAllSelections : null,
                          ),
                        ],
                      ),
                    ),
                    // 1. Gilt sóz (Target word) - Shártli
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
                    // 2. Anıqlama (Definition) - Shártli
                    TextFormField(
                      key: const Key('card-definition'),
                      controller: _definition,
                      decoration: InputDecoration(
                        labelText: S.fieldDefinition,
                        isDense: true,
                      ),
                      maxLines: 2,
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? S.definitionRequired
                          : null,
                    ),
                    const SizedBox(height: 8),
                    // 3. Assotsiaciya (Association) — ıqtıyarlı
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
                    // 4. Súwret — ıqtıyarlı
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

/// Rectangular selector button for Kitap, Klass, and Tema in the top destination row.
class _DestinationButton extends StatelessWidget {
  const _DestinationButton({
    super.key,
    required this.title,
    required this.isSelected,
    required this.onTap,
  });

  final String title;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final primaryColor = cs.primary;
    final isDark = theme.brightness == Brightness.dark;

    final bg = isSelected
        ? (isDark
            ? primaryColor.withValues(alpha: 0.22)
            : const Color(0xFFE9F1F7))
        : (isDark ? const Color(0xFF1E2832) : const Color(0xFFF3F6F9));

    final borderColor = isSelected
        ? primaryColor.withValues(alpha: 0.6)
        : (isDark ? Colors.white12 : const Color(0xFFD6DFE7));

    final textColor = isSelected
        ? (isDark ? const Color(0xFF90CAF9) : primaryColor)
        : (isDark ? Colors.white60 : const Color(0xFF5A6E82));

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: borderColor, width: 1.2),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: textColor,
                  ),
                ),
              ),
              Icon(
                Icons.arrow_drop_down,
                size: 16,
                color: textColor,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Red square button on the far right of the destination row that clears all 3 selections.
class _ClearDestinationSquareButton extends StatelessWidget {
  const _ClearDestinationSquareButton({
    super.key,
    required this.onPressed,
  });

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final enabled = onPressed != null;

    final bg = enabled
        ? (isDark ? const Color(0xFF3E1C1F) : const Color(0xFFFFECEE))
        : (isDark ? const Color(0xFF1F242A) : const Color(0xFFF3F5F7));

    final borderColor = enabled
        ? (isDark ? const Color(0xFF7A2E35) : const Color(0xFFF5B7B1))
        : (isDark ? Colors.white12 : const Color(0xFFE0E5EA));

    final iconColor = enabled
        ? (isDark ? const Color(0xFFEF5350) : const Color(0xFFD32F2F))
        : (isDark ? Colors.white24 : const Color(0xFFA5B2BE));

    return Tooltip(
      message: S.clearSelection,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: borderColor, width: 1.2),
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.close_rounded,
              size: 20,
              color: iconColor,
            ),
          ),
        ),
      ),
    );
  }
}
