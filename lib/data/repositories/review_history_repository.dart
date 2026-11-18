import '../database/app_database_exception.dart';
import '../database/ids.dart';
import '../models/catalog_models.dart';
import '../models/flashcard.dart';
import '../models/review_and_settings.dart';
import '../services/spaced_repetition.dart';
import 'repository_base.dart';

/// Outcome of recording a scheduled study review in a transaction.
class RecordedReviewResult {
  const RecordedReviewResult({
    required this.entry,
    required this.card,
    required this.schedule,
    required this.consecutiveEasySessions,
    required this.autoMastered,
  });

  final ReviewEntry entry;
  final Flashcard card;
  final ScheduleResult schedule;
  final int consecutiveEasySessions;
  final bool autoMastered;
}

/// Storage and transactional scheduling for flashcard review records.
class ReviewHistoryRepository extends RepositoryBase {
  ReviewHistoryRepository(super.db, super.clock);

  Future<ReviewEntry> add({
    required String flashcardId,
    required ReviewRating rating,
    DateTime? reviewedAt,
    DateTime? dueAt,
    int? intervalDays,
    double? easeFactor,
    int? responseTimeMs,
    String? sessionId,
  }) =>
      guardDb('Add review', () async {
        final id = generateId();
        await db.insert('review_history', {
          'id': id,
          'flashcard_id': flashcardId,
          'reviewed_at': reviewedAt == null ? nowMs() : msFromDate(reviewedAt),
          'rating': rating.value,
          'due_at': dueAt == null ? null : msFromDate(dueAt),
          'interval_days': intervalDays,
          'ease_factor': easeFactor,
          'response_time_ms': responseTimeMs,
          'session_id': optionalText(sessionId),
        });
        final rows =
            await db.query('review_history', where: 'id = ?', whereArgs: [id]);
        return ReviewEntry.fromMap(rows.first);
      });

  /// Calculates the next spaced-repetition schedule from the card's prior
  /// history, persists the new [ReviewEntry] with [sessionId], and
  /// automatically promotes the card to [CardStatus.mastered] when it achieves
  /// [kConsecutiveEasySessionsForMastery] (4) consecutive distinct sessions
  /// rated `Ańsat` (`ReviewRating.easy`).
  Future<RecordedReviewResult> recordScheduledReview({
    required String flashcardId,
    required ReviewRating rating,
    required String sessionId,
    DateTime? reviewedAt,
    int? responseTimeMs,
    SpacedRepetitionScheduler scheduler = const SpacedRepetitionScheduler(),
  }) =>
      guardDb('Record scheduled review', () async {
        final validSessionId = requireText(sessionId, 'Session ID');
        return db.transaction((txn) async {
          final cardRows = await txn.query(
            'flashcards',
            where: 'id = ?',
            whereArgs: [flashcardId],
          );
          if (cardRows.isEmpty) {
            throw AppDatabaseException(
              DbErrorKind.invalidReference,
              'Record scheduled review: referenced parent record does not exist.',
            );
          }
          var card = Flashcard.fromMap(cardRows.first);

          final historyRows = await txn.query(
            'review_history',
            where: 'flashcard_id = ?',
            whereArgs: [flashcardId],
            orderBy: 'reviewed_at ASC, rowid ASC',
          );
          final priorHistory = historyRows.map(ReviewEntry.fromMap).toList();
          final previous = priorHistory.isEmpty ? null : priorHistory.last;

          final reviewedInstant =
              (reviewedAt ?? clock()).toUtc();
          final reviewedMs = msFromDate(reviewedInstant);
          final schedule = scheduler.schedule(
            rating: rating,
            reviewedAt: reviewedInstant,
            previous: previous,
          );

          final id = generateId();
          await txn.insert('review_history', {
            'id': id,
            'flashcard_id': flashcardId,
            'reviewed_at': reviewedMs,
            'rating': rating.value,
            'due_at': msFromDate(schedule.dueAt),
            'interval_days': schedule.intervalDays,
            'ease_factor': schedule.easeFactor,
            'response_time_ms': responseTimeMs,
            'session_id': validSessionId,
          });

          final insertedRows = await txn.query(
            'review_history',
            where: 'id = ?',
            whereArgs: [id],
          );
          final entry = ReviewEntry.fromMap(insertedRows.first);

          final fullHistory = [...priorHistory, entry];
          final streak = scheduler.countConsecutiveEasySessions(
            fullHistory,
            since: card.statusChangedAt,
          );

          var autoMastered = false;
          if (streak >= kConsecutiveEasySessionsForMastery &&
              card.status != CardStatus.mastered) {
            await txn.update(
              'flashcards',
              {
                'status': CardStatus.mastered.name,
                'status_changed_at': reviewedMs,
                'updated_at': reviewedMs,
              },
              where: 'id = ?',
              whereArgs: [flashcardId],
            );
            final updatedRows = await txn.query(
              'flashcards',
              where: 'id = ?',
              whereArgs: [flashcardId],
            );
            card = Flashcard.fromMap(updatedRows.first);
            autoMastered = true;
          }

          return RecordedReviewResult(
            entry: entry,
            card: card,
            schedule: schedule,
            consecutiveEasySessions: streak,
            autoMastered: autoMastered,
          );
        });
      });

