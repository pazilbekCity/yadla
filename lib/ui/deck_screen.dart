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
    final db = AppScope.of(context);
    final targetDeckId = await _resolveTargetDeckId();
    if (widget.topic != null) {
      await QuickCardDestinationResolver.recordLastActiveTopic(
        db,
        widget.topic!.id,
      );
    }
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

  Future<void> _moveCard(Flashcard card) async {
    final db = AppScope.of(context);
    final options = await QuickCardDestinationResolver.loadAllDestinations(db);
    if (!mounted || options.isEmpty) return;
    final picked = await showSelectDestinationDialog(
      context,
      options: options,
      currentTopicId: widget.topic?.id,
    );
    if (picked == null || !mounted) return;
    if (picked.deckId == card.deckId) return;
    try {
      await db.flashcards.update(card.copyWith(deckId: picked.deckId));
      await QuickCardDestinationResolver.recordLastActiveTopic(
        db,
        picked.topicId,
      );
      if (!mounted) return;
      _reload();
      showMessage(context, S.cardMovedSuccess);
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
    final canPop = Navigator.canPop(context);
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(116),
        child: Material(
          color: colorScheme.surface,
          elevation: 0,
          child: SafeArea(
            bottom: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Row 1: [Home (small)]   [+ Karta qosıw (large)]   [🔍 Search (right)]
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
                  child: Row(
                    children: [
                      IconButton.outlined(
                        key: const Key('home-nav-button'),
                        tooltip: S.homeTooltip,
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.home_outlined, size: 20),
                        onPressed: () => Navigator.of(context)
                            .popUntil((route) => route.isFirst),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton.tonalIcon(
                          key: const Key('fab-add-flashcard'),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            side: BorderSide(color: colorScheme.outlineVariant),
                          ),
                          onPressed: _add,
                          icon: const Icon(Icons.add, size: 18),
                          label: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              S.addFlashcard,
                              maxLines: 1,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filledTonal(
                        key: const Key('search-cards-button'),
                        tooltip: S.searchCards,
                        visualDensity: VisualDensity.compact,
                        icon: Icon(
                          _searching ? Icons.search_off : Icons.search,
                          size: 20,
                        ),
                        onPressed: _toggleSearch,
                      ),
                    ],
                  ),
                ),
                // Row 2: [← Back] Topic/Deck name + Excel import
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 8, 4),
                  child: Row(
                    children: [
                      if (canPop) const BackButton(),
                      if (!canPop) const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _screenTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                      ),
                      IconButton(
                        key: const Key('import-excel-button'),
                        tooltip: S.importExcel,
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.upload_file_outlined),
                        onPressed: _importExcel,
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: colorScheme.outlineVariant),
              ],
            ),
          ),
        ),
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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Text(
                      S.cardCount(cards.length),
                      key: const Key('card-count'),
                      style: Theme.of(context).textTheme.titleSmall,
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
                              padding:
                                  const EdgeInsets.fromLTRB(16, 10, 16, 24),
                              itemCount: filteredCards.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (context, index) {
                                final c = filteredCards[index];
                                final subtitle =
                                    c.definitionText ?? c.associationText;
                                final hasSubtitle =
                                    subtitle != null && subtitle.isNotEmpty;
                                final badge = _statusBadgeText(c.status);
                                final hasPage = c.pageNumber != null &&
                                    c.pageNumber!.trim().isNotEmpty;
                                final isMastered =
                                    c.status == CardStatus.mastered;
                                final isDark = colorScheme.brightness ==
                                    Brightness.dark;
                                final cardColor = isMastered
                                    ? (isDark
                                        ? const Color(0xFF1D332B)
                                        : const Color(0xFFF1F9F4))
                                    : colorScheme.surface;
                                final borderColor = isMastered
                                    ? (isDark
                                        ? const Color(0xFF40916C)
                                        : const Color(0xFF95D5B2))
                                    : colorScheme.outlineVariant;
                                return Card(
                                  color: cardColor,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    side: BorderSide(color: borderColor),
                                  ),
                                  child: ListTile(
                                    contentPadding:
                                        const EdgeInsets.fromLTRB(14, 6, 6, 6),
                                    title: Text(
                                      c.targetText,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 16,
                                      ),
                                    ),
                                    subtitle: (!hasSubtitle &&
                                            !hasPage &&
                                            badge == null)
                                        ? null
                                        : Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              if (hasSubtitle) ...[
                                                const SizedBox(height: 4),
                                                Text(
                                                  subtitle,
                                                  maxLines: 2,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ],
                                              if (hasPage || badge != null) ...[
                                                const SizedBox(height: 6),
                                                Wrap(
                                                  spacing: 6,
                                                  runSpacing: 4,
                                                  crossAxisAlignment:
                                                      WrapCrossAlignment.center,
                                                  children: [
                                                    if (hasPage)
                                                      _PageNumberBadge(
                                                        key: Key(
                                                            'card-page-badge-${c.id}'),
                                                        pageNumber: c
                                                            .pageNumber!
                                                            .trim(),
                                                      ),
                                                    if (badge != null)
                                                      Chip(
                                                        key: Key(
                                                            'card-status-chip-${c.id}'),
                                                        label: Text(badge),
                                                        visualDensity:
                                                            VisualDensity
                                                                .compact,
                                                        materialTapTargetSize:
                                                            MaterialTapTargetSize
                                                                .shrinkWrap,
                                                      ),
                                                  ],
                                                ),
                                              ],
                                            ],
                                          ),
                                    onTap: () => _preview(c),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        PopupMenuButton<_CardMenuAction>(
                                          key: Key('card-status-menu-${c.id}'),
                                          padding: const EdgeInsets.all(6),
                                          constraints: const BoxConstraints(),
                                          icon: const Icon(
                                            Icons.tune_outlined,
                                            size: 20,
                                          ),
                                          onSelected: (action) {
                                            switch (action) {
                                              case _CardMenuAction.learning:
                                                _changeStatus(
                                                  c,
                                                  CardStatus.learning,
                                                );
                                              case _CardMenuAction.mastered:
                                                _changeStatus(
                                                  c,
                                                  CardStatus.mastered,
                                                );
                                              case _CardMenuAction.suspended:
                                                _changeStatus(
                                                  c,
                                                  CardStatus.suspended,
                                                );
                                              case _CardMenuAction.moveToTopic:
                                                _moveCard(c);
                                            }
                                          },
                                          itemBuilder: (_) => [
                                            if (c.status != CardStatus.learning)
                                              PopupMenuItem(
                                                value: _CardMenuAction.learning,
                                                child:
                                                    Text(S.restoreToLearning),
                                              ),
                                            if (c.status != CardStatus.mastered)
                                              PopupMenuItem(
                                                value: _CardMenuAction.mastered,
                                                child: Text(S.markMastered),
                                              ),
                                            if (c.status !=
                                                CardStatus.suspended)
                                              PopupMenuItem(
                                                value:
                                                    _CardMenuAction.suspended,
                                                child: Text(S.suspendCard),
                                              ),
                                            PopupMenuItem(
                                              key: Key('move-card-${c.id}'),
                                              value:
                                                  _CardMenuAction.moveToTopic,
                                              child: Text(S.moveCardToTopic),
                                            ),
                                          ],
                                        ),
                                        IconButton(
                                          tooltip: S.preview,
                                          visualDensity: VisualDensity.compact,
                                          padding: const EdgeInsets.all(5),
                                          constraints: const BoxConstraints(),
                                          icon: const Icon(
                                            Icons.visibility_outlined,
                                            size: 19,
                                          ),
                                          onPressed: () => _preview(c),
                                        ),
                                        IconButton(
                                          tooltip: S.edit,
                                          visualDensity: VisualDensity.compact,
                                          padding: const EdgeInsets.all(5),
                                          constraints: const BoxConstraints(),
                                          icon: const Icon(
                                            Icons.edit_outlined,
                                            size: 19,
                                          ),
                                          onPressed: () => _edit(c),
                                        ),
                                        IconButton(
                                          tooltip: S.delete,
                                          visualDensity: VisualDensity.compact,
                                          padding: const EdgeInsets.all(5),
                                          constraints: const BoxConstraints(),
                                          icon: const Icon(
                                            Icons.delete_outline,
                                            size: 19,
                                          ),
                                          onPressed: () => _delete(c),
                                        ),
                                      ],
                                    ),
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
      bottomNavigationBar: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: SizedBox(
          height: 48,
          child: FilledButton.icon(
            key: const Key('study-deck-button'),
            onPressed: _study,
            icon: const Icon(Icons.play_arrow_rounded),
            label: Text(
              widget.topic != null ? S.studyTopic : S.studyDeck,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ),
    );
  }
}

