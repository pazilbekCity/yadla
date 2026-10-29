import 'package:sqflite/sqflite.dart' show ConflictAlgorithm;

import '../database/app_database_exception.dart';
import '../database/migrations.dart';
import 'repository_base.dart';

/// How a validated backup should be applied when restoring into the database.
enum RestoreMode {
  /// Preserves all existing records and imports non-conflicting records from
  /// the backup (mapping matching parent names so child items merge cleanly).
  mergeKeepExisting,

  /// Replaces all existing records with the backup inside a single atomic
  /// database transaction.
  replaceAll,
}

/// Raw database snapshot across all tables.
class RawDatabaseSnapshot {
  const RawDatabaseSnapshot({
    required this.schemaVersion,
    required this.exportedAtMs,
    required this.subjects,
    required this.books,
    required this.topics,
    required this.decks,
    required this.flashcards,
    required this.reviewHistory,
    required this.appSettings,
  });

  final int schemaVersion;
  final int exportedAtMs;
  final List<Map<String, Object?>> subjects;
  final List<Map<String, Object?>> books;
  final List<Map<String, Object?>> topics;
  final List<Map<String, Object?>> decks;
  final List<Map<String, Object?>> flashcards;
  final List<Map<String, Object?>> reviewHistory;
  final List<Map<String, Object?>> appSettings;
}

/// Summary of records written during a restore transaction.
class RestoreCommitSummary {
  const RestoreCommitSummary({
    required this.subjectsRestored,
    required this.booksRestored,
    required this.topicsRestored,
    required this.decksRestored,
    required this.flashcardsRestored,
    required this.reviewsRestored,
    required this.settingsRestored,
    required this.imagesRestored,
  });

  final int subjectsRestored;
  final int booksRestored;
  final int topicsRestored;
  final int decksRestored;
  final int flashcardsRestored;
  final int reviewsRestored;
  final int settingsRestored;
  final int imagesRestored;
}

/// Repository handling consistent full-database export and transactional
/// restore operations.
class BackupRepository extends RepositoryBase {
  BackupRepository(super.db, super.clock);

  /// Returns `true` if the database currently contains any subjects, books,
  /// topics, decks, flashcards, or review history records.
  Future<bool> hasExistingUserData() =>
      guardDb('Check existing user data', () async {
        final subj = await db.query('subjects', columns: ['id'], limit: 1);
        if (subj.isNotEmpty) return true;
        final cards = await db.query('flashcards', columns: ['id'], limit: 1);
        if (cards.isNotEmpty) return true;
        final reviews =
            await db.query('review_history', columns: ['id'], limit: 1);
        return reviews.isNotEmpty;
      });

  /// Exports a consistent snapshot of all tables inside a single database
  /// transaction.
  Future<RawDatabaseSnapshot> exportRawSnapshot() =>
      guardDb('Export database snapshot', () async {
        return db.transaction((txn) async {
          final subjects = await txn.query(
            'subjects',
            orderBy: 'created_at ASC, id ASC',
          );
          final books = await txn.query(
            'books',
            orderBy: 'created_at ASC, id ASC',
          );
          final topics = await txn.query(
            'topics',
            orderBy: 'created_at ASC, id ASC',
          );
          final decks = await txn.query(
            'decks',
            orderBy: 'created_at ASC, id ASC',
          );
          final flashcards = await txn.query(
            'flashcards',
            orderBy: 'created_at ASC, id ASC',
          );
          final reviewHistory = await txn.query(
            'review_history',
            orderBy: 'reviewed_at ASC, rowid ASC',
          );
          final appSettings = await txn.query(
            'app_settings',
            orderBy: 'key ASC',
          );

          return RawDatabaseSnapshot(
            schemaVersion: allMigrations.last.version,
            exportedAtMs: nowMs(),
            subjects: subjects.map((r) => Map<String, Object?>.of(r)).toList(),
            books: books.map((r) => Map<String, Object?>.of(r)).toList(),
            topics: topics.map((r) => Map<String, Object?>.of(r)).toList(),
            decks: decks.map((r) => Map<String, Object?>.of(r)).toList(),
            flashcards:
                flashcards.map((r) => Map<String, Object?>.of(r)).toList(),
            reviewHistory:
                reviewHistory.map((r) => Map<String, Object?>.of(r)).toList(),
            appSettings:
                appSettings.map((r) => Map<String, Object?>.of(r)).toList(),
          );
        });
      });

