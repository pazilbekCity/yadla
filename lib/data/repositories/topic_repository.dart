import '../database/app_database_exception.dart';
import '../database/ids.dart';
import '../models/catalog_models.dart';
import 'repository_base.dart';

class TopicRepository extends RepositoryBase {
  TopicRepository(super.db, super.clock);

  Future<Topic> create({
    required String bookId,
    required String name,
    String? description,
  }) =>
      guardDb('Create topic', () async {
        final now = nowMs();
        final id = generateId();
        await db.insert('topics', {
          'id': id,
          'book_id': bookId,
          'name': requireText(name, 'Topic name'),
          'description': optionalText(description),
          'created_at': now,
          'updated_at': now,
        });
        return (await getById(id))!;
      });

  Future<Topic?> getById(String id) => guardDb('Get topic', () async {
        final rows = await db.query('topics', where: 'id = ?', whereArgs: [id]);
        return rows.isEmpty ? null : Topic.fromMap(rows.first);
      });

  Future<List<Topic>> listByBook(String bookId) =>
      guardDb('List topics', () async {
        final rows = await db.query('topics',
            where: 'book_id = ?',
            whereArgs: [bookId],
            orderBy: 'name COLLATE NOCASE, id');
        return rows.map(Topic.fromMap).toList();
      });

  Future<Topic> update(Topic t) => guardDb('Update topic', () async {
        final n = await db.update(
          'topics',
          {
            'book_id': t.bookId,
            'name': requireText(t.name, 'Topic name'),
            'description': optionalText(t.description),
            'updated_at': nowMs(),
          },
          where: 'id = ?',
          whereArgs: [t.id],
        );
        if (n == 0) throw notFound('Topic', t.id);
        return (await getById(t.id))!;
      });

  /// See [SubjectRepository.delete] for [cascade] semantics.
  Future<void> delete(String id, {bool cascade = false}) => guardDb(
        'Delete topic',
        () => db.transaction((txn) async {
          if (cascade) {
            await txn.execute('''
DELETE FROM flashcards WHERE deck_id IN (
  SELECT id FROM decks WHERE topic_id = ?)''', [id]);
            await txn.delete('decks', where: 'topic_id = ?', whereArgs: [id]);
          }
          final n = await txn.delete('topics', where: 'id = ?', whereArgs: [id]);
          if (n == 0) throw notFound('Topic', id);
        }),
        foreignKeyKind: DbErrorKind.hasDependents,
      );
}
