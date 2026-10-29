/// Shared helpers for epoch-millisecond UTC timestamps.
DateTime dateFromMs(int ms) =>
    DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);

int msFromDate(DateTime d) => d.toUtc().millisecondsSinceEpoch;

/// Top level of the hierarchy (e.g. "Informatics").
class Subject {
  const Subject({
    required this.id,
    required this.name,
    this.description,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String? description;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory Subject.fromMap(Map<String, Object?> m) => Subject(
        id: m['id'] as String,
        name: m['name'] as String,
        description: m['description'] as String?,
        createdAt: dateFromMs(m['created_at'] as int),
        updatedAt: dateFromMs(m['updated_at'] as int),
      );

  Subject copyWith({String? name, String? description}) => Subject(
        id: id,
        name: name ?? this.name,
        description: description ?? this.description,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );
}

/// A book belonging to a [Subject] (e.g. "Informatics Grade 8").
class Book {
  const Book({
    required this.id,
    required this.subjectId,
    required this.name,
    this.description,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String subjectId;
  final String name;
  final String? description;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory Book.fromMap(Map<String, Object?> m) => Book(
        id: m['id'] as String,
        subjectId: m['subject_id'] as String,
        name: m['name'] as String,
        description: m['description'] as String?,
        createdAt: dateFromMs(m['created_at'] as int),
        updatedAt: dateFromMs(m['updated_at'] as int),
      );

  Book copyWith({String? subjectId, String? name, String? description}) => Book(
        id: id,
        subjectId: subjectId ?? this.subjectId,
        name: name ?? this.name,
        description: description ?? this.description,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );
}

/// A topic belonging to a [Book] (e.g. "Microsoft Word").
class Topic {
  const Topic({
    required this.id,
    required this.bookId,
    required this.name,
    this.description,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String bookId;
  final String name;
  final String? description;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory Topic.fromMap(Map<String, Object?> m) => Topic(
        id: m['id'] as String,
        bookId: m['book_id'] as String,
        name: m['name'] as String,
        description: m['description'] as String?,
        createdAt: dateFromMs(m['created_at'] as int),
        updatedAt: dateFromMs(m['updated_at'] as int),
      );

  Topic copyWith({String? bookId, String? name, String? description}) => Topic(
        id: id,
        bookId: bookId ?? this.bookId,
        name: name ?? this.name,
        description: description ?? this.description,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );
}

/// A deck of flashcards belonging to a [Topic] (e.g. "Word vocabulary").
class Deck {
  const Deck({
    required this.id,
    required this.topicId,
    required this.name,
    this.description,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String topicId;
  final String name;
  final String? description;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory Deck.fromMap(Map<String, Object?> m) => Deck(
        id: m['id'] as String,
        topicId: m['topic_id'] as String,
        name: m['name'] as String,
        description: m['description'] as String?,
        createdAt: dateFromMs(m['created_at'] as int),
        updatedAt: dateFromMs(m['updated_at'] as int),
      );

  Deck copyWith({String? topicId, String? name, String? description}) => Deck(
        id: id,
        topicId: topicId ?? this.topicId,
        name: name ?? this.name,
        description: description ?? this.description,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );
}
