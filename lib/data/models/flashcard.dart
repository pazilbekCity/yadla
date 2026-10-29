import 'catalog_models.dart';

/// Which side(s) of the card show the optional image.
enum ImagePlacement {
  front,
  back,
  both;

  static ImagePlacement parse(String value) => ImagePlacement.values
      .firstWhere((p) => p.name == value,
          orElse: () => throw FormatException('Unknown image placement: $value'));
}

/// Logical study state of a flashcard.
enum CardStatus {
  /// Active in normal study sessions and spaced-repetition scheduling.
  learning,

  /// Memorized (either manually via «Yad boldı» or after 4 consecutive
  /// distinct sessions rated `Ańsat`). Excluded from normal study until
  /// reactivated.
  mastered,

  /// Temporarily excluded from study until reactivated.
  suspended;

  static CardStatus parse(String value) => CardStatus.values.firstWhere(
        (s) => s.name == value,
        orElse: () => throw FormatException('Unknown card status: $value'),
      );
}

class Flashcard {
  const Flashcard({
    required this.id,
    required this.deckId,
    required this.targetText,
    this.associationText,
    this.definitionText,
    this.imagePath,
    this.imagePlacement = ImagePlacement.front,
    this.status = CardStatus.learning,
    this.statusChangedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String deckId;

  /// The word or concept to memorize.
  final String targetText;

  /// Mnemonic / association text.
  final String? associationText;

  /// Definition or explanation.
  final String? definitionText;

  /// Optional image reference (a path or file name; import workflow comes later).
  final String? imagePath;
  final ImagePlacement imagePlacement;
  final CardStatus status;
  final DateTime? statusChangedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory Flashcard.fromMap(Map<String, Object?> m) => Flashcard(
        id: m['id'] as String,
        deckId: m['deck_id'] as String,
        targetText: m['target_text'] as String,
        associationText: m['association_text'] as String?,
        definitionText: m['definition_text'] as String?,
        imagePath: m['image_path'] as String?,
        imagePlacement: ImagePlacement.parse(m['image_placement'] as String),
        status: m['status'] == null
            ? CardStatus.learning
            : CardStatus.parse(m['status'] as String),
        statusChangedAt: m['status_changed_at'] == null
            ? null
            : dateFromMs(m['status_changed_at'] as int),
        createdAt: dateFromMs(m['created_at'] as int),
        updatedAt: dateFromMs(m['updated_at'] as int),
      );

  /// Nullable fields can be cleared by passing the matching `clear*` flag.
  Flashcard copyWith({
    String? deckId,
    String? targetText,
    String? associationText,
    bool clearAssociation = false,
    String? definitionText,
    bool clearDefinition = false,
    String? imagePath,
    bool clearImage = false,
    ImagePlacement? imagePlacement,
    CardStatus? status,
    DateTime? statusChangedAt,
  }) =>
      Flashcard(
        id: id,
        deckId: deckId ?? this.deckId,
        targetText: targetText ?? this.targetText,
        associationText:
            clearAssociation ? null : (associationText ?? this.associationText),
        definitionText:
            clearDefinition ? null : (definitionText ?? this.definitionText),
        imagePath: clearImage ? null : (imagePath ?? this.imagePath),
        imagePlacement: imagePlacement ?? this.imagePlacement,
        status: status ?? this.status,
        statusChangedAt: statusChangedAt ?? this.statusChangedAt,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );
}