enum _CardMenuAction {
  learning,
  mastered,
  suspended,
  moveToTopic,
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

/// Dedicated search screen for finding flashcards across a [Book], a [Subject],
/// or the entire database by target word (`Gilt sóz`), displaying each found
/// card's definition and its textbook page number (`📖 <page>-bet`).
class BookFlashcardSearchScreen extends StatefulWidget {
  const BookFlashcardSearchScreen({
    super.key,
    required Book this.book,
  }) : subject = null;

  const BookFlashcardSearchScreen.forSubject({
    super.key,
    required Subject this.subject,
  }) : book = null;

  const BookFlashcardSearchScreen.forAll({
    super.key,
  })  : book = null,
        subject = null;

  final Book? book;
  final Subject? subject;

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

  Future<List<Flashcard>> _loadCards() {
    final repo = AppScope.of(context).flashcards;
    if (widget.book != null) {
      return repo.listByBook(widget.book!.id);
    }
    if (widget.subject != null) {
      return repo.listBySubject(widget.subject!.id);
    }
    return repo.listAll();
  }

  String get _title {
    if (widget.book != null) {
      return '${widget.book!.name} — ${S.searchCards}';
    }
    if (widget.subject != null) {
      return '${widget.subject!.name} — ${S.searchCards}';
    }
    return S.searchCards;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= _loadCards();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _reload() => setState(() {
        _future = _loadCards();
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
        title: Text(_title),
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
