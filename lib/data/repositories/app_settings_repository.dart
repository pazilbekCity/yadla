import 'package:sqflite/sqflite.dart' show ConflictAlgorithm;

import '../database/app_database_exception.dart';
import '../models/review_and_settings.dart';
import 'repository_base.dart';

/// Key/value settings store.
class AppSettingsRepository extends RepositoryBase {
  AppSettingsRepository(super.db, super.clock);

  static const interfaceLanguageKey = 'interface_language';

  /// Interface languages planned for the app (Karakalpak, Uzbek, Russian).
  static const supportedLanguages = {'kaa', 'uz', 'ru'};

  Future<AppSetting?> get(String key) => guardDb('Get setting', () async {
        final rows =
            await db.query('app_settings', where: 'key = ?', whereArgs: [key]);
        return rows.isEmpty ? null : AppSetting.fromMap(rows.first);
      });

  Future<List<AppSetting>> getAll() => guardDb('List settings', () async {
        final rows = await db.query('app_settings', orderBy: 'key');
        return rows.map(AppSetting.fromMap).toList();
      });

  /// Inserts or replaces the value for [key].
  Future<AppSetting> set(String key, String value) =>
      guardDb('Set setting', () async {
        final k = requireText(key, 'Setting key');
        await db.insert(
          'app_settings',
          {'key': k, 'value': value, 'updated_at': nowMs()},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        return (await get(k))!;
      });

  Future<void> delete(String key) => guardDb('Delete setting', () async {
        final n = await db.delete('app_settings', where: 'key = ?', whereArgs: [key]);
        if (n == 0) {
          throw AppDatabaseException(
              DbErrorKind.notFound, 'Setting "$key" not found.');
        }
      });

  /// Returns the stored interface language code, or null if never chosen.
  Future<String?> getInterfaceLanguage() async =>
      (await get(interfaceLanguageKey))?.value;

  Future<void> setInterfaceLanguage(String code) async {
    if (!supportedLanguages.contains(code)) {
      throw AppDatabaseException(DbErrorKind.validation,
          'Unsupported interface language "$code". Use one of $supportedLanguages.');
    }
    await set(interfaceLanguageKey, code);
  }
}
