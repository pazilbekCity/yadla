import 'package:sqflite/sqflite.dart';

import '../database/app_database_exception.dart';

typedef Clock = DateTime Function();

/// Common helpers for repositories.
abstract class RepositoryBase {
  RepositoryBase(this.db, this.clock);

  final Database db;
  final Clock clock;

  int nowMs() => clock().toUtc().millisecondsSinceEpoch;

  /// Trims [value] and rejects blank text.
  String requireText(String value, String field) {
    final t = value.trim();
    if (t.isEmpty) {
      throw AppDatabaseException(
          DbErrorKind.validation, '$field must not be empty.');
    }
    return t;
  }

  /// Trims optional text; blank becomes null.
  String? optionalText(String? value) {
    final t = value?.trim();
    return (t == null || t.isEmpty) ? null : t;
  }

  AppDatabaseException notFound(String entity, String id) =>
      AppDatabaseException(DbErrorKind.notFound, '$entity "$id" not found.');
}
