import '../database/app_database_exception.dart';
import '../database/ids.dart';
import '../models/catalog_models.dart';
import 'repository_base.dart';

class BookRepository extends RepositoryBase {
  BookRepository(super.db, super.clock);

  Future<Book> create({
    required String subjectId,
    required String name,
    String? description,
  }) =>
      guardDb('Create book', () async {
        final now = nowMs();
        final id = generateId();
        await db.insert('books', {
          'id': id,
          'subject_id': subjectId,
          'name': requireText(name, 'Book name'),
          'description': optionalText(description),
          'created_at': now,
          'updated_at': now,
        });
        return (await getById(id))!;
      });

  Future<Book?> getById(String id) => guardDb('Get book', () async {
        final rows = await db.query('books', where: 'id = ?', whereArgs: [id]);
        return rows.isEmpty ? null : Book.fromMap(rows.first);
      });

  Future<List<Book>> listBySubject(String subjectId) =>
      guardDb('List books', () async {
        final rows = await db.query('books',
            where: 'subject_id = ?',
            whereArgs: [subjectId],
            orderBy: 'name COLLATE NOCASE, id');
        return rows.map(Book.fromMap).toList();
      });

  Future<Book> update(Book b) => guardDb('Update book', () async {
        final n = await db.update(
          'books',
          {
            'subject_id': b.subjectId,
            'name': requireText(b.name, 'Book name'),
            'description': optionalText(b.description),
            'updated_at': nowMs(),
          },
          where: 'id = ?',
          whereArgs: [b.id],
        );
        if (n == 0) throw notFound('Book', b.id);
        return (await getById(b.id))!;
      });

  /// See [SubjectRepository.delete] for [cascade] semantics.
  Future<void> delete(String id, {bool cascade = false}) => guardDb(
        'Delete book',
        () => db.transaction((txn) async {
          if (cascade) {
            await txn.execute('''
DELETE FROM flashcards WHERE deck_id IN (
  SELECT d.id FROM decks d JOIN topics t ON d.topic_id = t.id
  WHERE t.book_id = ?)''', [id]);
            await txn.execute('''
DELETE FROM decks WHERE topic_id IN (
  SELECT id FROM topics WHERE book_id = ?)''', [id]);
            await txn.delete('topics', where: 'book_id = ?', whereArgs: [id]);
          }
          final n = await txn.delete('books', where: 'id = ?', whereArgs: [id]);
          if (n == 0) throw notFound('Book', id);
        }),
        foreignKeyKind: DbErrorKind.hasDependents,
      );
}
