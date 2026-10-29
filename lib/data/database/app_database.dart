import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../repositories/app_settings_repository.dart';
import '../repositories/backup_repository.dart';
import '../repositories/book_repository.dart';
import '../repositories/deck_repository.dart';
import '../repositories/flashcard_repository.dart';
import '../repositories/repository_base.dart';
import '../repositories/review_history_repository.dart';
import '../repositories/subject_repository.dart';
import '../repositories/topic_repository.dart';
import 'app_database_exception.dart';
import 'migrations.dart';

/// Opens the local SQLite database, applies migrations, enforces foreign
/// keys, and exposes the repositories.
class AppDatabase {
  AppDatabase._(this._db, this.schemaVersion, Clock clock)
      : subjects = SubjectRepository(_db, clock),
        books = BookRepository(_db, clock),
        topics = TopicRepository(_db, clock),
        decks = DeckRepository(_db, clock),
        flashcards = FlashcardRepository(_db, clock),
        reviews = ReviewHistoryRepository(_db, clock),
        settings = AppSettingsRepository(_db, clock),
        backups = BackupRepository(_db, clock);

  static const fileName = 'anki_apk.db';

  final Database _db;
  final int schemaVersion;

  final SubjectRepository subjects;
  final BookRepository books;
  final TopicRepository topics;
  final DeckRepository decks;
  final FlashcardRepository flashcards;
  final ReviewHistoryRepository reviews;
  final AppSettingsRepository settings;
  final BackupRepository backups;

  /// Raw handle, intended for tests and diagnostics only.
  Database get rawDatabase => _db;

  /// Opens the database in the platform's default databases directory using
  /// the globally configured sqflite [databaseFactory].
  static Future<AppDatabase> openDefault() async {
    final dir = await getDatabasesPath();
    return open(path: p.join(dir, fileName));
  }

  /// Opens (creating/migrating if needed) the database at [path].
  /// [migrations] and [factory] are overridable for tests.
  static Future<AppDatabase> open({
    required String path,
    DatabaseFactory? factory,
    List<Migration> migrations = allMigrations,
    Clock? clock,
  }) async {
    final targetVersion = migrations.last.version;
    final f = factory ?? databaseFactory;
    try {
      final db = await f.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: targetVersion,
          onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
          onCreate: (db, version) =>
              _migrate(db, migrations, from: 0, to: version),
          onUpgrade: (db, from, to) =>
              _migrate(db, migrations, from: from, to: to),
          onDowngrade: (db, from, to) => throw AppDatabaseException(
            DbErrorKind.downgrade,
            'Database schema v$from is newer than supported v$to. '
            'Update the app instead of opening this data with an older version.',
          ),
          onOpen: _verifyIntegrity,
        ),
      );
      return AppDatabase._(db, targetVersion, clock ?? DateTime.now);
    } on AppDatabaseException {
      rethrow;
    } on DatabaseException catch (e) {
      throw AppDatabaseException(
        DbErrorKind.unknown,
        'Could not open database at "$path": $e',
        cause: e,
      );
    }
  }

  static Future<void> _migrate(
    Database db,
    List<Migration> migrations, {
    required int from,
    required int to,
  }) async {
    // sqflite runs onCreate/onUpgrade inside a transaction, so a failing
    // step rolls the whole migration back and leaves existing data intact.
    for (final m in migrations) {
      if (m.version > from && m.version <= to) {
        for (final sql in m.statements) {
          await db.execute(sql);
        }
      }
    }
  }

  static Future<void> _verifyIntegrity(Database db) async {
    final fk = await db.rawQuery('PRAGMA foreign_key_check');
    if (fk.isNotEmpty) {
      throw AppDatabaseException(
        DbErrorKind.corrupted,
        'Foreign key check found ${fk.length} violation(s) on open.',
      );
    }
    final integrity = await db.rawQuery('PRAGMA integrity_check');
    final result = integrity.isEmpty ? null : integrity.first.values.first;
    if (result != 'ok') {
      throw AppDatabaseException(
          DbErrorKind.corrupted, 'Integrity check failed: $result');
    }
  }

  Future<void> close() => _db.close();
}
