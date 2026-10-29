import 'package:flutter/material.dart';

import '../data/database/app_database_exception.dart';
import '../data/models/catalog_models.dart';
import '../data/services/backup_service.dart';
import 'app_scope.dart';
import 'backup_dialogs.dart';
import 'common.dart';
import 'deck_screen.dart';
import 'strings.dart';
import 'study_session_screen.dart';

enum _BackupMenuAction { exportBackup, importBackup }

/// Home screen: lists all [Subject]s and lets the user create, edit, delete,
/// or export/restore full offline backups. Tapping a subject opens [BooksScreen].
class SubjectsScreen extends StatefulWidget {
  const SubjectsScreen({
    super.key,
    this.pickBackupFile,
    this.backupService = const BackupService(),
  });

  final BackupFilePicker? pickBackupFile;
  final BackupService backupService;

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
    final repo = AppScope.of(context).subjects;
    final saved = await showNameDialog(
      context,
      title: S.addSubject,
      onSubmit: (name, desc) => repo.create(name: name, description: desc),
    );
    if (saved && mounted) _reload();
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
  const BooksScreen({super.key, required this.subject});

  final Subject subject;

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
    final saved = await showNameDialog(
      context,
      title: S.addBook,
      onSubmit: (name, desc) => repo.create(
        subjectId: widget.subject.id,
        name: name,
        description: desc,
      ),
    );
    if (saved && mounted) _reload();
  }

  Future<void> _edit(Book b) async {
    final repo = AppScope.of(context).books;
    final saved = await showNameDialog(
      context,
      title: S.editBook,
      initialName: b.name,
      initialDescription: b.description,
      onSubmit: (name, desc) =>
          repo.update(b.copyWith(name: name, description: desc ?? '')),
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
            onTap: (b) async {
              await Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => TopicsScreen(book: b),
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
        key: const Key('fab-add-book'),
        onPressed: _add,
        icon: const Icon(Icons.add),
        label: Text(S.addBook),
      ),
    );
  }
}

/// Book screen: lists and manages [Topic]s belonging to [book].
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
    try {
      await AppScope.of(context).topics.delete(t.id);
      if (mounted) _reload();
    } on AppDatabaseException catch (e) {
      if (mounted) showMessage(context, dbErrorMessage(e, name: t.name));
    }
  }

  @override
  Widget build(BuildContext context) {
    AppScope.languageOf(context);
    return Scaffold(
      appBar: AppBar(title: Text(widget.book.name)),
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
                  builder: (_) => DecksScreen(topic: t),
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
  });

  final List<T> items;
  final String emptyText;
  final String Function(T) titleOf;
  final String? Function(T) subtitleOf;
  final ValueChanged<T> onTap;
  final ValueChanged<T> onEdit;
  final ValueChanged<T> onDelete;

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
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 88),
      itemCount: items.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final item = items[index];
        final title = titleOf(item);
        final sub = subtitleOf(item);
        return ListTile(
          title: Text(title),
          subtitle: (sub == null || sub.isEmpty) ? null : Text(sub),
          onTap: () => onTap(item),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: S.edit,
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => onEdit(item),
              ),
              IconButton(
                tooltip: S.delete,
                icon: const Icon(Icons.delete_outline),
                onPressed: () => onDelete(item),
              ),
            ],
          ),
        );
      },
    );
  }
}
