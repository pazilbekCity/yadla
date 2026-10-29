import '../database/app_database_exception.dart';
import '../database/ids.dart';
import '../models/catalog_models.dart';
import '../models/flashcard.dart';
import '../services/excel_import_service.dart';
import 'repository_base.dart';

/// A flashcard paired withwhether it is currently due for review (`true` for
/// brand-new cards and cards whose latest `due_at <= asOf`).
class PrioritizedFlashcard {
  const PrioritizedFlashcard({
    required this.card,
    required this.isDue,
    this.nextDueAt,
    this.lastIntervalDays,
  });

  final Flashcard card;
  final bool isDue;
  final DateTime? nextDueAt;
  final int? lastIntervalDays;
}

class FlashcardRepository extends RepositoryBase {
  FlashcardRepository(super.db, super.clock);

  Future<Flashcard> create({
    required String deckId,
    required String targetText,
    String? associationText,
    String? definitionText,
    String? imagePath,
    ImagePlacement imagePlacement = ImagePlacement.front,
    CardStatus status = CardStatus.learning,
  }) =>
      guardDb('Create flashcard', () async {
        final now = nowMs();
        final id = generateId();
        await db.insert('flashcards', {
          'id': id,
          'deck_id': deckId,
          'target_text': requireText(targetText, 'Target text'),
          'association_text': optionalText(associationText),
          'definition_text': optionalText(definitionText),
          'image_path': optionalText(imagePath),
          'image_placement': imagePlacement.name,
          'status': status.name,
          'status_changed_at': null,
          'created_at': now,
          'updated_at': now,
        });
        return (await getById(id))!;
      });

  Future<Flashcard?> getById(String id) => guardDb('Get flashcard', () async {
        final rows =
            await db.query('flashcards', where: 'id = ?', whereArgs: [id]);
        return rows.isEmpty ? null : Flashcard.fromMap(rows.first);
      });

  Future<List<Flashcard>> listByDeck(String deckId) =>
      guardDb('List flashcards', () async {
        final rows = await db.query('flashcards',
            where: 'deck_id = ?',
            whereArgs: [deckId],
            orderBy: 'created_at, id');
        return rows.map(Flashcard.fromMap).toList();
      });

  /// Lists all flashcards across every book, topic, and deck belonging to
  /// [subjectId]. Never returns cards from other subjects.
  Future<List<Flashcard>> listBySubject(String subjectId) =>
      guardDb('List flashcards by subject', () async {
        final rows = await db.rawQuery('''
SELECT f.* FROM flashcards f
JOIN decks d ON f.deck_id = d.id
JOIN topics t ON d.topic_id = t.id
JOIN books b ON t.book_id = b.id
WHERE b.subject_id = ?
ORDER BY f.created_at, f.id
''', [subjectId]);
        return rows.map(Flashcard.fromMap).toList();
      });

  /// Lists eligible (`status = 'learning'`) flashcards in [deckId] for a study
  /// session, annotated with due status as of [asOf] (defaults to [clock]).
  /// Mastered and suspended cards are excluded. If [onlyDue] is true, only
  /// brand-new cards and cards with `due_at <= asOf` are returned.
  Future<List<PrioritizedFlashcard>> listEligibleByDeck(
    String deckId, {
    DateTime? asOf,
    bool onlyDue = false,
  }) =>
      guardDb('List eligible flashcards by deck', () async {
        final cutoff = asOf == null ? nowMs() : msFromDate(asOf);
        final rows = await db.rawQuery('''
SELECT
  f.*,
  latest.due_at AS last_due_at,
  latest.interval_days AS last_interval_days
FROM flashcards f
LEFT JOIN (
  SELECT r.flashcard_id, r.due_at, r.interval_days
  FROM review_history r
  WHERE r.rowid = (
    SELECT r2.rowid FROM review_history r2
    WHERE r2.flashcard_id = r.flashcard_id
    ORDER BY r2.reviewed_at DESC, r2.rowid DESC
    LIMIT 1
  )
) latest ON latest.flashcard_id = f.id
WHERE f.deck_id = ?
  AND f.status = 'learning'
  AND (? = 0 OR latest.due_at IS NULL OR latest.due_at <= ?)
ORDER BY
  CASE WHEN latest.due_at IS NULL OR latest.due_at <= ? THEN 0 ELSE 1 END,
  COALESCE(latest.due_at, 0),
  f.created_at,
  f.id
''', [deckId, onlyDue ? 1 : 0, cutoff, cutoff]);
        return rows.map((r) => _mapPrioritized(r, cutoff)).toList();
      });

  /// Lists eligible (`status = 'learning'`) flashcards across all decks in
  /// [subjectId], annotated with due status as of [asOf]. Never includes cards
  /// from other subjects or cards that are `mastered` / `suspended`.
  Future<List<PrioritizedFlashcard>> listEligibleBySubject(
    String subjectId, {
    DateTime? asOf,
    bool onlyDue = false,
  }) =>
      guardDb('List eligible flashcards by subject', () async {
        final cutoff = asOf == null ? nowMs() : msFromDate(asOf);
        final rows = await db.rawQuery('''
SELECT
  f.*,
  latest.due_at AS last_due_at,
  latest.interval_days AS last_interval_days
FROM flashcards f
JOIN decks d ON f.deck_id = d.id
JOIN topics t ON d.topic_id = t.id
JOIN books b ON t.book_id = b.id
LEFT JOIN (
  SELECT r.flashcard_id, r.due_at, r.interval_days
  FROM review_history r
  WHERE r.rowid = (
    SELECT r2.rowid FROM review_history r2
    WHERE r2.flashcard_id = r.flashcard_id
    ORDER BY r2.reviewed_at DESC, r2.rowid DESC
    LIMIT 1
  )
) latest ON latest.flashcard_id = f.id
WHERE b.subject_id = ?
  AND f.status = 'learning'
  AND (? = 0 OR latest.due_at IS NULL OR latest.due_at <= ?)
ORDER BY
  CASE WHEN latest.due_at IS NULL OR latest.due_at <= ? THEN 0 ELSE 1 END,
  COALESCE(latest.due_at, 0),
  f.created_at,
  f.id
''', [subjectId, onlyDue ? 1 : 0, cutoff, cutoff]);
        return rows.map((r) => _mapPrioritized(r, cutoff)).toList();
      });

