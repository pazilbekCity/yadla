import 'package:flutter/material.dart';

import '../data/database/app_database_exception.dart';
import '../data/models/catalog_models.dart';
import '../data/services/backup_service.dart';
import '../data/services/image_storage_service.dart';
import '../data/services/preset_catalog_service.dart';
import 'app_scope.dart';
import 'backup_dialogs.dart';
import 'common.dart';
import 'deck_screen.dart';
import 'strings.dart';
import 'study_session_screen.dart';

enum _BackupMenuAction { exportBackup, importBackup }

/// Home screen: lists all [Subject]s and lets the user create, edit, delete,
/// download preset subjects from Google Sheets, or export/restore full offline
/// backups. Tapping a subject opens [BooksScreen].
class SubjectsScreen extends StatefulWidget {
  const SubjectsScreen({
    super.key,
    this.pickBackupFile,
    this.backupService = const BackupService(),
    this.presetCatalogService = const PresetCatalogService(),
  });

  final BackupFilePicker? pickBackupFile;
  final BackupService backupService;
  final PresetCatalogService presetCatalogService;

  @override
  State<SubjectsScreen> createState() => _SubjectsScreenState();
}

class _SubjectsScreenState extends State<SubjectsScreen> {
  Future<List<Subject>>? _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= _load();
  }

  Future<List<Subject>> _load() => AppScope.of(context).subjects.getAll();

  void _reload() => setState(() {
        _future = _load();
      });

  Future<void> _exportBackup() async {
    await runBackupExportFlow(
      context,
      backupService: widget.backupService,
    );
  }

  Future<void> _importBackup() async {
    final restored = await runBackupRestoreFlow(
      context,
      pickFile: widget.pickBackupFile,
      backupService: widget.backupService,
    );
    if (restored && mounted) _reload();
  }

  Future<void> _add() async {
    final db = AppScope.of(context);
    final result = await showDialog<_AddSubjectOutcome>(
      context: context,
      builder: (_) => _AddSubjectDialog(
        presetCatalogService: widget.presetCatalogService,
        onManualCreate: (name, desc) =>
            db.subjects.create(name: name, description: desc),
        onDownloadPreset: (preset) =>
            widget.presetCatalogService.downloadAndImportPreset(
          db: db,
          preset: preset,
        ),
      ),
    );
    if (result == null || !mounted) return;
    _reload();
    if (result.presetImportResult != null) {
      final r = result.presetImportResult!;
      showMessage(
        context,
        S.presetImportSuccess(
          r.subjectName,
          r.booksCount,
          r.topicsCount,
          r.cardsImported,
        ),
      );
    }
  }

  Future<void> _edit(Subject s) async {
    final repo = AppScope.of(context).subjects;
    final saved = await showNameDialog(
      context,
      title: S.editSubject,
      initialName: s.name,
      initialDescription: s.description,
      onSubmit: (name, desc) =>
          repo.update(s.copyWith(name: name, description: desc ?? '')),
    );
    if (saved && mounted) _reload();
  }

  Future<void> _delete(Subject s) async {
    if (!await confirmDelete(context, s.name) || !mounted) return;
    try {
      await AppScope.of(context).subjects.delete(s.id);
      if (mounted) _reload();
    } on AppDatabaseException catch (e) {
      if (mounted) showMessage(context, dbErrorMessage(e, name: s.name));
    }
  }

  Future<void> _studySubjectItem(Subject s) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => StudySessionScreen.forSubject(
          subjectId: s.id,
          subjectName: s.name,
        ),
      ),
    );
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    AppScope.languageOf(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text(S.appTitle),
        actions: [
          PopupMenuButton<_BackupMenuAction>(
            key: const Key('backup-menu-button'),
            tooltip: S.backupMenuTooltip,
            icon: const Icon(Icons.import_export_outlined),
            onSelected: (action) {
              switch (action) {
                case _BackupMenuAction.exportBackup:
                  _exportBackup();
                case _BackupMenuAction.importBackup:
                  _importBackup();
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                key: const Key('export-backup-menu-item'),
                value: _BackupMenuAction.exportBackup,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.download_outlined, size: 18),
                    const SizedBox(width: 8),
                    Flexible(child: Text(S.exportBackup)),
                  ],
                ),
              ),
              PopupMenuItem(
                key: const Key('import-backup-menu-item'),
                value: _BackupMenuAction.importBackup,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.restore_outlined, size: 18),
                    const SizedBox(width: 8),
                    Flexible(child: Text(S.importBackup)),
                  ],
                ),
              ),
            ],
          ),
          const LanguageSelectorButton(),
        ],
      ),
      body: CenteredBody(
        child: AsyncView<List<Subject>>(
          future: _future!,
          onRetry: _reload,
          builder: (context, items) => _CatalogList<Subject>(
            items: items,
            emptyText: S.subjectsEmpty,
            titleOf: (s) => s.name,
            subtitleOf: (s) => s.description,
            onTap: (s) async {
              await Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => BooksScreen(subject: s),
                ),
              );
              if (mounted) _reload();
            },
            onStudy: _studySubjectItem,
            studyTooltip: S.studySubject,
            studyKeyOf: (s) => Key('study-subject-${s.id}'),
            onEdit: _edit,
            onDelete: _delete,
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('fab-add-subject'),
        onPressed: _add,
        icon: const Icon(Icons.add),
        label: Text(S.addSubject),
      ),
    );
  }
}

