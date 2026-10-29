import 'dart:math';

import 'package:flutter/material.dart';

import '../data/database/app_database.dart';
import '../data/database/app_database_exception.dart';
import '../data/database/ids.dart';
import '../data/models/flashcard.dart';
import '../data/models/review_and_settings.dart';
import '../data/repositories/flashcard_repository.dart';
import 'app_scope.dart';
import 'common.dart';
import 'flashcard_image_view.dart';
import 'strings.dart';

/// Default finite cap on how many times a single card can be re-queued within
/// one study session when rated `Qayta` or `Qıyın` (initial pass + up to 2
/// repeats = at most 3 appearances per session).
const int kDefaultMaxRequeuesPerCard = 2;

/// One card presentation step inside a study session.
class StudyStep {
  StudyStep({
    required this.card,
    this.lastCalculatedIntervalDays,
  });

  Flashcard card;
  bool revealed = false;
  ReviewRating? rating;
  bool markedMastered = false;
  int? lastCalculatedIntervalDays;
}

/// Pure, testable session queue that filters out non-learning cards,
/// prioritizes due cards ahead of not-yet-due cards, shuffles within each
/// priority group, tracks progress, supports navigating back/forth across seen
/// steps without losing state, and enforces a finite repetition policy.
class StudySessionQueue {
  StudySessionQueue(
    List<Flashcard> cards, {
    Random? random,
    this.maxRequeuesPerCard = kDefaultMaxRequeuesPerCard,
    String? sessionId,
  }) : sessionId = sessionId ?? generateId() {
    final rng = random ?? Random();
    final eligible = cards
        .where((c) => c.status == CardStatus.learning)
        .toList()
      ..shuffle(rng);
    totalUniqueCards = eligible.length;
    for (final c in eligible) {
      _steps.add(StudyStep(card: c));
    }
  }

  /// Builds a queue from [PrioritizedFlashcard] records so that due/new cards
  /// (`isDue == true`) are shuffled and placed before not-yet-due learning
  /// cards (`isDue == false`).
  StudySessionQueue.fromPrioritized(
    List<PrioritizedFlashcard> items, {
    Random? random,
    this.maxRequeuesPerCard = kDefaultMaxRequeuesPerCard,
    String? sessionId,
  }) : sessionId = sessionId ?? generateId() {
    final rng = random ?? Random();
    final eligible = items
        .where((item) => item.card.status == CardStatus.learning)
        .toList();
    final dueGroup = eligible.where((i) => i.isDue).toList()..shuffle(rng);
    final laterGroup = eligible.where((i) => !i.isDue).toList()..shuffle(rng);
    final ordered = [...dueGroup, ...laterGroup];
    totalUniqueCards = ordered.length;
    for (final item in ordered) {
      _steps.add(
        StudyStep(
          card: item.card,
          lastCalculatedIntervalDays: item.lastIntervalDays,
        ),
      );
    }
  }

  final String sessionId;
  late final int totalUniqueCards;
  final int maxRequeuesPerCard;
  final List<StudyStep> _steps = [];
  final Map<String, int> _requeueCount = {};
  final Set<String> _resolvedCardIds = {};

  int _activeIndex = 0;
  int _viewIndex = 0;

  bool get isEmpty => _steps.isEmpty;
  bool get isCompleted => _steps.isNotEmpty && _activeIndex >= _steps.length;

  List<StudyStep> get steps => List.unmodifiable(_steps);
  int get activeIndex => _activeIndex;
  int get viewIndex => _viewIndex;
  int get completedUniqueCount => _resolvedCardIds.length;
  int get remainingQueueCount =>
      isCompleted ? 0 : (_steps.length - _activeIndex);
  int get totalReviewsCompleted => _activeIndex;

  StudyStep get currentViewStep => _steps[_viewIndex];
  bool get isViewingHistory => _viewIndex < _activeIndex;
  bool get canGoPrevious => !isEmpty && !isCompleted && _viewIndex > 0;
  bool get canGoNext => !isEmpty && !isCompleted && _viewIndex < _activeIndex;

