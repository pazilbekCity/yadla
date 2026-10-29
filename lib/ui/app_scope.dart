import 'package:flutter/widgets.dart';

import '../data/database/app_database.dart';
import 'strings.dart';

/// Gives the widget tree access to the opened [AppDatabase] and the active
/// [AppLanguage]. Screens use repositories only; they never touch sqflite or
/// SQL directly.
class AppScope extends StatefulWidget {
  const AppScope({
    super.key,
    required this.database,
    this.initialLanguage,
    required this.child,
  });

  final AppDatabase database;
  final AppLanguage? initialLanguage;
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

  /// Reloads the active UI language from `app_settings` (e.g. after restoring
  /// a backup) and rebuilds the widget tree if it changed.
  static Future<void> syncLanguageFromDatabase(BuildContext context) async {
    final scope =
        context.dependOnInheritedWidgetOfExactType<_InheritedAppScope>();
    assert(scope != null, 'AppScope not found in widget tree');
    await scope!.state._loadPersistedLanguage();
  }

  @override
  State<AppScope> createState() => _AppScopeState();
}

class _AppScopeState extends State<AppScope> {
  late AppLanguage _language;

  @override
  void initState() {
    super.initState();
    _language = widget.initialLanguage ?? AppLanguage.kaa;
    S.setLanguage(_language);
    if (widget.initialLanguage == null) {
      _loadPersistedLanguage();
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
    } else if (widget.database != oldWidget.database &&
        widget.initialLanguage == null) {
      _loadPersistedLanguage();
    }
  }

  Future<void> _loadPersistedLanguage() async {
    try {
      final stored = await widget.database.settings.getInterfaceLanguage();
      final resolved = AppLanguage.fromCode(stored);
      S.setLanguage(resolved);
      if (mounted && resolved != _language) {
        setState(() {
          _language = resolved;
        });
      }
    } catch (_) {
      // Fall back to default Karakalpak if reading settings fails.
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

  @override
  Widget build(BuildContext context) {
    S.setLanguage(_language);
    return _InheritedAppScope(
      database: widget.database,
      language: _language,
      state: this,
      child: widget.child,
    );
  }
}

class _InheritedAppScope extends InheritedWidget {
  const _InheritedAppScope({
    required this.database,
    required this.language,
    required this.state,
    required super.child,
  });

  final AppDatabase database;
  final AppLanguage language;
  final _AppScopeState state;

  @override
  bool updateShouldNotify(_InheritedAppScope oldWidget) =>
      database != oldWidget.database || language != oldWidget.language;
}