/// Subject screen: lists and manages [Book]s belonging to [subject].
class BooksScreen extends StatefulWidget {
  const BooksScreen({
    super.key,
    required this.subject,
    this.pickImageFile,
    this.imageStorage = const ImageStorageService(),
  });

  final Subject subject;
  final ImageFilePicker? pickImageFile;
  final ImageStorageService imageStorage;

  @override
  State<BooksScreen> createState() => _BooksScreenState();
}

class _BooksScreenState extends State<BooksScreen> {
  Future<List<Book>>? _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= _load();
  }

  Future<List<Book>> _load() =>
      AppScope.of(context).books.listBySubject(widget.subject.id);

  void _reload() => setState(() {
        _future = _load();
      });

  Future<void> _add() async {
    final repo = AppScope.of(context).books;
    final saved = await _showBookDialog(
      context,
      title: S.addBook,
      pickImageFile: widget.pickImageFile,
      imageStorage: widget.imageStorage,
      onSubmit: (name, desc, year, imagePath) => repo.create(
        subjectId: widget.subject.id,
        name: name,
        description: desc,
        publicationYear: year,
        imagePath: imagePath,
      ),
    );
    if (saved && mounted) _reload();
  }

  Future<void> _edit(Book b) async {
    final repo = AppScope.of(context).books;
    final saved = await _showBookDialog(
      context,
      title: S.editBook,
      initialName: b.name,
      initialDescription: b.description,
      initialYear: b.publicationYear,
      initialImagePath: b.imagePath,
      pickImageFile: widget.pickImageFile,
      imageStorage: widget.imageStorage,
      onSubmit: (name, desc, year, imagePath) => repo.update(
        b.copyWith(
          name: name,
          description: desc ?? '',
          publicationYear: year,
          clearPublicationYear: year == null,
          imagePath: imagePath,
          clearImagePath: imagePath == null || imagePath.isEmpty,
        ),
      ),
    );
    if (saved && mounted) _reload();
  }

  Future<void> _delete(Book b) async {
    if (!await confirmDelete(context, b.name) || !mounted) return;
    try {
      await AppScope.of(context).books.delete(b.id);
      if (mounted) _reload();
    } on AppDatabaseException catch (e) {
      if (mounted) showMessage(context, dbErrorMessage(e, name: b.name));
    }
  }

  Future<void> _studySubject() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => StudySessionScreen.forSubject(
          subjectId: widget.subject.id,
          subjectName: widget.subject.name,
        ),
      ),
    );
    if (mounted) _reload();
  }

  Future<void> _studyBookItem(Book b) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => StudySessionScreen.forBook(
          bookId: b.id,
          bookName: b.name,
        ),
      ),
    );
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    AppScope.languageOf(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.subject.name),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton.tonalIcon(
              key: const Key('study-subject-button'),
              onPressed: _studySubject,
              icon: const Icon(Icons.play_arrow),
              label: Text(S.studySubject),
            ),
          ),
        ],
      ),
      body: CenteredBody(
        child: AsyncView<List<Book>>(
          future: _future!,
          onRetry: _reload,
          builder: (context, items) => _CatalogList<Book>(
            items: items,
            emptyText: S.booksEmpty,
            titleOf: (b) => b.name,
            subtitleOf: (b) => b.description,
            leadingBuilder: (context, b) => _BookCoverThumbnail(
              key: Key('book-cover-${b.id}'),
              imagePath: b.imagePath,
            ),
            badgeBuilder: (context, b) {
              final year = b.publicationYear;
              if (year == null) return null;
              final colorScheme = Theme.of(context).colorScheme;
              return Container(
                key: Key('book-year-badge-${b.id}'),
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.calendar_today_outlined,
                      size: 12,
                      color: colorScheme.onPrimaryContainer,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      S.bookYearBadge(year),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: colorScheme.onPrimaryContainer,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ],
                ),
              );
            },
            onTap: (b) async {
              await Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => TopicsScreen(book: b),
                ),
              );
              if (mounted) _reload();
            },
            onStudy: _studyBookItem,
            studyTooltip: S.studyBook,
            studyKeyOf: (b) => Key('study-book-${b.id}'),
            onEdit: _edit,
            onDelete: _delete,
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('fab-add-book'),
        onPressed: _add,
        icon: const Icon(Icons.add),
        label: Text(S.addBook),
      ),
    );
  }
}

