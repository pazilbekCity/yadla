import 'dart:math' as math;

import '../models/review_and_settings.dart';

/// Number of consecutive, distinct study sessions in which a card must be
/// rated `Ańsat` (`ReviewRating.easy`) to be automatically marked `mastered`.
const int kConsecutiveEasySessionsForMastery = 4;

/// Default starting ease factor for cards with no prior scheduled review.
const double kInitialEaseFactor = 2.5;

/// Floor for ease factor so repeated failures never freeze a card's growth.
const double kMinEaseFactor = 1.3;

/// Early retry delay when a card is rated `Qayta` (`ReviewRating.again`).
const Duration kAgainRetryDelay = Duration(minutes: 1);

/// Calculated next-review parameters produced by [SpacedRepetitionScheduler].
class ScheduleResult {
  const ScheduleResult({
    required this.dueAt,
    required this.intervalDays,
    required this.easeFactor,
  });

  /// Next review timestamp in UTC.
  final DateTime dueAt;

  /// Scheduled interval in whole days (`0` for same-day early retry on `Qayta`).
  final int intervalDays;

  /// Updated ease factor (`>= kMinEaseFactor`).
  final double easeFactor;
}

/// Deterministic SM-2 / Anki-inspired spaced-repetition scheduler.
///
/// ### Initial & subsequent interval rules:
/// - **New or lapsed card (`previous == null` or `previous.intervalDays == 0`):**
///   - `Qayta` (1): `intervalDays = 0`, `dueAt = now + 1 minute`,
///     `ease = max(1.3, ease - 0.20)`.
///   - `Qıyın` (2): `intervalDays = 1`, `dueAt = now + 1 day`,
///     `ease = max(1.3, ease - 0.15)`.
///   - `Jaqsı` (3): `intervalDays = 1` (or `3` when graduating from a 1-day
///     interval), `dueAt = now + intervalDays`, `ease` unchanged.
///   - `Ańsat` (4): `intervalDays = 5`, `dueAt = now + 5 days`,
///     `ease = ease + 0.15`.
/// - **Review card with `prevInterval >= 1`:**
///   - `Qayta` (1): resets `intervalDays = 0` (`dueAt = now + 1 minute`),
///     `ease = max(1.3, ease - 0.20)`.
///   - `Qıyın` (2): short growth `max(1, round(prevInterval * 1.2))`,
///     `ease = max(1.3, ease - 0.15)`.
///   - `Jaqsı` (3): normal growth `max(hardInterval + 1, round(prevInterval * ease))`,
///     `ease` unchanged.
///   - `Ańsat` (4): bonus growth `max(goodInterval + 2, round(prevInterval * ease * 1.3))`,
///     `ease = ease + 0.15`.
///
/// Guarantees monotonic intervals (`Qayta < Qıyın <= Jaqsı < Ańsat`) for any
/// prior state and always persists UTC timestamps.
class SpacedRepetitionScheduler {
  const SpacedRepetitionScheduler();

  ScheduleResult schedule({
    required ReviewRating rating,
    required DateTime reviewedAt,
    ReviewEntry? previous,
  }) {
    final nowUtc = reviewedAt.toUtc();
    final prevEase = previous?.easeFactor ?? kInitialEaseFactor;
    final prevInterval = previous?.intervalDays ?? 0;

    final hardInterval = prevInterval <= 0
        ? 1
        : math.max(1, (prevInterval * 1.2).round());
    final goodInterval = prevInterval <= 0
        ? 1
        : (prevInterval == 1
            ? 3
            : math.max(hardInterval + 1, (prevInterval * prevEase).round()));
    final easyInterval = prevInterval <= 0
        ? 5
        : math.max(
            goodInterval + 2,
            (prevInterval * prevEase * 1.3).round(),
          );

    switch (rating) {
      case ReviewRating.again:
        final ease = _roundEase(math.max(kMinEaseFactor, prevEase - 0.20));
        return ScheduleResult(
          dueAt: nowUtc.add(kAgainRetryDelay),
          intervalDays: 0,
          easeFactor: ease,
        );
      case ReviewRating.hard:
        final ease = _roundEase(math.max(kMinEaseFactor, prevEase - 0.15));
        return ScheduleResult(
          dueAt: nowUtc.add(Duration(days: hardInterval)),
          intervalDays: hardInterval,
          easeFactor: ease,
        );
      case ReviewRating.good:
        final ease = _roundEase(math.max(kMinEaseFactor, prevEase));
        return ScheduleResult(
          dueAt: nowUtc.add(Duration(days: goodInterval)),
          intervalDays: goodInterval,
          easeFactor: ease,
        );
      case ReviewRating.easy:
        final ease = _roundEase(math.max(kMinEaseFactor, prevEase + 0.15));
        return ScheduleResult(
          dueAt: nowUtc.add(Duration(days: easyInterval)),
          intervalDays: easyInterval,
          easeFactor: ease,
        );
    }
  }

  /// Counts how many distinct study sessions in a row (at the tail of
  /// [chronologicalHistory]) received an uninterrupted `Ańsat`
  /// (`ReviewRating.easy`) rating.
  ///
  /// - If [since] is provided (e.g. when a mastered card was manually
  ///   reactivated to `learning`), only reviews at or after [since] are
  ///   considered so historical reviews are preserved without re-triggering
  ///   immediate mastery.
  /// - Any rating other than `ReviewRating.easy` resets the streak to 0.
  /// - Multiple `Ańsat` reviews within the same `sessionId` count at most once.
  int countConsecutiveEasySessions(
    Iterable<ReviewEntry> chronologicalHistory, {
    DateTime? since,
  }) {
    final sinceUtc = since?.toUtc();
    final qualifyingSessions = <String>{};
    for (final entry in chronologicalHistory) {
      if (sinceUtc != null && entry.reviewedAt.toUtc().isBefore(sinceUtc)) {
        continue;
      }
      if (entry.rating != ReviewRating.easy) {
        qualifyingSessions.clear();
        continue;
      }
      final sessionKey = (entry.sessionId != null &&
              entry.sessionId!.trim().isNotEmpty)
          ? entry.sessionId!.trim()
          : entry.id;
      qualifyingSessions.add(sessionKey);
    }
    return qualifyingSessions.length;
  }

  static double _roundEase(double value) =>
      (value * 100).roundToDouble() / 100;
}
