import 'package:flutter/material.dart';

import '../data/database/app_database_exception.dart';
import '../data/models/catalog_models.dart';
import '../data/repositories/flashcard_repository.dart';
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

class _CatalogPayload<T> {
  const _CatalogPayload(this.items, this.progress);

  final List<T> items;
  final Map<String, MasteryProgress> progress;
}

class _HomeSubjectsPayload {
  const _HomeSubjectsPayload({
    required this.items,
    required this.progress,
    required this.streakDays,
    required this.dueTodayCount,
    this.promoBanner,
  });

  final List<Subject> items;
  final Map<String, MasteryProgress> progress;
  final int streakDays;
  final int dueTodayCount;
  final PromoBannerData? promoBanner;
}

class _SubjectsScreenState extends State<SubjectsScreen> {
  Future<_HomeSubjectsPayload>? _future;
  PromoBannerData? _livePromoBanner;
  bool _promoDismissed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_future == null) {
      _future = _load();
      _refreshPromoBannerInBackground();
    }
  }

  Future<_HomeSubjectsPayload> _load() async {
    final db = AppScope.of(context);
    final items = await db.subjects.getAll();
    final progress = await db.flashcards.progressBySubject();
    final streakDays = await db.reviews.calculateStudyStreakDays();
    final dueTodayCount = await db.flashcards.countDueCards();
    final cachedPromo = await PresetCatalogService.loadCachedPromoBanner(db);
    return _HomeSubjectsPayload(
      items: items,
      progress: progress,
      streakDays: streakDays,
      dueTodayCount: dueTodayCount,
      promoBanner: _livePromoBanner ?? cachedPromo,
    );
  }

  Future<void> _refreshPromoBannerInBackground() async {
    final db = AppScope.of(context);
    final fetched =
        await widget.presetCatalogService.fetchAndCachePromoBanner(db);
    if (!mounted) return;
    if (fetched?.title != _livePromoBanner?.title ||
        fetched?.subtitle != _livePromoBanner?.subtitle ||
        fetched?.contactOrLink != _livePromoBanner?.contactOrLink) {
      setState(() {
        _livePromoBanner = fetched;
      });
    }
  }

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
    final existingSubjects = await db.subjects.getAll();
    if (!mounted) return;
    final existingNames = {
      for (final s in existingSubjects) s.name.trim().toLowerCase(),
    };
    final remainingPresets = PresetCatalogService.availablePresets
        .where((p) => !existingNames.contains(p.name.trim().toLowerCase()))
        .toList();

    final result = await showDialog<_AddSubjectOutcome>(
      context: context,
      builder: (_) => _AddSubjectDialog(
        availablePresets: remainingPresets,
        existingSubjectNamesLower: existingNames,
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
    final subjectsRepo = AppScope.of(context).subjects;
    try {
      await subjectsRepo.delete(s.id);
      if (mounted) _reload();
    } on AppDatabaseException catch (e) {
      if (!mounted) return;
      if (e.kind == DbErrorKind.hasDependents) {
        if (!await confirmCascadeDelete(context, s.name) || !mounted) return;
        try {
          await subjectsRepo.delete(s.id, cascade: true);
          if (mounted) _reload();
        } on AppDatabaseException catch (err) {
          if (mounted) showMessage(context, dbErrorMessage(err, name: s.name));
        }
      } else {
        showMessage(context, dbErrorMessage(e, name: s.name));
      }
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

  Future<void> _studyDueToday(int dueCount) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => StudySessionScreen.forAllDue(
          title: S.dueTodayBadge(dueCount),
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
          const ThemeModeButton(),
          const LanguageSelectorButton(),
        ],
      ),
      body: CenteredBody(
        child: AsyncView<_HomeSubjectsPayload>(
          future: _future!,
          onRetry: _reload,
          builder: (context, payload) {
            final activeBanner = _promoDismissed
                ? null
                : (_livePromoBanner ?? payload.promoBanner);
            final showStatusHeader = payload.items.isNotEmpty ||
                payload.streakDays > 0 ||
                payload.dueTodayCount > 0;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (showStatusHeader)
                  _DailyRetentionBar(
                    streakDays: payload.streakDays,
                    dueTodayCount: payload.dueTodayCount,
                    onTapDueToday: payload.dueTodayCount > 0
                        ? () => _studyDueToday(payload.dueTodayCount)
                        : null,
                  ),
                if (activeBanner != null)
                  _PromoBannerCard(
                    banner: activeBanner,
                    onDismiss: () => setState(() => _promoDismissed = true),
                  ),
                Expanded(
                  child: _CatalogList<Subject>(
                    items: payload.items,
                    emptyText: S.subjectsEmpty,
                    titleOf: (s) => s.name,
                    subtitleOf: (s) => s.description,
                    progressOf: (s) => payload.progress[s.id]?.ratio ?? 0.0,
                    progressKeyOf: (s) => Key('subject-progress-${s.id}'),
                    onTap: (s) async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => BooksScreen(
                            subject: s,
                            presetCatalogService: widget.presetCatalogService,
                          ),
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
              ],
            );
          },
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
    this.presetCatalogService = const PresetCatalogService(),
  });

  final Subject subject;
  final ImageFilePicker? pickImageFile;
  final ImageStorageService imageStorage;
  final PresetCatalogService presetCatalogService;

  @override
  State<BooksScreen> createState() => _BooksScreenState();
}

class _BooksScreenState extends State<BooksScreen> {
  Future<_CatalogPayload<Book>>? _future;
  PresetSubjectDefinition? _customLinkedPreset;
  bool _syncingPreset = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= _load();
  }

  Future<_CatalogPayload<Book>> _load() async {
    final db = AppScope.of(context);
    final items = await db.books.listBySubject(widget.subject.id);
    final progress = await db.flashcards.progressByBook(widget.subject.id);
    final customPresets = await PresetCatalogService.loadLinkedPresets(db);
    final resolvedPreset = PresetCatalogService.findPresetByName(
      widget.subject.name,
      customPresets: customPresets,
    );
    if (mounted && _customLinkedPreset?.spreadsheetId != resolvedPreset?.spreadsheetId) {
      setState(() => _customLinkedPreset = resolvedPreset);
    } else {
      _customLinkedPreset = resolvedPreset;
    }
    return _CatalogPayload(items, progress);
  }

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
    final booksRepo = AppScope.of(context).books;
    try {
      await booksRepo.delete(b.id);
      if (mounted) _reload();
    } on AppDatabaseException catch (e) {
      if (!mounted) return;
      if (e.kind == DbErrorKind.hasDependents) {
        if (!await confirmCascadeDelete(context, b.name) || !mounted) return;
        try {
          await booksRepo.delete(b.id, cascade: true);
          if (mounted) _reload();
        } on AppDatabaseException catch (err) {
          if (mounted) showMessage(context, dbErrorMessage(err, name: b.name));
        }
      } else {
        showMessage(context, dbErrorMessage(e, name: b.name));
      }
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

  Future<void> _syncPreset(PresetSubjectDefinition preset) async {
    if (_syncingPreset) return;
    setState(() => _syncingPreset = true);
    try {
      final db = AppScope.of(context);
      final r = await widget.presetCatalogService.downloadAndImportPreset(
        db: db,
        preset: preset,
      );
      if (!mounted) return;
      setState(() => _syncingPreset = false);
      _reload();
      showMessage(
        context,
        S.presetImportSuccess(
          r.subjectName,
          r.booksCount,
          r.topicsCount,
          r.cardsImported,
        ),
      );
    } on AppDatabaseException catch (e) {
      if (!mounted) return;
      setState(() => _syncingPreset = false);
      showMessage(context, dbErrorMessage(e));
    } catch (_) {
      if (!mounted) return;
      setState(() => _syncingPreset = false);
      showMessage(context, S.presetImportError);
    }
  }

  @override
  Widget build(BuildContext context) {
    AppScope.languageOf(context);
    final linkedPreset = _customLinkedPreset ??
        PresetCatalogService.findPresetByName(widget.subject.name);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.subject.name),
        actions: [
          if (linkedPreset != null)
            IconButton(
              key: const Key('sync-preset-subject-button'),
              tooltip: S.syncFromDatabase,
              onPressed:
                  _syncingPreset ? null : () => _syncPreset(linkedPreset),
              icon: _syncingPreset
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sync),
            ),
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
        child: AsyncView<_CatalogPayload<Book>>(
          future: _future!,
          onRetry: _reload,
          builder: (context, payload) => _CatalogList<Book>(
            items: payload.items,
            emptyText: S.booksEmpty,
            titleOf: (b) => b.name,
            subtitleOf: (b) => b.description,
            progressOf: (b) => payload.progress[b.id]?.ratio ?? 0.0,
            progressKeyOf: (b) => Key('book-progress-${b.id}'),
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
  Future<_CatalogPayload<Topic>>? _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= _load();
  }

  Future<_CatalogPayload<Topic>> _load() async {
    final db = AppScope.of(context);
    final items = await db.topics.listByBook(widget.book.id);
    final progress = await db.flashcards.progressByTopic(widget.book.id);
    return _CatalogPayload(items, progress);
  }

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
      if (!mounted) return;
      if (e.kind == DbErrorKind.hasDependents) {
        if (!await confirmCascadeDelete(context, t.name) || !mounted) return;
        try {
          await scope.topics.delete(t.id, cascade: true);
          if (mounted) _reload();
        } on AppDatabaseException catch (err) {
          if (mounted) showMessage(context, dbErrorMessage(err, name: t.name));
        }
      } else {
        showMessage(context, dbErrorMessage(e, name: t.name));
      }
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

  Future<void> _searchBookCards() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => BookFlashcardSearchScreen(book: widget.book),
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
          IconButton(
            key: const Key('search-book-cards-button'),
            tooltip: S.searchCards,
            icon: const Icon(Icons.search),
            onPressed: _searchBookCards,
          ),
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
        child: AsyncView<_CatalogPayload<Topic>>(
          future: _future!,
          onRetry: _reload,
          builder: (context, payload) => _CatalogList<Topic>(
            items: payload.items,
            emptyText: S.topicsEmpty,
            titleOf: (t) => t.name,
            subtitleOf: (t) => t.description,
            progressOf: (t) => payload.progress[t.id]?.ratio ?? 0.0,
            progressKeyOf: (t) => Key('topic-progress-${t.id}'),
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
    this.progressOf,
    this.progressKeyOf,
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
  final double Function(T item)? progressOf;
  final Key Function(T item)? progressKeyOf;

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
    final isDark = colorScheme.brightness == Brightness.dark;
    final fillGreen = isDark
        ? const Color(0xFF2D6A4F).withValues(alpha: 0.34)
        : const Color(0xFF40916C).withValues(alpha: 0.16);
    final barGreen =
        isDark ? const Color(0xFF52B788) : const Color(0xFF2D6A4F);

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
        final progress = (progressOf?.call(item) ?? 0.0).clamp(0.0, 1.0);
        return Card(
          margin: EdgeInsets.zero,
          elevation: 0,
          color: colorScheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: colorScheme.outlineVariant),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              if (progress > 0)
                Positioned.fill(
                  child: FractionallySizedBox(
                    key: progressKeyOf?.call(item),
                    alignment: Alignment.centerLeft,
                    widthFactor: progress,
                    child: DecoratedBox(
                      decoration: BoxDecoration(color: fillGreen),
                    ),
                  ),
                ),
              ListTile(
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
              if (progress > 0)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: 3.5,
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: progress,
                    child: DecoratedBox(
                      decoration: BoxDecoration(color: barGreen),
                    ),
                  ),
                ),
            ],
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
    required this.availablePresets,
    required this.existingSubjectNamesLower,
    required this.presetCatalogService,
    required this.onManualCreate,
    required this.onDownloadPreset,
  });

  final List<PresetSubjectDefinition> availablePresets;
  final Set<String> existingSubjectNamesLower;
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
  final _sheetSubjectName = TextEditingController();
  final _sheetUrl = TextEditingController();
  late List<PresetSubjectDefinition> _presets = List.of(widget.availablePresets);
  bool _showUrlImport = false;
  bool _busy = false;
  bool _downloadingPreset = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _discoverRemotePresets();
  }

  Future<void> _discoverRemotePresets() async {
    final discovered =
        await widget.presetCatalogService.fetchRemoteCatalogPresets();
    if (!mounted) return;
    final filtered = discovered
        .where(
          (p) => !widget.existingSubjectNamesLower.contains(
            p.name.trim().toLowerCase(),
          ),
        )
        .toList();
    if (filtered.length != _presets.length) {
      setState(() => _presets = filtered);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    _sheetSubjectName.dispose();
    _sheetUrl.dispose();
    super.dispose();
  }

  Future<void> _downloadFromCustomUrl() async {
    if (_busy) return;
    final subjName = _sheetSubjectName.text.trim();
    final rawUrl = _sheetUrl.text.trim();
    if (subjName.isEmpty) {
      setState(() => _error = S.nameRequired);
      return;
    }
    final sheetId = PresetCatalogService.extractSpreadsheetId(rawUrl);
    if (sheetId == null) {
      setState(() => _error = S.googleSheetsUrlInvalid);
      return;
    }
    final customPreset = PresetSubjectDefinition(
      id: subjName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_'),
      name: subjName,
      description: '',
      spreadsheetId: sheetId,
      topicsGid: '0',
      answersGid: PresetCatalogService.extractGidFromUrl(rawUrl),
    );
    await _downloadPreset(customPreset);
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
    final hasPresets = _presets.isNotEmpty;
    return AlertDialog(
      title: Text(S.addSubject),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (hasPresets) ...[
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
              for (final preset in _presets)
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
                    subtitle: preset.description.isEmpty
                        ? null
                        : Text(
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
            ],
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const Key('toggle-sheet-url-import'),
                onPressed: _busy
                    ? null
                    : () => setState(() => _showUrlImport = !_showUrlImport),
                icon: Icon(
                  _showUrlImport ? Icons.expand_less : Icons.link,
                  size: 18,
                ),
                label: Text(S.addByGoogleSheetsUrl),
              ),
            ),
            if (_showUrlImport) ...[
              const SizedBox(height: 6),
              TextField(
                key: const Key('field-sheet-subject-name'),
                controller: _sheetSubjectName,
                enabled: !_busy,
                decoration: InputDecoration(labelText: S.name),
              ),
              const SizedBox(height: 8),
              TextField(
                key: const Key('field-sheet-url'),
                controller: _sheetUrl,
                enabled: !_busy,
                decoration: InputDecoration(
                  labelText: S.googleSheetsUrlLabel,
                  hintText: 'https://docs.google.com/spreadsheets/d/...',
                ),
              ),
              const SizedBox(height: 8),
              FilledButton.tonalIcon(
                key: const Key('download-sheet-url-button'),
                onPressed: _busy ? null : _downloadFromCustomUrl,
                icon: const Icon(Icons.cloud_download_outlined, size: 18),
                label: Text(S.downloadFromSheetUrl),
              ),
            ],
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Divider(),
            ),
            // Option 2: Create a new subject manually
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
                    autofocus: !hasPresets,
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

/// Compact, calm daily retention bar displaying the user's consecutive study
/// streak (`🔥 <N> kún úzliksiz`) and the count of flashcards due today
/// (`📅 Búgin qaytalaw: <N>`).
class _DailyRetentionBar extends StatelessWidget {
  const _DailyRetentionBar({
    required this.streakDays,
    required this.dueTodayCount,
    this.onTapDueToday,
  });

  final int streakDays;
  final int dueTodayCount;
  final VoidCallback? onTapDueToday;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = colorScheme.brightness == Brightness.dark;
    final streakColor =
        isDark ? const Color(0xFFE09F67) : const Color(0xFFB35E24);
    final streakBg = isDark
        ? const Color(0xFF36281E)
        : const Color(0xFFF9EFE6);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          // 1. 🔥 Daily Streak Pill
          Expanded(
            child: Container(
              key: const Key('home-streak-badge'),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: streakBg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: streakColor.withValues(alpha: 0.35),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.local_fire_department_rounded,
                    size: 18,
                    color: streakColor,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      S.streakDaysBadge(streakDays),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: streakColor,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          // 2. 📅 Due Today Pill (tappable when dueTodayCount > 0)
          Expanded(
            child: Material(
              color: colorScheme.primaryContainer.withValues(alpha: 0.65),
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                key: const Key('home-due-today-badge'),
                borderRadius: BorderRadius.circular(10),
                onTap: onTapDueToday,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: colorScheme.outlineVariant),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.event_available_outlined,
                        size: 18,
                        color: colorScheme.onPrimaryContainer,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          S.dueTodayBadge(dueTodayCount),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.labelLarge?.copyWith(
                                    color: colorScheme.onPrimaryContainer,
                                    fontWeight: FontWeight.w600,
                                  ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Polite, understated announcement / sponsor card managed remotely via the
/// `Reklama` worksheet in the master Google Spreadsheet.
class _PromoBannerCard extends StatelessWidget {
  const _PromoBannerCard({
    required this.banner,
    required this.onDismiss,
  });

  final PromoBannerData banner;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final sub = banner.subtitle;
    final contact = banner.contactOrLink;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Card(
        key: const Key('promo-banner-card'),
        color: colorScheme.secondaryContainer.withValues(alpha: 0.55),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: colorScheme.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.campaign_outlined,
                size: 20,
                color: colorScheme.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            S.promoBadgeLabel,
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(
                                  color: colorScheme.onPrimaryContainer,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 10,
                                ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            banner.title,
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                    if (sub != null && sub.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        sub,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                    if (contact != null && contact.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      SelectableText(
                        contact,
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                              color: colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                key: const Key('dismiss-promo-banner'),
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close, size: 16),
                onPressed: onDismiss,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
