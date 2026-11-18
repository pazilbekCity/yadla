import 'package:flutter/material.dart';

import '../data/database/app_database_exception.dart';
import '../data/models/catalog_models.dart';
import '../data/models/flashcard.dart';
import 'app_scope.dart';
import 'common.dart';
import 'excel_import_dialog.dart';
import 'flashcard_editor_screen.dart';
import 'flashcard_preview_screen.dart';
import 'strings.dart';
import 'study_session_screen.dart';

/// Flashcards list screen for either a [Deck] or directly for a [Topic]
/// (creating/reusing the topic's default deck on demand when adding or
/// importing cards).
class DeckScreen extends StatefulWidget {
  const DeckScreen({
    super.key,
    required Deck this.deck,
    this.pickXlsxFile,
  }) : topic = null;

  const DeckScreen.forTopic({
    super.key,
    required Topic this.topic,
    this.pickXlsxFile,
  }) : deck = null;

  final Deck? deck;
  final Topic? topic;
  final XlsxFilePicker? pickXlsxFile;

  @override
  State<DeckScreen> createState() => _DeckScreenState();
}

class _DeckScreenState extends State<DeckScreen> {
  Future<List<Flashcard>>? _future;
  bool _searching = false;
  final _searchController = TextEditingController();
  String _searchQuery = '';

