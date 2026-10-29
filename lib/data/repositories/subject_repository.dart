import '../database/app_database_exception.dart';
import '../database/ids.dart';
import '../models/catalog_models.dart';
import 'repository_base.dart';

class SubjectRepository extends RepositoryBase {
  SubjectRepository(super.db, super.clock);

  Future<Subject> create({required String name, String? description}) =>
      guardDb('Create subject', () async {
        final now = nowMs();
        final id = generateId();
        await db.insert('subjects', {
          'id': id,
          'name': requireText(name, 'Subject name'),
          'description': optionalText(description),
          'created_at': now,
          'updated_at': now,
        });
        return (await getById(id))!;
      });

  Future<Subject?> getById(String id) => guardDb('Get subject', () async {
        final rows = await db.query('subjects', where: 'id = ?', whereArgs: [id]);
        return rows.isEmpty ? null : Subject.fromMap(rows.first);
      });

  Future<List<Subject>> getAll() => guardDb('List subjects', () async {
        final rows = await db.query('subjects', orderBy: 'name COLLATE NOCASE, id');
        return rows.map(Subject.fromMap).toList();
      });

  Future<Subject> update(Subject s) => guardDb('Update subject', () async {
        final n = await db.update(
          'subjects',
          {
            'name': requireText(s.name, 'Subject name'),
            'description': optionalText(s.description),
            'updated_at': nowMs(),
          },
          where: 'id = ?',
          whereArgs: [s.id],
        );
        if (n == 0) throw notFound('Subject', s.id);
        return (await getById(s.id))!;
      });

  /// Deletes a subject. Without [cascade], fails with
  /// [DbErrorKind.hasDependents] if it still has books. With [cascade], the
  /// whole subtree (books, topics, decks, flashcards, review history) is
  /// removed in a single transaction.
  Future<void> delete(String id, {bool cascade = false}) => guardDb(
        'Delete subject',
        () => db.transaction((txn) async {
          if (cascade) {
            await txn.execute('''
DELETE FROM flashcards WHERE deck_id IN (
  SELECT d.id FROM decks d
  JOIN topics t ON d.topic_id = t.id
  JOIN books b ON t.book_id = b.id WHERE b.subject_id = ?)''', [id]);
            await txn.execute('''
DELETE FROM decks WHERE topic_id IN (
  SELECT t.id FROM topics t JOIN books b ON t.book_id = b.id
  WHERE b.subject_id = ?)''', [id]);
            await txn.execute('''
DELETE FROM topics WHERE book_id IN (
  SELECT id FROM books WHERE subject_id = ?)''', [id]);
            await txn.delete('books', where: 'subject_id = ?', whereArgs: [id]);
          }
          final n = await txn.delete('subjects', where: 'id = ?', whereArgs: [id]);
          if (n == 0) throw notFound('Subject', id);
        }),
        foreignKeyKind: DbErrorKind.hasDependents,
      );
}
