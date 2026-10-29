import 'dart:io';

import 'package:anki_apk/data/database/app_database.dart';
import 'package:anki_apk/data/database/app_database_exception.dart';
import 'package:anki_apk/data/database/migrations.dart';
import 'package:anki_apk/data/models/flashcard.dart';
import 'package:anki_apk/data/models/review_and_settings.dart';
import 'package:anki_apk/data/repositories/app_settings_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Matcher dbError(DbErrorKind kind) => isA<AppDatabaseException>()
    .having((e) => e.kind, 'kind', kind);

/// Builds Subject > Book > Topic > Deck > Flashcard and returns the ids.
Future<({String subject, String book, String topic, String deck, String card})>
    seed(AppDatabase db) async {
  final s = await db.subjects.create(name: 'Informatics');
  final b = await db.books.create(subjectId: s.id, name: 'Informatics Grade 8');
  final t = await db.topics.create(bookId: b.id, name: 'Microsoft Word');
  final d = await db.decks.create(topicId: t.id, name: 'Word vocabulary');
  final c = await db.flashcards.create(deckId: d.id, targetText: 'Ribbon');
  return (subject: s.id, book: b.id, topic: t.id, deck: d.id, card: c.id);
}

Future<int> count(AppDatabase db, String table) async =>
    (await db.rawDatabase.rawQuery('SELECT COUNT(*) c FROM $table')).first['c']
        as int;

