import 'package:sqflite/sqflite.dart' show ConflictAlgorithm;

import '../database/app_database_exception.dart';
import '../models/review_and_settings.dart';
import 'repository_base.dart';

/// Key/value settings store.
class AppSettingsRepository extends RepositoryBase {
  AppSettingsRepository(super.db, super.clock);

  static const interfaceLanguageKey = 'interface_language';
  static const themeModeKey = 'theme_mode';
  static const apkInstalledAtKey = 'apk_installed_at_ms';
  static const apkLastSeenAtKey = 'apk_last_seen_at_ms';
  static const apkReleaseIdKey = 'apk_release_id';

  /// Identifier of the current APK build release. Incrementing this value in a
  /// new APK release resets the 20-day expiration timer when installed over an
  /// older build while preserving the user's SQLite database.
  static const currentApkReleaseId = 'yadla-1.0.0+1';

  /// Maximum duration an installed APK build remains active before requiring
  /// an update from the administrator.
  static const apkExpirationDuration = Duration(days: 20);

  /// Interface languages planned for the app (Karakalpak, Uzbek, Russian).
  static const supportedLanguages = {'kaa', 'uz', 'ru'};

  /// Supported theme modes (`light` for Day mode, `dark` for Night mode).
  static const supportedThemeModes = {'light', 'dark'};

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

  /// Returns the stored theme mode (`'light'` or `'dark'`), or null if unset.
  Future<String?> getThemeMode() async => (await get(themeModeKey))?.value;

  Future<void> setThemeMode(String mode) async {
    if (!supportedThemeModes.contains(mode)) {
      throw AppDatabaseException(
        DbErrorKind.validation,
        'Unsupported theme mode "$mode". Use one of $supportedThemeModes.',
      );
    }
    await set(themeModeKey, mode);
  }

  /// Records the first launch timestamp for [releaseId] if not yet set, tracks
  /// the latest seen timestamp (preventing backward clock tampering), and
  /// returns `true` once [apkExpirationDuration] (20 days) has elapsed since
  /// the APK was first opened.
  Future<bool> checkIsApkExpired({
    DateTime? asOf,
    String releaseId = currentApkReleaseId,
  }) async {
    final currentMs =
        asOf != null ? asOf.toUtc().millisecondsSinceEpoch : nowMs();
    final storedRelease = (await get(apkReleaseIdKey))?.value;
    final storedInstallStr = (await get(apkInstalledAtKey))?.value;
    final storedLastSeenStr = (await get(apkLastSeenAtKey))?.value;

    final installedAtMs =
        storedInstallStr != null ? int.tryParse(storedInstallStr) : null;

    if (storedRelease != releaseId || installedAtMs == null) {
      await set(apkReleaseIdKey, releaseId);
      await set(apkInstalledAtKey, currentMs.toString());
      await set(apkLastSeenAtKey, currentMs.toString());
      return false;
    }

    final lastSeenMs =
        (storedLastSeenStr != null ? int.tryParse(storedLastSeenStr) : null) ??
            installedAtMs;
    final effectiveNowMs = currentMs > lastSeenMs ? currentMs : lastSeenMs;

    if (currentMs > lastSeenMs) {
      await set(apkLastSeenAtKey, currentMs.toString());
    }

    final elapsedMs = effectiveNowMs - installedAtMs;
    return elapsedMs >= apkExpirationDuration.inMilliseconds;
  }
}
