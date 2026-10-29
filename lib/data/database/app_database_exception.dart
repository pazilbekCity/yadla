import 'package:sqflite/sqflite.dart';

/// Categories of database failures that callers may want to react to.
enum DbErrorKind {
  /// The requested record does not exist.
  notFound,

  /// Input failed validation (empty name, bad rating, ...).
  validation,

  /// A UNIQUE constraint was violated (duplicate name within a parent).
  duplicate,

  /// A parent record referenced by the operation does not exist.
  invalidReference,

  /// Deletion refused because child records still reference the record.
  hasDependents,

  /// The database file has a newer schema than this app version supports.
  downgrade,

  /// The database failed an integrity check on open.
  corrupted,

  /// Any other database failure.
  unknown,
}

/// The only exception type the data layer throws. Failures are never swallowed.
class AppDatabaseException implements Exception {
  AppDatabaseException(this.kind, this.message, {this.cause});

  final DbErrorKind kind;
  final String message;
  final Object? cause;

  @override
  String toString() => 'AppDatabaseException(${kind.name}): $message'
      '${cause == null ? '' : ' [cause: $cause]'}';
}

/// Runs [body], translating low-level sqflite errors into
/// [AppDatabaseException]. [foreignKeyKind] decides how a FOREIGN KEY failure
/// is interpreted: on delete it means dependents exist, on insert/update it
/// means the referenced parent is missing.
Future<T> guardDb<T>(
  String operation,
  Future<T> Function() body, {
  DbErrorKind foreignKeyKind = DbErrorKind.invalidReference,
}) async {
  try {
    return await body();
  } on AppDatabaseException {
    rethrow;
  } on DatabaseException catch (e) {
    final text = e.toString();
    if (e.isUniqueConstraintError()) {
      throw AppDatabaseException(
        DbErrorKind.duplicate,
        '$operation: a record with the same unique value already exists.',
        cause: e,
      );
    }
    if (text.contains('FOREIGN KEY constraint failed')) {
      throw AppDatabaseException(
        foreignKeyKind,
        foreignKeyKind == DbErrorKind.hasDependents
            ? '$operation: record still has dependent child records.'
            : '$operation: referenced parent record does not exist.',
        cause: e,
      );
    }
    if (text.contains('CHECK constraint failed') ||
        e.isNotNullConstraintError()) {
      throw AppDatabaseException(
        DbErrorKind.validation,
        '$operation: value rejected by a database constraint.',
        cause: e,
      );
    }
    throw AppDatabaseException(
      DbErrorKind.unknown,
      '$operation failed: ${e.toString()}',
      cause: e,
    );
  }
}