  static PrioritizedFlashcard _mapPrioritized(
    Map<String, Object?> row,
    int cutoffMs,
  ) {
    final card = Flashcard.fromMap(row);
    final dueMs = row['last_due_at'] as int?;
    final intervalDays = row['last_interval_days'] as int?;
    final isDue = dueMs == null || dueMs <= cutoffMs;
    return PrioritizedFlashcard(
      card: card,
      isDue: isDue,
      nextDueAt: dueMs == null ? null : dateFromMs(dueMs),
      lastIntervalDays: intervalDays,
    );
  }

  /// Updates a card's study [status] (`learning`, `mastered`, `suspended`)
  /// while preserving all of its review history. Recording `status_changed_at`
  /// ensures that reactivating a mastered card starts a fresh 4-session streak
  /// without deleting past reviews.
  Future<Flashcard> setStatus(String id, CardStatus status) =>
      guardDb('Set flashcard status', () async {
        final now = nowMs();
        final n = await db.update(
          'flashcards',
          {
            'status': status.name,
            'status_changed_at': now,
            'updated_at': now,
          },
          where: 'id = ?',
          whereArgs: [id],
        );
        if (n == 0) throw notFound('Flashcard', id);
        return (await getById(id))!;
      });

  /// Writes all editable fields and refreshes `updated_at`; `created_at`
  /// is never changed.
  Future<Flashcard> update(Flashcard c) => guardDb('Update flashcard', () async {
        final n = await db.update(
          'flashcards',
          {
            'deck_id': c.deckId,
            'target_text': requireText(c.targetText, 'Target text'),
            'association_text': optionalText(c.associationText),
            'definition_text': optionalText(c.definitionText),
            'image_path': optionalText(imagePathOf(c)),
            'image_placement': c.imagePlacement.name,
            'status': c.status.name,
            'updated_at': nowMs(),
          },
          where: 'id = ?',
          whereArgs: [c.id],
        );
        if (n == 0) throw notFound('Flashcard', c.id);
        return (await getById(c.id))!;
      });

  static String? imagePathOf(Flashcard c) => c.imagePath;

  /// Deletes the flashcard; its review history is removed by the database
  /// (ON DELETE CASCADE) in the same statement.
  Future<void> delete(String id) => guardDb('Delete flashcard', () async {
        final n = await db.delete('flashcards', where: 'id = ?', whereArgs: [id]);
        if (n == 0) throw notFound('Flashcard', id);
      });

  /// Inserts validated [rows] into [deckId] inside a single transaction while
  /// skipping any row that duplicates another row in the same batch or an
  /// existing card in [deckId]. Existing cards and their review history are
  /// never modified.
  Future<ExcelImportCommitResult> importBatch({
    required String deckId,
    required List<FlashcardImportRow> rows,
    int preSkippedCount = 0,
  }) =>
      guardDb('Import flashcards', () async {
        return db.transaction((txn) async {
          final deckRows = await txn.query(
            'decks',
            columns: ['id'],
            where: 'id = ?',
            whereArgs: [deckId],
          );
          if (deckRows.isEmpty) {
            throw AppDatabaseException(
              DbErrorKind.invalidReference,
              'Import flashcards: referenced parent record does not exist.',
            );
          }

          final existingRows = await txn.query(
            'flashcards',
            columns: ['target_text', 'definition_text'],
            where: 'deck_id = ?',
            whereArgs: [deckId],
          );
          final seenKeys = <String>{
            for (final r in existingRows)
              '${(r['target_text'] as String).trim().toLowerCase()}\u0000${((r['definition_text'] as String?) ?? '').trim().toLowerCase()}',
          };

          var imported = 0;
          var skipped = preSkippedCount;
          final baseNow = nowMs();

          for (var i = 0; i < rows.length; i++) {
            final row = rows[i];
            final target = requireText(row.targetText, 'Target text');
            final def = requireText(row.definitionText, 'Definition text');
            final key =
                '${target.toLowerCase()}\u0000${def.toLowerCase()}';
            if (!seenKeys.add(key)) {
              skipped++;
              continue;
            }

            final ts = baseNow + i;
            await txn.insert('flashcards', {
              'id': generateId(),
              'deck_id': deckId,
              'target_text': target,
              'association_text': optionalText(row.associationText),
              'definition_text': def,
              'image_path': optionalText(row.imageFilename),
              'image_placement': ImagePlacement.front.name,
              'status': CardStatus.learning.name,
              'status_changed_at': null,
              'created_at': ts,
              'updated_at': ts,
            });
            imported++;
          }

          return ExcelImportCommitResult(
            importedCount: imported,
            skippedCount: skipped,
          );
        });
      });
}