/// Book screen: lists and manages [Topic]s belonging to [book].
/// Tapping a topic opens its flashcards directly ([DeckScreen.forTopic]).
class TopicsScreen extends StatefulWidget {
  const TopicsScreen({super.key, required this.book});

  final Book book;

  @override
  State<TopicsScreen> createState() => _TopicsScreenState();
}

class _TopicsScreenState extends State<TopicsScreen> {
  Future<List<Topic>>? _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= _load();
  }

  Future<List<Topic>> _load() =>
      AppScope.of(context).topics.listByBook(widget.book.id);

  void _reload() => setState(() {
        _future = _load();
      });

  Future<void> _add() async {
    final repo = AppScope.of(context).topics;
    final saved = await showNameDialog(
      context,
      title: S.addTopic,
      onSubmit: (name, desc) => repo.create(
        bookId: widget.book.id,
        name: name,
        description: desc,
      ),
    );
    if (saved && mounted) _reload();
  }

  Future<void> _edit(Topic t) async {
    final repo = AppScope.of(context).topics;
    final saved = await showNameDialog(
      context,
      title: S.editTopic,
      initialName: t.name,
      initialDescription: t.description,
      onSubmit: (name, desc) =>
          repo.update(t.copyWith(name: name, description: desc ?? '')),
    );
    if (saved && mounted) _reload();
  }

  Future<void> _delete(Topic t) async {
    if (!await confirmDelete(context, t.name) || !mounted) return;
    final scope = AppScope.of(context);
    try {
      final cards = await scope.flashcards.listByTopic(t.id);
      if (cards.isEmpty) {
        // Clean up any auto-created empty default deck when the topic has no cards.
        await scope.topics.delete(t.id, cascade: true);
      } else {
        await scope.topics.delete(t.id);
      }
      if (mounted) _reload();
    } on AppDatabaseException catch (e) {
      if (mounted) showMessage(context, dbErrorMessage(e, name: t.name));
    }
  }

  Future<void> _studyBook() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => StudySessionScreen.forBook(
          bookId: widget.book.id,
          bookName: widget.book.name,
        ),
      ),
    );
    if (mounted) _reload();
  }

  Future<void> _studyTopicItem(Topic t) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => StudySessionScreen.forTopic(
          topicId: t.id,
          topicName: t.name,
        ),
      ),
    );
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    AppScope.languageOf(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.book.name),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton.tonalIcon(
              key: const Key('study-book-button'),
              onPressed: _studyBook,
              icon: const Icon(Icons.play_arrow),
              label: Text(S.studyBook),
            ),
          ),
        ],
      ),
      body: CenteredBody(
        child: AsyncView<List<Topic>>(
          future: _future!,
          onRetry: _reload,
          builder: (context, items) => _CatalogList<Topic>(
            items: items,
            emptyText: S.topicsEmpty,
            titleOf: (t) => t.name,
            subtitleOf: (t) => t.description,
            onTap: (t) async {
              await Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => DeckScreen.forTopic(topic: t),
                ),
              );
              if (mounted) _reload();
            },
            onStudy: _studyTopicItem,
            studyTooltip: S.studyTopic,
            studyKeyOf: (t) => Key('study-topic-${t.id}'),
            onEdit: _edit,
            onDelete: _delete,
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('fab-add-topic'),
        onPressed: _add,
        icon: const Icon(Icons.add),
        label: Text(S.addTopic),
      ),
    );
  }
}