  void goPrevious() {
    if (canGoPrevious) _viewIndex--;
  }

  void goNext() {
    if (canGoNext) _viewIndex++;
  }

  void toggleReveal() {
    if (isEmpty || isCompleted) return;
    currentViewStep.revealed = !currentViewStep.revealed;
  }

  /// Applies [rating] to the active step. Returns `false` if the step was
  /// already rated/mastered or the user is viewing a historical step.
  bool recordRating(
    ReviewRating rating, {
    int? calculatedIntervalDays,
    bool forceResolve = false,
  }) {
    if (isEmpty || isCompleted || isViewingHistory) return false;
    final step = _steps[_activeIndex];
    if (step.rating != null || step.markedMastered) return false;

    step.rating = rating;
    if (calculatedIntervalDays != null) {
      step.lastCalculatedIntervalDays = calculatedIntervalDays;
    }
    final cardId = step.card.id;
    final shouldRepeat = !forceResolve &&
        (rating == ReviewRating.again || rating == ReviewRating.hard);
    final requeuesSoFar = _requeueCount[cardId] ?? 0;

    if (shouldRepeat && requeuesSoFar < maxRequeuesPerCard) {
      _requeueCount[cardId] = requeuesSoFar + 1;
      _steps.add(
        StudyStep(
          card: step.card,
          lastCalculatedIntervalDays: step.lastCalculatedIntervalDays,
        ),
      );
    } else {
      _resolvedCardIds.add(cardId);
    }

    _activeIndex++;
    _viewIndex = _activeIndex;
    return true;
  }

  /// Marks the active card as mastered in this session, removes any pending
  /// future steps for the same card, and advances to the next step.
  bool markCurrentCardMastered() {
    if (isEmpty || isCompleted || isViewingHistory) return false;
    final step = _steps[_activeIndex];
    if (step.rating != null || step.markedMastered) return false;

    step.markedMastered = true;
    step.card = step.card.copyWith(status: CardStatus.mastered);
    final cardId = step.card.id;
    _resolvedCardIds.add(cardId);

    // Remove any future queued repeats of this card
    for (var i = _steps.length - 1; i > _activeIndex; i--) {
      if (_steps[i].card.id == cardId) {
        _steps.removeAt(i);
      }
    }

    _activeIndex++;
    _viewIndex = _activeIndex;
    return true;
  }
}

/// Study session screen supporting both single-deck and whole-subject study.
class StudySessionScreen extends StatefulWidget {
  const StudySessionScreen._({
    super.key,
    required this.title,
    required this.loadPrioritizedCards,
    this.random,
    this.maxRequeuesPerCard = kDefaultMaxRequeuesPerCard,
  });

  /// Starts a study session for eligible learning cards in [deckId],
  /// prioritizing due and new cards.
  factory StudySessionScreen.forDeck({
    Key? key,
    required String deckId,
    required String deckName,
    Random? random,
    int maxRequeuesPerCard = kDefaultMaxRequeuesPerCard,
    bool onlyDue = false,
  }) =>
      StudySessionScreen._(
        key: key,
        title: deckName,
        random: random,
        maxRequeuesPerCard: maxRequeuesPerCard,
        loadPrioritizedCards: (db) =>
            db.flashcards.listEligibleByDeck(deckId, onlyDue: onlyDue),
      );

  /// Starts a study session for eligible learning cards across all decks in
  /// [subjectId], prioritizing due and new cards.
  factory StudySessionScreen.forSubject({
    Key? key,
    required String subjectId,
    required String subjectName,
    Random? random,
    int maxRequeuesPerCard = kDefaultMaxRequeuesPerCard,
    bool onlyDue = false,
  }) =>
      StudySessionScreen._(
        key: key,
        title: subjectName,
        random: random,
        maxRequeuesPerCard: maxRequeuesPerCard,
        loadPrioritizedCards: (db) =>
            db.flashcards.listEligibleBySubject(subjectId, onlyDue: onlyDue),
      );

