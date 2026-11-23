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

final RegExp _naturalTokenPattern = RegExp(r'(\d+|\D+)');

/// Compares two display names using natural numeric ordering (e.g.
/// `"2-sabaq"` < `"10-sabaq"`, `"5-klass"` < `"10-klass"`) and case-insensitive
/// text comparison, falling back to [idA] / [idB] for deterministic ties.
int compareNaturalNames(
  String a,
  String b, {
  String idA = '',
  String idB = '',
}) {
  final tokensA = _naturalTokenPattern
      .allMatches(a.trim())
      .map((m) => m.group(0)!)
      .toList();
  final tokensB = _naturalTokenPattern
      .allMatches(b.trim())
      .map((m) => m.group(0)!)
      .toList();
  final minLen =
      tokensA.length < tokensB.length ? tokensA.length : tokensB.length;
  for (var i = 0; i < minLen; i++) {
    final tokA = tokensA[i];
    final tokB = tokensB[i];
    final numA = int.tryParse(tokA);
    final numB = int.tryParse(tokB);
    final int cmp;
    if (numA != null && numB != null) {
      cmp = numA.compareTo(numB);
    } else {
      cmp = tokA.toLowerCase().compareTo(tokB.toLowerCase());
    }
    if (cmp != 0) return cmp;
  }
  final lenCmp = tokensA.length.compareTo(tokensB.length);
  if (lenCmp != 0) return lenCmp;
  final exactCmp = a.compareTo(b);
  if (exactCmp != 0) return exactCmp;
  return idA.compareTo(idB);
}