/// Topic screen: lists and manages [Deck]s belonging to [topic].
class DecksScreen extends StatefulWidget {
  const DecksScreen({super.key, required this.topic});

  final Topic topic;

  @override
  State<DecksScreen> createState() => _DecksScreenState();
}

class _DecksScreenState extends State<DecksScreen> {
  Future<List<Deck>>? _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= _load();
  }

  Future<List<Deck>> _load() =>
      AppScope.of(context).decks.listByTopic(widget.topic.id);

  void _reload() => setState(() {
        _future = _load();
      });

  Future<void> _add() async {
    final repo = AppScope.of(context).decks;
    final saved = await showNameDialog(
      context,
      title: S.addDeck,
      onSubmit: (name, desc) => repo.create(
        topicId: widget.topic.id,
        name: name,
        description: desc,
      ),
    );
    if (saved && mounted) _reload();
  }

  Future<void> _edit(Deck d) async {
    final repo = AppScope.of(context).decks;
    final saved = await showNameDialog(
      context,
      title: S.editDeck,
      initialName: d.name,
      initialDescription: d.description,
      onSubmit: (name, desc) =>
          repo.update(d.copyWith(name: name, description: desc ?? '')),
    );
    if (saved && mounted) _reload();
  }

  Future<void> _delete(Deck d) async {
    if (!await confirmDelete(context, d.name) || !mounted) return;
    try {
      await AppScope.of(context).decks.delete(d.id);
      if (mounted) _reload();
    } on AppDatabaseException catch (e) {
      if (mounted) showMessage(context, dbErrorMessage(e, name: d.name));
    }
  }

  @override
  Widget build(BuildContext context) {
    AppScope.languageOf(context);
    return Scaffold(
      appBar: AppBar(title: Text(widget.topic.name)),
      body: CenteredBody(
        child: AsyncView<List<Deck>>(
          future: _future!,
          onRetry: _reload,
          builder: (context, items) => _CatalogList<Deck>(
            items: items,
            emptyText: S.decksEmpty,
            titleOf: (d) => d.name,
            subtitleOf: (d) => d.description,
            onTap: (d) async {
              await Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => DeckScreen(deck: d),
                ),
              );
              if (mounted) _reload();
            },
            onEdit: _edit,
            onDelete: _delete,
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('fab-add-deck'),
        onPressed: _add,
        icon: const Icon(Icons.add),
        label: Text(S.addDeck),
      ),
    );
  }
}

class _CatalogList<T> extends StatelessWidget {
  const _CatalogList({
    required this.items,
    required this.emptyText,
    required this.titleOf,
    required this.subtitleOf,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
    this.leadingBuilder,
    this.badgeBuilder,
    this.onStudy,
    this.studyTooltip,
    this.studyKeyOf,
  });