  final String title;
  final Future<List<PrioritizedFlashcard>> Function(AppDatabase db)
      loadPrioritizedCards;
  final Random? random;
  final int maxRequeuesPerCard;

  @override
  State<StudySessionScreen> createState() => _StudySessionScreenState();
}

class _StudySessionScreenState extends State<StudySessionScreen> {
  Future<StudySessionQueue>? _sessionFuture;
  bool _submitting = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sessionFuture ??= _startNewSession();
  }

  Future<StudySessionQueue> _startNewSession() async {
    final db = AppScope.of(context);
    final items = await widget.loadPrioritizedCards(db);
    return StudySessionQueue.fromPrioritized(
      items,
      random: widget.random,
      maxRequeuesPerCard: widget.maxRequeuesPerCard,
    );
  }

  void _restart() {
    setState(() {
      _submitting = false;
      _sessionFuture = _startNewSession();
    });
  }

  Future<void> _submitRating(
    StudySessionQueue queue,
    ReviewRating rating,
  ) async {
    if (_submitting || queue.isCompleted || queue.isViewingHistory) return;
    final step = queue.currentViewStep;
    if (step.rating != null || step.markedMastered) return;

    setState(() => _submitting = true);
    try {
      final result = await AppScope.of(context).reviews.recordScheduledReview(
            flashcardId: step.card.id,
            rating: rating,
            sessionId: queue.sessionId,
          );
      if (!mounted) return;
      setState(() {
        queue.recordRating(
          rating,
          calculatedIntervalDays: result.schedule.intervalDays,
          forceResolve: result.autoMastered,
        );
        _submitting = false;
      });
      if (result.autoMastered && mounted) {
        showMessage(context, S.cardAutoMastered);
      }
    } on AppDatabaseException catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      showMessage(context, dbErrorMessage(e));
    }
  }

  Future<void> _markMastered(StudySessionQueue queue) async {
    if (_submitting || queue.isCompleted || queue.isViewingHistory) return;
    final step = queue.currentViewStep;
    if (step.rating != null || step.markedMastered) return;

    setState(() => _submitting = true);
    try {
      await AppScope.of(context)
          .flashcards
          .setStatus(step.card.id, CardStatus.mastered);
      if (!mounted) return;
      setState(() {
        queue.markCurrentCardMastered();
        _submitting = false;
      });
      showMessage(context, S.cardMarkedMastered);
    } on AppDatabaseException catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      showMessage(context, dbErrorMessage(e));
    }
  }

  static String _ratingLabel(ReviewRating r) {
    switch (r) {
      case ReviewRating.again:
        return S.rateAgain;
      case ReviewRating.hard:
        return S.rateHard;
      case ReviewRating.good:
        return S.rateGood;
      case ReviewRating.easy:
        return S.rateEasy;
    }
  }

  @override
  Widget build(BuildContext context) {
    AppScope.languageOf(context);
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: AsyncView<StudySessionQueue>(
        future: _sessionFuture!,
        onRetry: _restart,
        builder: (context, queue) {
          if (queue.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.school_outlined, size: 48),
                    const SizedBox(height: 12),
                    Text(
                      S.studyEmpty,
                      key: const Key('study-empty'),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton.tonal(
                      onPressed: () => Navigator.pop(context),
                      child: Text(S.finishSession),
                    ),
                  ],
                ),
              ),
            );
          }

          if (queue.isCompleted) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.check_circle_outline, size: 56),
                    const SizedBox(height: 12),
                    Text(
                      S.sessionCompleteTitle,
                      key: const Key('study-complete-title'),
                      style: Theme.of(context).textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      S.sessionSummary(
                        queue.totalUniqueCards,
                        queue.totalReviewsCompleted,
                      ),
                      key: const Key('study-complete-summary'),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      alignment: WrapAlignment.center,
                      children: [
                        OutlinedButton.icon(
                          key: const Key('study-restart'),
                          onPressed: _restart,
                          icon: const Icon(Icons.refresh),
                          label: Text(S.restartSession),
                        ),
                        FilledButton(
                          key: const Key('study-finish'),
                          onPressed: () => Navigator.pop(context),
                          child: Text(S.finishSession),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }

          final step = queue.currentViewStep;
          final card = step.card;
          final assoc = card.associationText;
          final def = card.definitionText;
          final calcInterval = step.lastCalculatedIntervalDays;
          final hasImage =
              card.imagePath != null && card.imagePath!.trim().isNotEmpty;
          final showFrontImage = hasImage &&
              (card.imagePlacement == ImagePlacement.front ||
                  card.imagePlacement == ImagePlacement.both);
          final showBackImage = hasImage &&
              (card.imagePlacement == ImagePlacement.back ||
                  card.imagePlacement == ImagePlacement.both);

          final canActOnStep = !queue.isViewingHistory &&
              !_submitting &&
              step.rating == null &&
              !step.markedMastered;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Progress & step navigation bar
              Material(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    children: [
                      IconButton(
                        key: const Key('study-prev-card'),
                        tooltip: S.previousCard,
                        onPressed: queue.canGoPrevious
                            ? () => setState(queue.goPrevious)
                            : null,
                        icon: const Icon(Icons.chevron_left),
                      ),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              S.sessionProgress(
                                queue.completedUniqueCount,
                                queue.totalUniqueCards,
                                queue.remainingQueueCount,
                              ),
                              key: const Key('study-progress'),
                              style: Theme.of(context).textTheme.labelLarge,
                              textAlign: TextAlign.center,
                            ),
                            Text(
                              S.stepIndicator(
                                queue.viewIndex + 1,
                                queue.steps.length,
                              ),
                              key: const Key('study-step-indicator'),
                              style: Theme.of(context).textTheme.bodySmall,
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        key: const Key('study-next-card'),
                        tooltip: S.nextCard,
                        onPressed:
                            queue.canGoNext ? () => setState(queue.goNext) : null,
                        icon: const Icon(Icons.chevron_right),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: CenteredBody(
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
                                card.targetText,
                                key: const Key('study-target-text'),
                                style:
                                    Theme.of(context).textTheme.headlineSmall,
                                textAlign: TextAlign.center,
                              ),
                              if (assoc != null && assoc.isNotEmpty) ...[
                                const SizedBox(height: 12),
                                Text(
                                  assoc,
                                  key: const Key('study-association-text'),
                                  style: Theme.of(context).textTheme.bodyLarge,
                                  textAlign: TextAlign.center,
                                ),
                              ],
                              if (calcInterval != null) ...[
                                const SizedBox(height: 10),
                                Text(
                                  S.calculatedNextReview(calcInterval),
                                  key: const Key('study-calculated-interval'),
                                  style: Theme.of(context).textTheme.bodySmall,
                                  textAlign: TextAlign.center,
                                ),
                              ],
                              if (showFrontImage) ...[
                                const SizedBox(height: 16),
                                FlashcardImageView(
                                  key: const Key('study-image-front'),
                                  path: card.imagePath!,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      FilledButton.tonal(
                        key: const Key('study-toggle-definition'),
                        onPressed: () => setState(queue.toggleReveal),
                        child: Text(
                          step.revealed ? S.hideDefinition : S.showDefinition,
                        ),
                      ),
                      if (step.revealed) ...[
                        const SizedBox(height: 16),
                        Card(
                          key: const Key('study-definition-card'),
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  (def == null || def.isEmpty)
                                      ? S.noDefinition
                                      : def,
                                  key: const Key('study-definition-text'),
                                  style: Theme.of(context).textTheme.bodyLarge,
                                  textAlign: TextAlign.center,
                                ),
                                if (showBackImage) ...[
                                  const SizedBox(height: 16),
                                  FlashcardImageView(
                                    key: const Key('study-image-back'),
                                    path: card.imagePath!,
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
              ),
              if (queue.isViewingHistory &&
                  (step.rating != null || step.markedMastered))
                Material(
                  color: Theme.of(context).colorScheme.secondaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Text(
                      step.markedMastered
                          ? S.statusMastered
                          : S.alreadyRated(_ratingLabel(step.rating!)),
                      key: const Key('study-already-rated'),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                )
              else ...[
                // Separate «Yad boldı» control above the four rating buttons
                Material(
                  color: const Color(0xFF1E1E24),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    child: CenteredBody(
                      child: OutlinedButton.icon(
                        key: const Key('mark-mastered-button'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFFFD54F),
                          side: const BorderSide(color: Color(0xFFFFD54F)),
                        ),
                        onPressed:
                            canActOnStep ? () => _markMastered(queue) : null,
                        icon: const Icon(Icons.workspace_premium_outlined,
                            size: 18),
                        label: Text(S.markMastered),
                      ),
                    ),
                  ),
                ),
                _AnkiRatingBar(
                  enabled: canActOnStep,
                  onRate: (r) => _submitRating(queue, r),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// Bottom-aligned four-button rating bar styled after Anki's mobile layout:
/// compact dark bar with interval captions above bold contrasting rating labels.
class _AnkiRatingBar extends StatelessWidget {
  const _AnkiRatingBar({
    required this.enabled,
    required this.onRate,
  });

  final bool enabled;
  final ValueChanged<ReviewRating> onRate;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF1E1E24),
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: CenteredBody(
            child: Row(
              children: [
                _RatingButton(
                  buttonKey: const Key('rate-again'),
                  intervalText: S.intervalAgain,
                  labelText: S.rateAgain,
                  backgroundColor: const Color(0xFF3A2326),
                  accentColor: const Color(0xFFFF6B6B),
                  enabled: enabled,
                  onTap: () => onRate(ReviewRating.again),
                ),
                const SizedBox(width: 6),
                _RatingButton(
                  buttonKey: const Key('rate-hard'),
                  intervalText: S.intervalHard,
                  labelText: S.rateHard,
                  backgroundColor: const Color(0xFF383024),
                  accentColor: const Color(0xFFFFB74D),
                  enabled: enabled,
                  onTap: () => onRate(ReviewRating.hard),
                ),
                const SizedBox(width: 6),
                _RatingButton(
                  buttonKey: const Key('rate-good'),
                  intervalText: S.intervalGood,
                  labelText: S.rateGood,
                  backgroundColor: const Color(0xFF21372A),
                  accentColor: const Color(0xFF69F0AE),
                  enabled: enabled,
                  onTap: () => onRate(ReviewRating.good),
                ),
                const SizedBox(width: 6),
                _RatingButton(
                  buttonKey: const Key('rate-easy'),
                  intervalText: S.intervalEasy,
                  labelText: S.rateEasy,
                  backgroundColor: const Color(0xFF213242),
                  accentColor: const Color(0xFF64B5F6),
                  enabled: enabled,
                  onTap: () => onRate(ReviewRating.easy),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RatingButton extends StatelessWidget {
  const _RatingButton({
    required this.buttonKey,
    required this.intervalText,
    required this.labelText,
    required this.backgroundColor,
    required this.accentColor,
    required this.enabled,
    required this.onTap,
  });

  final Key buttonKey;
  final String intervalText;
  final String labelText;
  final Color backgroundColor;
  final Color accentColor;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: enabled ? backgroundColor : backgroundColor.withAlpha(120),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          key: buttonKey,
          borderRadius: BorderRadius.circular(10),
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    intervalText,
                    style: const TextStyle(
                      color: Color(0xFFB0B3B8),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    labelText,
                    style: TextStyle(
                      color: accentColor,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