  /// Oldest first.
  Future<List<ReviewEntry>> listForFlashcard(String flashcardId) =>
      guardDb('List reviews', () async {
        final rows = await db.query('review_history',
            where: 'flashcard_id = ?',
            whereArgs: [flashcardId],
            orderBy: 'reviewed_at ASC, rowid ASC');
        return rows.map(ReviewEntry.fromMap).toList();
      });

  /// Returns the most recent review for [flashcardId], or `null` if never
  /// reviewed.
  Future<ReviewEntry?> latestForFlashcard(String flashcardId) =>
      guardDb('Latest review', () async {
        final rows = await db.query(
          'review_history',
          where: 'flashcard_id = ?',
          whereArgs: [flashcardId],
          orderBy: 'reviewed_at DESC, rowid DESC',
          limit: 1,
        );
        return rows.isEmpty ? null : ReviewEntry.fromMap(rows.first);
      });

  /// Calculates the user's current consecutive daily study streak as of [asOf]
  /// (defaults to [clock]). Counts distinct UTC calendar days on which at least
  /// one review was recorded or a card was marked mastered.
  Future<int> calculateStudyStreakDays({DateTime? asOf}) =>
      guardDb('Calculate study streak days', () async {
        final reviewRows = await db.rawQuery(
          'SELECT reviewed_at AS ts FROM review_history',
        );
        final masteredRows = await db.rawQuery(
          "SELECT status_changed_at AS ts FROM flashcards WHERE status = 'mastered' AND status_changed_at IS NOT NULL",
        );

        final activeDayKeys = <int>{};
        void addTimestamp(int? ms) {
          if (ms == null) return;
          final dt = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
          final dayEpoch = DateTime.utc(dt.year, dt.month, dt.day)
                  .millisecondsSinceEpoch ~/
              Duration.millisecondsPerDay;
          activeDayKeys.add(dayEpoch);
        }

        for (final r in reviewRows) {
          addTimestamp(r['ts'] as int?);
        }
        for (final r in masteredRows) {
          addTimestamp(r['ts'] as int?);
        }

        if (activeDayKeys.isEmpty) return 0;

        final nowUtc = (asOf ?? clock()).toUtc();
        final todayKey =
            DateTime.utc(nowUtc.year, nowUtc.month, nowUtc.day)
                    .millisecondsSinceEpoch ~/
                Duration.millisecondsPerDay;

        var cursor = todayKey;
        if (!activeDayKeys.contains(cursor)) {
          // If the user hasn't studied yet today, keep yesterday's streak alive.
          if (activeDayKeys.contains(cursor - 1)) {
            cursor = cursor - 1;
          } else {
            return 0;
          }
        }

        var streak = 0;
        while (activeDayKeys.contains(cursor)) {
          streak++;
          cursor--;
        }
        return streak;
      });
}