  final List<T> items;
  final String emptyText;
  final String Function(T) titleOf;
  final String? Function(T) subtitleOf;
  final ValueChanged<T> onTap;
  final ValueChanged<T> onEdit;
  final ValueChanged<T> onDelete;
  final Widget Function(BuildContext context, T item)? leadingBuilder;
  final Widget? Function(BuildContext context, T item)? badgeBuilder;
  final ValueChanged<T>? onStudy;
  final String? studyTooltip;
  final Key Function(T item)? studyKeyOf;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(emptyText, textAlign: TextAlign.center),
        ),
      );
    }
    final colorScheme = Theme.of(context).colorScheme;
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final item = items[index];
        final title = titleOf(item);
        final sub = subtitleOf(item);
        final badge = badgeBuilder?.call(context, item);
        final hasSub = sub != null && sub.isNotEmpty;
        return Card(
          margin: EdgeInsets.zero,
          elevation: 1,
          color: colorScheme.secondaryContainer.withValues(alpha: 0.45),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: colorScheme.outlineVariant),
          ),
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            leading: leadingBuilder?.call(context, item),
            title: Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            subtitle: (badge == null && !hasSub)
                ? null
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (badge != null) ...[
                        const SizedBox(height: 4),
                        badge,
                      ],
                      if (hasSub) ...[
                        const SizedBox(height: 4),
                        Text(sub),
                      ],
                    ],
                  ),
            onTap: () => onTap(item),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (onStudy != null)
                  IconButton.filledTonal(
                    key: studyKeyOf?.call(item),
                    tooltip: studyTooltip ?? S.study,
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.play_arrow),
                    onPressed: () => onStudy!(item),
                  ),
                IconButton(
                  tooltip: S.edit,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => onEdit(item),
                ),
                IconButton(
                  tooltip: S.delete,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => onDelete(item),
                ),
                Icon(
                  Icons.chevron_right,
                  color: colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _BookCoverThumbnail extends StatelessWidget {
  const _BookCoverThumbnail({
    super.key,
    required this.imagePath,
  });

  final String? imagePath;

  static const double _width = 44;
  static const double _height = 56;

  Widget _placeholder(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      key: const Key('book-cover-placeholder'),
      width: _width,
      height: _height,
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Icon(
        Icons.menu_book_rounded,
        color: colorScheme.onPrimaryContainer,
        size: 24,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final file = ImageStorageService.resolveLocalImageFile(imagePath);
    if (file == null) {
      return _placeholder(context);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.file(
        file,
        key: const Key('book-cover-image'),
        width: _width,
        height: _height,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _placeholder(context),
      ),
    );
  }
}

Future<bool> _showBookDialog(
  BuildContext context, {
  required String title,
  String initialName = '',
  String? initialDescription,
  int? initialYear,
  String? initialImagePath,
  ImageFilePicker? pickImageFile,
  ImageStorageService imageStorage = const ImageStorageService(),
  required Future<void> Function(
    String name,
    String? description,
    int? publicationYear,
    String? imagePath,
  ) onSubmit,
}) async {
  final saved = await showDialog<bool>(
    context: context,
    builder: (_) => _BookDialog(
      title: title,
      initialName: initialName,
      initialDescription: initialDescription,
      initialYear: initialYear,
      initialImagePath: initialImagePath,
      pickImageFile: pickImageFile,
      imageStorage: imageStorage,
      onSubmit: onSubmit,
    ),
  );
  return saved ?? false;
}

class _BookDialog extends StatefulWidget {
  const _BookDialog({
    required this.title,
    required this.initialName,
    required this.initialDescription,
    required this.initialYear,
    required this.initialImagePath,
    required this.pickImageFile,
    required this.imageStorage,
    required this.onSubmit,
  });

  final String title;
  final String initialName;
  final String? initialDescription;
  final int? initialYear;
  final String? initialImagePath;
  final ImageFilePicker? pickImageFile;
  final ImageStorageService imageStorage;
  final Future<void> Function(
    String name,
    String? description,
    int? publicationYear,
    String? imagePath,
  ) onSubmit;

  @override
  State<_BookDialog> createState() => _BookDialogState();
}

class _BookDialogState extends State<_BookDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.initialName);
  late final _year = TextEditingController(
    text: widget.initialYear?.toString() ?? '',
  );
  late final _desc = TextEditingController(text: widget.initialDescription);
  late String? _imagePath = widget.initialImagePath;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _year.dispose();
    _desc.dispose();
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
        _imagePath = persistentPath;
      });
    } on ImageStorageException catch (e) {
      if (mounted) {
        setState(() => _error = _imageErrorMessage(e));
      }
    }
  }

  void _clearImage() {
    setState(() {
      _imagePath = null;
      _error = null;
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final yearText = _year.text.trim();
    final parsedYear = yearText.isEmpty ? null : int.parse(yearText);
    try {
      await widget.onSubmit(
        _name.text.trim(),
        _desc.text.trim(),
        parsedYear,
        _imagePath,
      );
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

  @override
  Widget build(BuildContext context) {
    final hasImage = _imagePath != null && _imagePath!.trim().isNotEmpty;
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                key: const Key('field-name'),
                controller: _name,
                autofocus: true,
                decoration: InputDecoration(labelText: S.name),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? S.nameRequired : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                key: const Key('field-book-year'),
                controller: _year,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: S.bookYear),
                validator: (v) {
                  final trimmed = v?.trim() ?? '';
                  if (trimmed.isEmpty) return null;
                  final parsed = int.tryParse(trimmed);
                  if (parsed == null || parsed < 1000 || parsed > 9999) {
                    return S.bookYearInvalid;
                  }
                  return null;
                },
              ),
              const SizedBox(height: 8),
              TextFormField(
                key: const Key('field-description'),
                controller: _desc,
                decoration: InputDecoration(labelText: S.description),
              ),
              const SizedBox(height: 14),
              Text(
                S.bookCoverImage,
                style: Theme.of(context).textTheme.labelMedium,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _BookCoverThumbnail(imagePath: _imagePath),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const Key('pick-book-image-button'),
                      onPressed: _busy ? null : _pickImage,
                      icon: const Icon(Icons.photo_library_outlined),
                      label: Text(hasImage ? S.changeImage : S.pickImage),
                    ),
                  ),
                  if (hasImage)
                    IconButton(
                      key: const Key('clear-book-image-button'),
                      tooltip: S.removeImage,
                      onPressed: _busy ? null : _clearImage,
                      icon: const Icon(Icons.clear),
                    ),
                ],
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: Text(S.cancel),
        ),
        FilledButton(
          key: const Key('dialog-save'),
          onPressed: _busy ? null : _submit,
          child: Text(S.save),
        ),
      ],
    );
  }
}