  /// Restores a validated [snapshot] into the database inside a single atomic
  /// transaction. If any write fails, the entire transaction is rolled back
  /// and existing data remains untouched.
  Future<RestoreCommitSummary> restoreRawSnapshot({
    required RawDatabaseSnapshot snapshot,
    required RestoreMode mode,
    required Map<String, String> resolvedCardImagePaths,
    required int imagesRestoredCount,
  }) =>
      guardDb('Restore database snapshot', () async {
        return db.transaction((txn) async {
          var subjectsRestored = 0;
          var booksRestored = 0;
          var topicsRestored = 0;
          var decksRestored = 0;
          var flashcardsRestored = 0;
          var reviewsRestored = 0;
          var settingsRestored = 0;

          if (mode == RestoreMode.replaceAll) {
            // Delete child-to-parent so ON DELETE RESTRICT is respected.
            await txn.delete('review_history');
            await txn.delete('flashcards');
            await txn.delete('decks');
            await txn.delete('topics');
            await txn.delete('books');
            await txn.delete('subjects');
            await txn.delete('app_settings');

            for (final s in snapshot.subjects) {
              await txn.insert('subjects', {
                'id': s['id'],
                'name': s['name'],
                'description': s['description'],
                'created_at': s['created_at'],
                'updated_at': s['updated_at'],
              });
              subjectsRestored++;
            }

            for (final b in snapshot.books) {
              await txn.insert('books', {
                'id': b['id'],
                'subject_id': b['subject_id'],
                'name': b['name'],
                'description': b['description'],
                'created_at': b['created_at'],
                'updated_at': b['updated_at'],
              });
              booksRestored++;
            }

            for (final t in snapshot.topics) {
              await txn.insert('topics', {
                'id': t['id'],
                'book_id': t['book_id'],
                'name': t['name'],
                'description': t['description'],
                'created_at': t['created_at'],
                'updated_at': t['updated_at'],
              });
              topicsRestored++;
            }

            for (final d in snapshot.decks) {
              await txn.insert('decks', {
                'id': d['id'],
                'topic_id': d['topic_id'],
                'name': d['name'],
                'description': d['description'],
                'created_at': d['created_at'],
                'updated_at': d['updated_at'],
              });
              decksRestored++;
            }

            for (final c in snapshot.flashcards) {
              final cardId = c['id'] as String;
              final imagePath = resolvedCardImagePaths.containsKey(cardId)
                  ? resolvedCardImagePaths[cardId]
                  : c['image_path'] as String?;
              await txn.insert('flashcards', {
                'id': cardId,
                'deck_id': c['deck_id'],
                'target_text': c['target_text'],
                'association_text': c['association_text'],
                'definition_text': c['definition_text'],
                'image_path': imagePath,
                'image_placement': c['image_placement'] ?? 'front',
                'status': c['status'] ?? 'learning',
                'status_changed_at': c['status_changed_at'],
                'created_at': c['created_at'],
                'updated_at': c['updated_at'],
              });
              flashcardsRestored++;
            }

            for (final r in snapshot.reviewHistory) {
              await txn.insert('review_history', {
                'id': r['id'],
                'flashcard_id': r['flashcard_id'],
                'reviewed_at': r['reviewed_at'],
                'rating': r['rating'],
                'due_at': r['due_at'],
                'interval_days': r['interval_days'],
                'ease_factor': r['ease_factor'],
                'response_time_ms': r['response_time_ms'],
                'session_id': r['session_id'],
              });
              reviewsRestored++;
            }

            for (final st in snapshot.appSettings) {
              await txn.insert(
                'app_settings',
                {
                  'key': st['key'],
                  'value': st['value'],
                  'updated_at': st['updated_at'],
                },
                conflictAlgorithm: ConflictAlgorithm.replace,
              );
              settingsRestored++;
            }
          } else {
            // RestoreMode.mergeKeepExisting: never overwrite or delete existing data.
            final subjectIdMap = <String, String>{};
            final existingSubjects = await txn.query('subjects');
            final subjById = {
              for (final r in existingSubjects) r['id'] as String: r,
            };
            final subjByName = {
              for (final r in existingSubjects)
                (r['name'] as String).trim(): r['id'] as String,
            };

            for (final s in snapshot.subjects) {
              final oldId = s['id'] as String;
              final name = (s['name'] as String).trim();
              if (subjById.containsKey(oldId)) {
                subjectIdMap[oldId] = oldId;
              } else if (subjByName.containsKey(name)) {
                subjectIdMap[oldId] = subjByName[name]!;
              } else {
                await txn.insert('subjects', {
                  'id': oldId,
                  'name': name,
                  'description': s['description'],
                  'created_at': s['created_at'],
                  'updated_at': s['updated_at'],
                });
                subjectIdMap[oldId] = oldId;
                subjByName[name] = oldId;
                subjectsRestored++;
              }
            }

            final bookIdMap = <String, String>{};
            final existingBooks = await txn.query('books');
            final bookById = {
              for (final r in existingBooks) r['id'] as String: r,
            };
            final bookByParentAndName = {
              for (final r in existingBooks)
                '${r['subject_id']}\u0000${(r['name'] as String).trim()}':
                    r['id'] as String,
            };

            for (final b in snapshot.books) {
              final oldId = b['id'] as String;
              final targetSubjectId =
                  subjectIdMap[b['subject_id'] as String]!;
              final name = (b['name'] as String).trim();
              final compositeKey = '$targetSubjectId\u0000$name';
              if (bookById.containsKey(oldId)) {
                bookIdMap[oldId] = oldId;
              } else if (bookByParentAndName.containsKey(compositeKey)) {
                bookIdMap[oldId] = bookByParentAndName[compositeKey]!;
              } else {
                await txn.insert('books', {
                  'id': oldId,
                  'subject_id': targetSubjectId,
                  'name': name,
                  'description': b['description'],
                  'created_at': b['created_at'],
                  'updated_at': b['updated_at'],
                });
                bookIdMap[oldId] = oldId;
                bookByParentAndName[compositeKey] = oldId;
                booksRestored++;
              }
            }

            final topicIdMap = <String, String>{};
            final existingTopics = await txn.query('topics');
            final topicById = {
              for (final r in existingTopics) r['id'] as String: r,
            };
            final topicByParentAndName = {
              for (final r in existingTopics)
                '${r['book_id']}\u0000${(r['name'] as String).trim()}':
                    r['id'] as String,
            };

            for (final t in snapshot.topics) {
              final oldId = t['id'] as String;
              final targetBookId = bookIdMap[t['book_id'] as String]!;
              final name = (t['name'] as String).trim();
              final compositeKey = '$targetBookId\u0000$name';
              if (topicById.containsKey(oldId)) {
                topicIdMap[oldId] = oldId;
              } else if (topicByParentAndName.containsKey(compositeKey)) {
                topicIdMap[oldId] = topicByParentAndName[compositeKey]!;
              } else {
                await txn.insert('topics', {
                  'id': oldId,
                  'book_id': targetBookId,
                  'name': name,
                  'description': t['description'],
                  'created_at': t['created_at'],
                  'updated_at': t['updated_at'],
                });
                topicIdMap[oldId] = oldId;
                topicByParentAndName[compositeKey] = oldId;
                topicsRestored++;
              }
            }

            final deckIdMap = <String, String>{};
            final existingDecks = await txn.query('decks');
            final deckById = {
              for (final r in existingDecks) r['id'] as String: r,
            };
            final deckByParentAndName = {
              for (final r in existingDecks)
                '${r['topic_id']}\u0000${(r['name'] as String).trim()}':
                    r['id'] as String,
            };

            for (final d in snapshot.decks) {
              final oldId = d['id'] as String;
              final targetTopicId = topicIdMap[d['topic_id'] as String]!;
              final name = (d['name'] as String).trim();
              final compositeKey = '$targetTopicId\u0000$name';
              if (deckById.containsKey(oldId)) {
                deckIdMap[oldId] = oldId;
              } else if (deckByParentAndName.containsKey(compositeKey)) {
                deckIdMap[oldId] = deckByParentAndName[compositeKey]!;
              } else {
                await txn.insert('decks', {
                  'id': oldId,
                  'topic_id': targetTopicId,
                  'name': name,
                  'description': d['description'],
                  'created_at': d['created_at'],
                  'updated_at': d['updated_at'],
                });
                deckIdMap[oldId] = oldId;
                deckByParentAndName[compositeKey] = oldId;
                decksRestored++;
              }
            }

            final existingCards = await txn.query(
              'flashcards',
              columns: ['id'],
            );
            final existingCardIds = {
              for (final r in existingCards) r['id'] as String,
            };

            for (final c in snapshot.flashcards) {
              final cardId = c['id'] as String;
              if (existingCardIds.contains(cardId)) {
                continue;
              }
              final targetDeckId = deckIdMap[c['deck_id'] as String]!;
              final imagePath = resolvedCardImagePaths.containsKey(cardId)
                  ? resolvedCardImagePaths[cardId]
                  : c['image_path'] as String?;
              await txn.insert('flashcards', {
                'id': cardId,
                'deck_id': targetDeckId,
                'target_text': c['target_text'],
                'association_text': c['association_text'],
                'definition_text': c['definition_text'],
                'image_path': imagePath,
                'image_placement': c['image_placement'] ?? 'front',
                'status': c['status'] ?? 'learning',
                'status_changed_at': c['status_changed_at'],
                'created_at': c['created_at'],
                'updated_at': c['updated_at'],
              });
              existingCardIds.add(cardId);
              flashcardsRestored++;
            }

            final existingReviews = await txn.query(
              'review_history',
              columns: ['id'],
            );
            final existingReviewIds = {
              for (final r in existingReviews) r['id'] as String,
            };

            for (final r in snapshot.reviewHistory) {
              final reviewId = r['id'] as String;
              final cardId = r['flashcard_id'] as String;
              if (existingReviewIds.contains(reviewId) ||
                  !existingCardIds.contains(cardId)) {
                continue;
              }
              await txn.insert('review_history', {
                'id': reviewId,
                'flashcard_id': cardId,
                'reviewed_at': r['reviewed_at'],
                'rating': r['rating'],
                'due_at': r['due_at'],
                'interval_days': r['interval_days'],
                'ease_factor': r['ease_factor'],
                'response_time_ms': r['response_time_ms'],
                'session_id': r['session_id'],
              });
              existingReviewIds.add(reviewId);
              reviewsRestored++;
            }

            for (final st in snapshot.appSettings) {
              await txn.insert(
                'app_settings',
                {
                  'key': st['key'],
                  'value': st['value'],
                  'updated_at': st['updated_at'],
                },
                conflictAlgorithm: ConflictAlgorithm.replace,
              );
              settingsRestored++;
            }
          }

          return RestoreCommitSummary(
            subjectsRestored: subjectsRestored,
            booksRestored: booksRestored,
            topicsRestored: topicsRestored,
            decksRestored: decksRestored,
            flashcardsRestored: flashcardsRestored,
            reviewsRestored: reviewsRestored,
            settingsRestored: settingsRestored,
            imagesRestored: imagesRestoredCount,
          );
        });
      });
}
