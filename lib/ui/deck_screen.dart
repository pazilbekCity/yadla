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

/// Deck screen: shows the card count, lists flashcards in [deck], and lets the
/// user create, edit, preview, import from Excel `.xlsx`, change status
/// (`learning` / `mastered` / `suspended`), or delete cards.
class DeckScreen extends StatefulWidget {
  const DeckScreen({
    super.key,
    required this.deck,
    this.pickXlsxFile,
  });

  final Deck deck;
  final XlsxFilePicker? pickXlsxFile;

  @override
  State<DeckScreen> createState() => _DeckScreenState();
}

class _DeckScreenState extends State<DeckScreen> {
  Future<List<Flashcard>>? _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= _load();
  }

  Future<List<Flashcard>> _load() =>
      AppScope.of(context).flashcards.listByDeck(widget.deck.id);

  void _reload() => setState(() {
        _future = _load();
      });

  Future<void> _add() async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute<bool>(
        builder: (_) => FlashcardEditorScreen(deckId: widget.deck.id),
      ),
    );
    if (saved == true && mounted) _reload();
  }

  Future<void> _edit(Flashcard card) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute<bool>(
        builder: (_) =>
            FlashcardEditorScreen(deckId: widget.deck.id, existing: card),
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
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => StudySessionScreen.forDeck(
          deckId: widget.deck.id,
          deckName: widget.deck.name,
        ),
      ),
    );
    if (mounted) _reload();
  }

  Future<void> _importExcel() async {
    final imported = await runExcelImportFlow(
      context,
      deckId: widget.deck.id,
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
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.deck.name),
        actions: [
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
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Material(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
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
                          label: Text(S.studyDeck),
                        ),
                      ],
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
                      : ListView.separated(
                          padding: const EdgeInsets.only(bottom: 88),
                          itemCount: cards.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final c = cards[index];
                            final subtitle =
                                c.definitionText ?? c.associationText;
                            final badge = _statusBadgeText(c.status);
                            return ListTile(
                              title: Row(
                                children: [
                                  Expanded(child: Text(c.targetText)),
                                  if (badge != null)
                                    Padding(
                                      padding: const EdgeInsets.only(left: 8),
                                      child: Chip(
                                        key: Key('card-status-chip-${c.id}'),
                                        label: Text(badge),
                                        visualDensity: VisualDensity.compact,
                                      ),
                                    ),
                                ],
                              ),
                              subtitle: (subtitle == null || subtitle.isEmpty)
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
                                    icon: const Icon(Icons.visibility_outlined),
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