void main() {
  sqfliteFfiInit();
  final factory = databaseFactoryFfi;

  late AppDatabase db;

  setUp(() async {
    db = await AppDatabase.open(
        path: inMemoryDatabasePath, factory: factory);
  });
  tearDown(() => db.close());

  group('initialization', () {
    test('creates schema at latest version with foreign keys on', () async {
      expect(db.schemaVersion, allMigrations.last.version);
      final fk = await db.rawDatabase.rawQuery('PRAGMA foreign_keys');
      expect(fk.first.values.first, 1);
      final tables = (await db.rawDatabase.rawQuery(
              "SELECT name FROM sqlite_master WHERE type='table'"))
          .map((r) => r['name'])
          .toSet();
      expect(
          tables,
          containsAll([
            'subjects',
            'books',
            'topics',
            'decks',
            'flashcards',
            'review_history',
            'app_settings'
          ]));
    });
  });

  group('CRUD', () {
    test('subject create/get/list/update/delete', () async {
      final s = await db.subjects.create(name: '  Math ', description: 'd');
      expect(s.name, 'Math');
      expect((await db.subjects.getById(s.id))!.description, 'd');
      expect(await db.subjects.getAll(), hasLength(1));
      final u = await db.subjects.update(s.copyWith(name: 'Maths'));
      expect(u.name, 'Maths');
      expect(u.createdAt, s.createdAt);
      await db.subjects.delete(s.id);
      expect(await db.subjects.getById(s.id), isNull);
    });

    test('book/topic/deck CRUD', () async {
      final ids = await seed(db);
      final b = (await db.books.getById(ids.book))!;
      expect((await db.books.update(b.copyWith(name: 'Grade 9'))).name, 'Grade 9');
      final t = (await db.topics.getById(ids.topic))!;
      expect((await db.topics.update(t.copyWith(name: 'Excel'))).name, 'Excel');
      final d = (await db.decks.getById(ids.deck))!;
      expect((await db.decks.update(d.copyWith(name: 'Terms'))).name, 'Terms');
      expect(await db.books.listBySubject(ids.subject), hasLength(1));
      expect(await db.topics.listByBook(ids.book), hasLength(1));
      expect(await db.decks.listByTopic(ids.topic), hasLength(1));
    });

    test('flashcard fields, image placement, timestamps', () async {
      final ids = await seed(db);
      var now = DateTime.utc(2026, 1, 1);
      final clocked = await AppDatabase.open(
          path: inMemoryDatabasePath, factory: factory, clock: () => now);
      addTearDown(clocked.close);
      final s = await clocked.subjects.create(name: 'S');
      final b = await clocked.books.create(subjectId: s.id, name: 'B');
      final t = await clocked.topics.create(bookId: b.id, name: 'T');
      final d = await clocked.decks.create(topicId: t.id, name: 'D');
      final c = await clocked.flashcards.create(
        deckId: d.id,
        targetText: 'Font',
        associationText: 'looks of letters',
        definitionText: 'A typeface',
        imagePath: 'img/font.png',
        imagePlacement: ImagePlacement.both,
      );
      expect(c.imagePlacement, ImagePlacement.both);
      expect(c.createdAt, now);
      now = DateTime.utc(2026, 1, 2);
      final u = await clocked.flashcards.update(
          c.copyWith(imagePlacement: ImagePlacement.back, clearAssociation: true));
      expect(u.imagePlacement, ImagePlacement.back);
      expect(u.associationText, isNull);
      expect(u.createdAt, DateTime.utc(2026, 1, 1));
      expect(u.updatedAt, DateTime.utc(2026, 1, 2));
      expect(ids.card, isNotEmpty);
    });

    test('flashcard delete and not-found errors', () async {
      final ids = await seed(db);
      await db.flashcards.delete(ids.card);
      expect(db.flashcards.delete(ids.card), throwsA(dbError(DbErrorKind.notFound)));
      expect(db.subjects.delete('nope'), throwsA(dbError(DbErrorKind.notFound)));
    });

    test('update of missing record fails explicitly', () async {
      final ids = await seed(db);
      final s = (await db.subjects.getById(ids.subject))!;
      await db.subjects.delete(s.id, cascade: true);
      expect(db.subjects.update(s), throwsA(dbError(DbErrorKind.notFound)));
    });
  });

  group('integrity', () {
    test('blank names rejected; duplicates rejected within parent only', () async {
      expect(db.subjects.create(name: '   '),
          throwsA(dbError(DbErrorKind.validation)));
      final a = await db.subjects.create(name: 'A');
      final b = await db.subjects.create(name: 'B');
      await db.books.create(subjectId: a.id, name: 'Book');
      expect(db.books.create(subjectId: a.id, name: 'Book'),
          throwsA(dbError(DbErrorKind.duplicate)));
      await db.books.create(subjectId: b.id, name: 'Book'); // other parent ok
      expect(db.subjects.create(name: 'A'),
          throwsA(dbError(DbErrorKind.duplicate)));
    });

    test('child with missing parent rejected', () async {
      expect(db.books.create(subjectId: 'ghost', name: 'x'),
          throwsA(dbError(DbErrorKind.invalidReference)));
      expect(db.flashcards.create(deckId: 'ghost', targetText: 'x'),
          throwsA(dbError(DbErrorKind.invalidReference)));
    });

    test('moving a record to a missing parent is rejected, data unchanged',
        () async {
      final ids = await seed(db);
      final d = (await db.decks.getById(ids.deck))!;
      expect(db.decks.update(d.copyWith(topicId: 'ghost')),
          throwsA(dbError(DbErrorKind.invalidReference)));
      expect((await db.decks.getById(ids.deck))!.topicId, ids.topic);
    });

    test('invalid image placement / rating blocked by CHECK constraints',
        () async {
      final ids = await seed(db);
      expect(
          db.rawDatabase.execute(
              "UPDATE flashcards SET image_placement='left' WHERE id=?",
              [ids.card]),
          throwsA(isA<Exception>()));
      expect(
          db.rawDatabase.insert('review_history', {
            'id': 'r',
            'flashcard_id': ids.card,
            'reviewed_at': 1,
            'rating': 9,
          }),
          throwsA(isA<Exception>()));
    });

    test('delete without cascade is refused while children exist', () async {
      final ids = await seed(db);
      for (final f in <Future<void> Function()>[
        () => db.subjects.delete(ids.subject),
        () => db.books.delete(ids.book),
        () => db.topics.delete(ids.topic),
        () => db.decks.delete(ids.deck),
      ]) {
        await expectLater(f(), throwsA(dbError(DbErrorKind.hasDependents)));
      }
      expect(await count(db, 'subjects'), 1);
      expect(await count(db, 'flashcards'), 1);
    });

    test('cascade delete removes whole subtree and review history', () async {
      final ids = await seed(db);
      await db.reviews.add(flashcardId: ids.card, rating: ReviewRating.good);
      await db.subjects.delete(ids.subject, cascade: true);
      for (final t in [
        'subjects', 'books', 'topics', 'decks', 'flashcards', 'review_history'
      ]) {
        expect(await count(db, t), 0, reason: t);
      }
    });

    test('cascade on a lower level leaves siblings and ancestors intact',
        () async {
      final ids = await seed(db);
      final other = await db.topics.create(bookId: ids.book, name: 'Other');
      final od = await db.decks.create(topicId: other.id, name: 'OD');
      await db.flashcards.create(deckId: od.id, targetText: 'keep');
      await db.topics.delete(ids.topic, cascade: true);
      expect(await db.topics.getById(ids.topic), isNull);
      expect(await db.decks.getById(ids.deck), isNull);
      expect(await db.flashcards.getById(ids.card), isNull);
      expect(await db.topics.getById(other.id), isNotNull);
      expect(await db.flashcards.listByDeck(od.id), hasLength(1));
      expect(await db.books.getById(ids.book), isNotNull);
    });

    test('cascade of a missing id rolls back and reports notFound', () async {
      await seed(db);
      await expectLater(db.books.delete('ghost', cascade: true),
          throwsA(dbError(DbErrorKind.notFound)));
      expect(await count(db, 'flashcards'), 1);
    });

    test('flashcard deletion removes its review history', () async {
      final ids = await seed(db);
      await db.reviews.add(
          flashcardId: ids.card,
          rating: ReviewRating.hard,
          dueAt: DateTime.utc(2030),
          intervalDays: 1,
          easeFactor: 2.5);
      await db.reviews.add(flashcardId: ids.card, rating: ReviewRating.easy);
      expect(await db.reviews.listForFlashcard(ids.card), hasLength(2));
      await db.flashcards.delete(ids.card);
      expect(await count(db, 'review_history'), 0);
    });

    test('review for missing flashcard rejected', () async {
      expect(db.reviews.add(flashcardId: 'ghost', rating: ReviewRating.good),
          throwsA(dbError(DbErrorKind.invalidReference)));
    });
  });

  group('settings', () {
    test('set/get/replace/delete and language validation', () async {
      expect(await db.settings.getInterfaceLanguage(), isNull);
      await db.settings.setInterfaceLanguage('kaa');
      expect(await db.settings.getInterfaceLanguage(), 'kaa');
      await db.settings.setInterfaceLanguage('ru');
      expect(await db.settings.getInterfaceLanguage(), 'ru');
      expect(db.settings.setInterfaceLanguage('xx'),
          throwsA(dbError(DbErrorKind.validation)));
      await db.settings.delete(AppSettingsRepository.interfaceLanguageKey);
      expect(await db.settings.getAll(), isEmpty);
      expect(db.settings.delete('missing'),
          throwsA(dbError(DbErrorKind.notFound)));
    });
  });

  group('persistence and migrations (file database)', () {
    late Directory dir;
    late String path;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('anki_apk_test_');
      path = p.join(dir.path, 'test.db');
    });
    tearDown(() => dir.deleteSync(recursive: true));

    test('data survives closing and reopening', () async {
      final first = await AppDatabase.open(path: path, factory: factory);
      final ids = await seed(first);
      await first.settings.setInterfaceLanguage('uz');
      await first.close();

      final second = await AppDatabase.open(path: path, factory: factory);
      addTearDown(second.close);
      expect((await second.subjects.getById(ids.subject))!.name, 'Informatics');
      expect((await second.flashcards.getById(ids.card))!.targetText, 'Ribbon');
      expect(await second.decks.listByTopic(ids.topic), hasLength(1));
      expect(await second.settings.getInterfaceLanguage(), 'uz');
    });

    test('upgrade migration from v1 to v2 keeps existing data and adds status and session_id',
        () async {
      final v1 = await AppDatabase.open(
        path: path,
        factory: factory,
        migrations: [allMigrations.first],
      );
      final s = await v1.subjects.create(name: 'Informatics');
      final b = await v1.books.create(subjectId: s.id, name: 'Informatics Grade 8');
      final t = await v1.topics.create(bookId: b.id, name: 'Microsoft Word');
      final d = await v1.decks.create(topicId: t.id, name: 'Word vocabulary');
      const cardId = 'legacy-card-1';
      await v1.rawDatabase.insert('flashcards', {
        'id': cardId,
        'deck_id': d.id,
        'target_text': 'Ribbon',
        'image_placement': 'front',
        'created_at': 1700000000000,
        'updated_at': 1700000000000,
      });
      await v1.rawDatabase.insert('review_history', {
        'id': 'legacy-review-1',
        'flashcard_id': cardId,
        'reviewed_at': 1700000000000,
        'rating': 3,
      });
      await v1.close();

      final v2 = await AppDatabase.open(
          path: path, factory: factory, migrations: allMigrations);
      addTearDown(v2.close);
      expect(v2.schemaVersion, allMigrations.last.version);
      final card = (await v2.flashcards.getById(cardId))!;
      expect(card.targetText, 'Ribbon');
      expect(card.status.name, 'learning');
      final reviews = await v2.reviews.listForFlashcard(cardId);
      expect(reviews, hasLength(1));
      expect(reviews.single.id, 'legacy-review-1');
    });

    test('upgrade migration keeps existing data and applies new schema',
        () async {
      final vCurrent = await AppDatabase.open(path: path, factory: factory);
      final ids = await seed(vCurrent);
      await vCurrent.close();

      final nextVersion = allMigrations.last.version + 1;
      final migrations = [
        ...allMigrations,
        Migration(nextVersion, ['ALTER TABLE flashcards ADD COLUMN notes TEXT']),
      ];
      final vNext = await AppDatabase.open(
          path: path, factory: factory, migrations: migrations);
      addTearDown(vNext.close);
      expect(vNext.schemaVersion, nextVersion);
      expect((await vNext.flashcards.getById(ids.card))!.targetText, 'Ribbon');
      final cols =
          await vNext.rawDatabase.rawQuery('PRAGMA table_info(flashcards)');
      expect(cols.map((c) => c['name']), contains('notes'));
    });

    test('failed migration rolls back and leaves data untouched', () async {
      final vCurrent = await AppDatabase.open(path: path, factory: factory);
      final ids = await seed(vCurrent);
      await vCurrent.close();

      final nextVersion = allMigrations.last.version + 1;
      final bad = [
        ...allMigrations,
        Migration(nextVersion, [
          'ALTER TABLE flashcards ADD COLUMN ok_col TEXT',
          'THIS IS NOT SQL',
        ]),
      ];
      await expectLater(
          AppDatabase.open(path: path, factory: factory, migrations: bad),
          throwsA(isA<AppDatabaseException>()));

      final again = await AppDatabase.open(path: path, factory: factory);
      addTearDown(again.close);
      expect(again.schemaVersion, allMigrations.last.version);
      expect((await again.flashcards.getById(ids.card))!.targetText, 'Ribbon');
      final cols = await again.rawDatabase.rawQuery('PRAGMA table_info(flashcards)');
      expect(cols.map((c) => c['name']), isNot(contains('ok_col')));
    });

    test('opening a newer database with older code is refused', () async {
      final nextVersion = allMigrations.last.version + 1;
      final bumped = [
        ...allMigrations,
        Migration(nextVersion, ['ALTER TABLE flashcards ADD COLUMN notes TEXT']),
      ];
      final vNext = await AppDatabase.open(
          path: path, factory: factory, migrations: bumped);
      await vNext.close();
      await expectLater(AppDatabase.open(path: path, factory: factory),
          throwsA(dbError(DbErrorKind.downgrade)));
    });
  });
}