  String get _screenTitle => widget.topic?.name ?? widget.deck!.name;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      final q = _searchController.text.trim();
      if (q != _searchQuery && mounted) {
        setState(() => _searchQuery = q);
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _toggleSearch() {
    setState(() {
      _searching = !_searching;
      if (!_searching) {
        _searchController.clear();
        _searchQuery = '';
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= _load();
  }

  Future<List<Flashcard>> _load() {
    final scope = AppScope.of(context);
    final topic = widget.topic;
    if (topic != null) {
      return scope.flashcards.listByTopic(topic.id);
    }
    return scope.flashcards.listByDeck(widget.deck!.id);
  }

  Future<String> _resolveTargetDeckId() async {
    final deck = widget.deck;
    if (deck != null) return deck.id;
    final topic = widget.topic!;
    final defaultDeck = await AppScope.of(context)
        .decks
        .getOrCreateDefaultForTopic(topic.id, defaultName: topic.name);
    return defaultDeck.id;
  }

  void _reload() => setState(() {
        _future = _load();
      });

  Future<void> _add() async {
    final targetDeckId = await _resolveTargetDeckId();
    if (!mounted) return;
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute<bool>(
        builder: (_) => FlashcardEditorScreen(deckId: targetDeckId),
      ),
    );
    if (saved == true && mounted) _reload();
  }

  Future<void> _edit(Flashcard card) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute<bool>(
        builder: (_) =>
            FlashcardEditorScreen(deckId: card.deckId, existing: card),
      ),
    );
    if (saved == true && mounted) _reload();
  }

  Future<void> _preview(Flashcard card) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => FlashcardPreviewScreen(card: card),
      ),
    );
  }

  Future<void> _study() async {
    final topic = widget.topic;
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => topic != null
            ? StudySessionScreen.forTopic(
                topicId: topic.id,
                topicName: topic.name,
              )
            : StudySessionScreen.forDeck(
                deckId: widget.deck!.id,
                deckName: widget.deck!.name,
              ),
      ),
    );
    if (mounted) _reload();
  }

  Future<void> _importExcel() async {
    final targetDeckId = await _resolveTargetDeckId();
    if (!mounted) return;
    final imported = await runExcelImportFlow(
      context,
      deckId: targetDeckId,
      pickFile: widget.pickXlsxFile,
    );
    if (imported && mounted) _reload();
  }

  Future<void> _changeStatus(Flashcard card, CardStatus newStatus) async {
    try {
      await AppScope.of(context).flashcards.setStatus(card.id, newStatus);
      if (!mounted) return;
      _reload();
      final msg = switch (newStatus) {
        CardStatus.learning => S.cardRestoredToLearning,
        CardStatus.mastered => S.cardMarkedMastered,
        CardStatus.suspended => S.cardSuspended,
      };
      showMessage(context, msg);
    } on AppDatabaseException catch (e) {
      if (mounted) {
        showMessage(context, dbErrorMessage(e, name: card.targetText));
      }
    }
  }

  Future<void> _delete(Flashcard card) async {
    if (!await confirmDelete(context, card.targetText) || !mounted) return;
    try {
      await AppScope.of(context).flashcards.delete(card.id);
      if (mounted) _reload();
    } on AppDatabaseException catch (e) {
      if (mounted) {
        showMessage(context, dbErrorMessage(e, name: card.targetText));
      }
    }
  }

  static String? _statusBadgeText(CardStatus s) {
    switch (s) {
      case CardStatus.learning:
        return null;
      case CardStatus.mastered:
        return S.statusMastered;
      case CardStatus.suspended:
        return S.statusSuspended;
    }
  }

  @override
  Widget build(BuildContext context) {
    AppScope.languageOf(context);
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(_screenTitle),
        actions: [
          IconButton(
            key: const Key('search-cards-button'),
            tooltip: S.searchCards,
            icon: Icon(_searching ? Icons.search_off : Icons.search),
            onPressed: _toggleSearch,
          ),
          IconButton(
            key: const Key('import-excel-button'),
            tooltip: S.importExcel,
            icon: const Icon(Icons.upload_file_outlined),
            onPressed: _importExcel,
          ),
        ],
      ),
      body: CenteredBody(
        child: AsyncView<List<Flashcard>>(
          future: _future!,
          onRetry: _reload,
          builder: (context, cards) {
            final filteredCards = _filterCardsByTarget(cards, _searchQuery);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Material(
                  color: colorScheme.surfaceContainerHighest,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            S.cardCount(cards.length),
                            key: const Key('card-count'),
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ),
                        FilledButton.tonalIcon(
                          key: const Key('study-deck-button'),
                          onPressed: _study,
                          icon: const Icon(Icons.play_arrow),
                          label: Text(
                            widget.topic != null ? S.studyTopic : S.studyDeck,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_searching)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                    child: TextField(
                      key: const Key('search-cards-field'),
                      controller: _searchController,
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: S.searchByTargetHint,
                        prefixIcon: const Icon(Icons.search, size: 20),
                        suffixIcon: _searchQuery.isEmpty
                            ? null
                            : IconButton(
                                key: const Key('clear-search-button'),
                                icon: const Icon(Icons.clear, size: 18),
                                onPressed: _searchController.clear,
                              ),
                      ),
                    ),
                  ),
                Expanded(
                  child: cards.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(S.flashcardsEmpty,
                                textAlign: TextAlign.center),
                          ),
                        )
                      : filteredCards.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text(
                                  S.searchNoResults,
                                  key: const Key('search-no-results'),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.only(bottom: 88),
                              itemCount: filteredCards.length,
                              separatorBuilder: (_, _) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final c = filteredCards[index];
                                final subtitle =
                                    c.definitionText ?? c.associationText;
                                final badge = _statusBadgeText(c.status);
                                final hasPage = c.pageNumber != null &&
                                    c.pageNumber!.trim().isNotEmpty;
                                return ListTile(
                                  title: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          c.targetText,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      if (hasPage)
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(left: 8),
                                          child: _PageNumberBadge(
                                            key: Key(
                                                'card-page-badge-${c.id}'),
                                            pageNumber: c.pageNumber!.trim(),
                                          ),
                                        ),
                                      if (badge != null)
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(left: 8),
                                          child: Chip(
                                            key: Key(
                                                'card-status-chip-${c.id}'),
                                            label: Text(badge),
                                            visualDensity:
                                                VisualDensity.compact,
                                          ),
                                        ),
                                    ],
                                  ),
                                  subtitle:
                                      (subtitle == null || subtitle.isEmpty)
                                          ? null
                                          : Text(
                                              subtitle,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                  onTap: () => _preview(c),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      PopupMenuButton<CardStatus>(
                                        key: Key('card-status-menu-${c.id}'),
                                        icon: const Icon(Icons.tune_outlined),
                                        onSelected: (s) => _changeStatus(c, s),
                                        itemBuilder: (_) => [
                                          if (c.status != CardStatus.learning)
                                            PopupMenuItem(
                                              value: CardStatus.learning,
                                              child: Text(S.restoreToLearning),
                                            ),
                                          if (c.status != CardStatus.mastered)
                                            PopupMenuItem(
                                              value: CardStatus.mastered,
                                              child: Text(S.markMastered),
                                            ),
                                          if (c.status != CardStatus.suspended)
                                            PopupMenuItem(
                                              value: CardStatus.suspended,
                                              child: Text(S.suspendCard),
                                            ),
                                        ],
                                      ),
                                      IconButton(
                                        tooltip: S.preview,
                                        icon: const Icon(
                                            Icons.visibility_outlined),
                                        onPressed: () => _preview(c),
                                      ),
                                      IconButton(
                                        tooltip: S.edit,
                                        icon: const Icon(Icons.edit_outlined),
                                        onPressed: () => _edit(c),
                                      ),
                                      IconButton(
                                        tooltip: S.delete,
                                        icon: const Icon(Icons.delete_outline),
                                        onPressed: () => _delete(c),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                ),
              ],
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('fab-add-flashcard'),
        onPressed: _add,
        icon: const Icon(Icons.add),
        label: Text(S.addFlashcard),
      ),
    );
  }
}

