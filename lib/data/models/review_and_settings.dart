import 'catalog_models.dart';

/// Recall rating, mirroring Anki's four buttons.
enum ReviewRating {
  again(1),
  hard(2),
  good(3),
  easy(4);

  const ReviewRating(this.value);
  final int value;

  static ReviewRating fromValue(int value) => ReviewRating.values.firstWhere(
      (r) => r.value == value,
      orElse: () => throw FormatException('Unknown rating: $value'));
}

/// One recorded review of a flashcard.
class ReviewEntry {
  const ReviewEntry({
    required this.id,
    required this.flashcardId,
    required this.reviewedAt,
    required this.rating,
    this.dueAt,
    this.intervalDays,
    this.easeFactor,
    this.responseTimeMs,
    this.sessionId,
  });

  final String id;
  final String flashcardId;
  final DateTime reviewedAt;
  final ReviewRating rating;
  final DateTime? dueAt;
  final int? intervalDays;
  final double? easeFactor;
  final int? responseTimeMs;
  final String? sessionId;

  factory ReviewEntry.fromMap(Map<String, Object?> m) => ReviewEntry(
        id: m['id'] as String,
        flashcardId: m['flashcard_id'] as String,
        reviewedAt: dateFromMs(m['reviewed_at'] as int),
        rating: ReviewRating.fromValue(m['rating'] as int),
        dueAt: m['due_at'] == null ? null : dateFromMs(m['due_at'] as int),
        intervalDays: m['interval_days'] as int?,
        easeFactor: (m['ease_factor'] as num?)?.toDouble(),
        responseTimeMs: m['response_time_ms'] as int?,
        sessionId: m['session_id'] as String?,
      );
}

/// A key/value application setting (e.g. `interface_language`).
class AppSetting {
  const AppSetting({
    required this.key,
    required this.value,
    required this.updatedAt,
  });

  final String key;
  final String value;
  final DateTime updatedAt;

  factory AppSetting.fromMap(Map<String, Object?> m) => AppSetting(
        key: m['key'] as String,
        value: m['value'] as String,
        updatedAt: dateFromMs(m['updated_at'] as int),
      );
}
