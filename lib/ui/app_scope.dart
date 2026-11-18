import 'package:flutter/material.dart';

import '../data/database/app_database.dart';
import 'strings.dart';

/// Gives the widget tree access to the opened [AppDatabase], the active
/// [AppLanguage], and the active [ThemeMode]. Screens use repositories only;
/// they never touch sqflite or SQL directly.
class AppScope extends StatefulWidget {
  const AppScope({
    super.key,
    required this.database,
    this.initialLanguage,
    this.initialThemeMode,
    required this.child,
  });

  final AppDatabase database;
  final AppLanguage? initialLanguage;
  final ThemeMode? initialThemeMode;
  final Widget child;

  static AppDatabase of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<_InheritedAppScope>();
    assert(scope != null, 'AppScope not found in widget tree');
    return scope!.database;
  }

  /// Returns the active [AppLanguage] and subscribes [context] to language
  /// changes when inside an [AppScope].
  static AppLanguage languageOf(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<_InheritedAppScope>();
    return scope?.language ?? S.currentLanguage;
  }

  /// Returns the active [ThemeMode] (`ThemeMode.light` or `ThemeMode.dark`)
  /// and subscribes [context] to theme changes when inside an [AppScope].
  static ThemeMode themeModeOf(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<_InheritedAppScope>();
    return scope?.themeMode ?? ThemeMode.light;
  }

  /// Changes the active UI language immediately and persists the selection to
  /// `app_settings` (`interface_language`).
  static Future<void> setLanguage(
    BuildContext context,
    AppLanguage language,
  ) async {
    final scope =
        context.dependOnInheritedWidgetOfExactType<_InheritedAppScope>();
    assert(scope != null, 'AppScope not found in widget tree');
    await scope!.state._changeLanguage(language);
  }

  /// Toggles between Day (`ThemeMode.light`) and Night (`ThemeMode.dark`) mode
  /// and persists the choice to `app_settings` (`theme_mode`).
  static Future<void> toggleThemeMode(BuildContext context) async {
    final scope =
        context.dependOnInheritedWidgetOfExactType<_InheritedAppScope>();
    assert(scope != null, 'AppScope not found in widget tree');
    final next = scope!.themeMode == ThemeMode.dark
        ? ThemeMode.light
        : ThemeMode.dark;
    await scope.state._changeThemeMode(next);
  }

  /// Reloads the active UI language from `app_settings` (e.g. after restoring
  /// a backup) and rebuilds the widget tree if it changed.
  static Future<void> syncLanguageFromDatabase(BuildContext context) async {
    final scope =
        context.dependOnInheritedWidgetOfExactType<_InheritedAppScope>();
    assert(scope != null, 'AppScope not found in widget tree');
    await scope!.state._loadPersistedSettings();
  }

  static ThemeMode themeModeFromCode(String? code) =>
      code == 'dark' ? ThemeMode.dark : ThemeMode.light;

  @override
  State<AppScope> createState() => _AppScopeState();
}

class _AppScopeState extends State<AppScope> {
  late AppLanguage _language;
  late ThemeMode _themeMode;

  @override
  void initState() {
    super.initState();
    _language = widget.initialLanguage ?? AppLanguage.kaa;
    _themeMode = widget.initialThemeMode ?? ThemeMode.light;
    S.setLanguage(_language);
    if (widget.initialLanguage == null || widget.initialThemeMode == null) {
      _loadPersistedSettings();
    }
  }

  @override
  void didUpdateWidget(covariant AppScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialLanguage != null &&
        widget.initialLanguage != oldWidget.initialLanguage &&
        widget.initialLanguage != _language) {
      _language = widget.initialLanguage!;
      S.setLanguage(_language);
    }
    if (widget.initialThemeMode != null &&
        widget.initialThemeMode != oldWidget.initialThemeMode &&
        widget.initialThemeMode != _themeMode) {
      _themeMode = widget.initialThemeMode!;
    }
    if (widget.database != oldWidget.database &&
        (widget.initialLanguage == null || widget.initialThemeMode == null)) {
      _loadPersistedSettings();
    }
  }

  Future<void> _loadPersistedSettings() async {
    try {
      final storedLang = await widget.database.settings.getInterfaceLanguage();
      final storedTheme = await widget.database.settings.getThemeMode();
      final resolvedLang = AppLanguage.fromCode(storedLang);
      final resolvedTheme = AppScope.themeModeFromCode(storedTheme);
      S.setLanguage(resolvedLang);
      if (mounted &&
          (resolvedLang != _language || resolvedTheme != _themeMode)) {
        setState(() {
          _language = resolvedLang;
          _themeMode = resolvedTheme;
        });
      }
    } catch (_) {
      // Fall back to defaults if reading settings fails.
    }
  }

  Future<void> _changeLanguage(AppLanguage language) async {
    S.setLanguage(language);
    if (mounted) {
      setState(() {
        _language = language;
      });
    }
    await widget.database.settings.setInterfaceLanguage(language.code);
  }

  Future<void> _changeThemeMode(ThemeMode mode) async {
    if (mounted) {
      setState(() {
        _themeMode = mode;
      });
    }
    await widget.database.settings
        .setThemeMode(mode == ThemeMode.dark ? 'dark' : 'light');
  }

  @override
  Widget build(BuildContext context) {
    S.setLanguage(_language);
    return _InheritedAppScope(
      database: widget.database,
      language: _language,
      themeMode: _themeMode,
      state: this,
      child: widget.child,
    );
  }
}

class _InheritedAppScope extends InheritedWidget {
  const _InheritedAppScope({
    required this.database,
    required this.language,
    required this.themeMode,
    required this.state,
    required super.child,
  });

  final AppDatabase database;
  final AppLanguage language;
  final ThemeMode themeMode;
  final _AppScopeState state;

  @override
  bool updateShouldNotify(_InheritedAppScope oldWidget) =>
      database != oldWidget.database ||
      language != oldWidget.language ||
      themeMode != oldWidget.themeMode;
}
