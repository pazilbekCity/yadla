import '../database/app_database_exception.dart';
import '../database/ids.dart';
import '../models/catalog_models.dart';
import 'repository_base.dart';

class DeckRepository extends RepositoryBase {
  DeckRepository(super.db, super.clock);

  Future<Deck> create({
    required String topicId,
    required String name,
    String? description,
  }) =>
      guardDb('Create deck', () async {
        final now = nowMs();
        final id = generateId();
        await db.insert('decks', {
          'id': id,
          'topic_id': topicId,
          'name': requireText(name, 'Deck name'),
          'description': optionalText(description),
          'created_at': now,
          'updated_at': now,
        });
        return (await getById(id))!;
      });

  Future<Deck?> getById(String id) => guardDb('Get deck', () async {
        final rows = await db.query('decks', where: 'id = ?', whereArgs: [id]);
        return rows.isEmpty ? null : Deck.fromMap(rows.first);
      });

  Future<List<Deck>> listByTopic(String topicId) =>
      guardDb('List decks', () async {
        final rows = await db.query('decks',
            where: 'topic_id = ?',
            whereArgs: [topicId],
            orderBy: 'name COLLATE NOCASE, id');
        return rows.map(Deck.fromMap).toList();
      });

  Future<Deck> update(Deck d) => guardDb('Update deck', () async {
        final n = await db.update(
          'decks',
          {
            'topic_id': d.topicId,
            'name': requireText(d.name, 'Deck name'),
            'description': optionalText(d.description),
            'updated_at': nowMs(),
          },
          where: 'id = ?',
          whereArgs: [d.id],
        );
        if (n == 0) throw notFound('Deck', d.id);
        return (await getById(d.id))!;
      });

  /// Without [cascade], fails with [DbErrorKind.hasDependents] if the deck
  /// still has flashcards. With [cascade], its flashcards (and their review
  /// history) are deleted in the same transaction.
  Future<void> delete(String id, {bool cascade = false}) => guardDb(
        'Delete deck',
        () => db.transaction((txn) async {
          if (cascade) {
            await txn.delete('flashcards', where: 'deck_id = ?', whereArgs: [id]);
          }
          final n = await txn.delete('decks', where: 'id = ?', whereArgs: [id]);
          if (n == 0) throw notFound('Deck', id);
        }),
        foreignKeyKind: DbErrorKind.hasDependents,
      );
}