class _AddSubjectOutcome {
  const _AddSubjectOutcome.manual() : presetImportResult = null;
  const _AddSubjectOutcome.preset(this.presetImportResult);

  final PresetImportResult? presetImportResult;
}

class _AddSubjectDialog extends StatefulWidget {
  const _AddSubjectDialog({
    required this.presetCatalogService,
    required this.onManualCreate,
    required this.onDownloadPreset,
  });

  final PresetCatalogService presetCatalogService;
  final Future<void> Function(String name, String? description) onManualCreate;
  final Future<PresetImportResult> Function(PresetSubjectDefinition preset)
      onDownloadPreset;

  @override
  State<_AddSubjectDialog> createState() => _AddSubjectDialogState();
}

class _AddSubjectDialogState extends State<_AddSubjectDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _desc = TextEditingController();
  bool _busy = false;
  bool _downloadingPreset = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _downloadPreset(PresetSubjectDefinition preset) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _downloadingPreset = true;
      _error = null;
    });
    try {
      final imported = await widget.onDownloadPreset(preset);
      if (mounted) {
        Navigator.pop(context, _AddSubjectOutcome.preset(imported));
      }
    } on AppDatabaseException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _downloadingPreset = false;
          _error = dbErrorMessage(e);
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _downloadingPreset = false;
          _error = S.presetImportError;
        });
      }
    }
  }

  Future<void> _submitManual() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onManualCreate(_name.text.trim(), _desc.text.trim());
      if (mounted) {
        Navigator.pop(context, const _AddSubjectOutcome.manual());
      }
    } on AppDatabaseException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = dbErrorMessage(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(S.addSubject),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Option 1: Download from preset database (Google Sheets)
            Text(
              S.addSubjectFromDatabase,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colorScheme.primary,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              S.addSubjectFromDatabaseSub,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            for (final preset in PresetCatalogService.availablePresets)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                color: colorScheme.primaryContainer.withValues(alpha: 0.45),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: colorScheme.outlineVariant),
                ),
                child: ListTile(
                  key: Key('preset-subject-${preset.id}'),
                  leading: Icon(
                    Icons.cloud_download_outlined,
                    color: colorScheme.primary,
                  ),
                  title: Text(
                    preset.name,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    preset.description,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  trailing: _downloadingPreset
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.download_rounded),
                  onTap: _busy ? null : () => _downloadPreset(preset),
                ),
              ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Divider(),
            ),
            // Option 2: Create from 0 manually
            Text(
              S.addSubjectFromScratch,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colorScheme.primary,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              S.addSubjectFromScratchSub,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    key: const Key('field-name'),
                    controller: _name,
                    enabled: !_busy,
                    decoration: InputDecoration(labelText: S.name),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? S.nameRequired : null,
                  ),
                  TextFormField(
                    key: const Key('field-description'),
                    controller: _desc,
                    enabled: !_busy,
                    decoration: InputDecoration(labelText: S.description),
                  ),
                ],
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _error!,
                  key: const Key('add-subject-error'),
                  style: TextStyle(color: colorScheme.error),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: Text(S.cancel),
        ),
        FilledButton(
          key: const Key('dialog-save'),
          onPressed: _busy ? null : _submitManual,
          child: Text(S.save),
        ),
      ],
    );
  }
}