List<Flashcard> _filterCardsByTarget(List<Flashcard> cards, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return cards;
  final startsWithMatches = <Flashcard>[];
  final containsMatches = <Flashcard>[];
  for (final c in cards) {
    final targetLower = c.targetText.trim().toLowerCase();
    if (targetLower.startsWith(q)) {
      startsWithMatches.add(c);
    } else if (targetLower.contains(q)) {
      containsMatches.add(c);
    }
  }
  return [...startsWithMatches, ...containsMatches];
}

class _PageNumberBadge extends StatelessWidget {
  const _PageNumberBadge({
    super.key,
    required this.pageNumber,
  });

  final String pageNumber;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.menu_book_outlined,
            size: 12,
            color: colorScheme.onPrimaryContainer,
          ),
          const SizedBox(width: 4),
          Text(
            S.bookPageBadge(pageNumber),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }
}

/// Dedicated search screen for finding flashcards across an entire [Book] by
/// target word (`Gilt sóz`), displaying each found card's definition and its
/// textbook page number (`📖 <page>-bet`).
class BookFlashcardSearchScreen extends StatefulWidget {
  const BookFlashcardSearchScreen({
    super.key,
    required this.book,
  });

  final Book book;

  @override
  State<BookFlashcardSearchScreen> createState() =>
      _BookFlashcardSearchScreenState();
}

class _BookFlashcardSearchScreenState extends State<BookFlashcardSearchScreen> {
  Future<List<Flashcard>>? _future;
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      final q = _searchController.text.trim();
      if (q != _searchQuery && mounted) {
        setState(() => _searchQuery = q);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= AppScope.of(context).flashcards.listByBook(widget.book.id);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _reload() => setState(() {
        _future = AppScope.of(context).flashcards.listByBook(widget.book.id);
      });

  Future<void> _preview(Flashcard card) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => FlashcardPreviewScreen(card: card),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    AppScope.languageOf(context);
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.book.name} — ${S.searchCards}'),
      ),
      body: CenteredBody(
        child: AsyncView<List<Flashcard>>(
          future: _future!,
          onRetry: _reload,
          builder: (context, cards) {
            final filtered = _filterCardsByTarget(cards, _searchQuery);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: TextField(
                    key: const Key('search-cards-field'),
                    controller: _searchController,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: S.searchByTargetHint,
                      prefixIcon: const Icon(Icons.search, size: 20),
                      suffixIcon: _searchQuery.isEmpty
                          ? null
                          : IconButton(
                              key: const Key('clear-search-button'),
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: _searchController.clear,
                            ),
                    ),
                  ),
                ),
                Expanded(
                  child: filtered.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              S.searchNoResults,
                              key: const Key('search-no-results'),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                          itemCount: filtered.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final c = filtered[index];
                            final sub = c.definitionText ?? c.associationText;
                            final hasPage = c.pageNumber != null &&
                                c.pageNumber!.trim().isNotEmpty;
                            return Card(
                              child: ListTile(
                                key: Key('search-result-card-${c.id}'),
                                title: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        c.targetText,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    if (hasPage)
                                      Padding(
                                        padding: const EdgeInsets.only(left: 8),
                                        child: _PageNumberBadge(
                                          key: Key('card-page-badge-${c.id}'),
                                          pageNumber: c.pageNumber!.trim(),
                                        ),
                                      ),
                                  ],
                                ),
                                subtitle: (sub == null || sub.isEmpty)
                                    ? null
                                    : Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Text(
                                          sub,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () => _preview(c),
                              ),
                            );
                          },
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
