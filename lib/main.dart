import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'data/database/app_database.dart';
import 'ui/app_scope.dart';
import 'ui/catalog_screens.dart';
import 'ui/common.dart';
import 'ui/strings.dart';
import 'ui/theme.dart';

typedef DatabaseOpener = Future<AppDatabase> Function();

void main() {
  runApp(YadlaApp(openDatabase: AppDatabase.openDefault));
}

class _AppInitData {
  const _AppInitData(
    this.database,
    this.language,
    this.themeMode,
    this.isExpired,
  );

  final AppDatabase database;
  final AppLanguage language;
  final ThemeMode themeMode;
  final bool isExpired;
}

class YadlaApp extends StatefulWidget {
  const YadlaApp({super.key, required this.openDatabase});

  final DatabaseOpener openDatabase;

  @override
  State<YadlaApp> createState() => _YadlaAppState();
}

class _YadlaAppState extends State<YadlaApp> with WidgetsBindingObserver {
  late Future<_AppInitData> _initFuture = _initialize();
  AppDatabase? _db;
  bool _expiredOverride = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final db = _db;
      if (db != null && !_expiredOverride) {
        db.settings.checkIsApkExpired().then((expired) {
          if (expired && mounted && !_expiredOverride) {
            setState(() => _expiredOverride = true);
          }
        });
      }
    }
  }

  Future<_AppInitData> _initialize() async {
    final db = await widget.openDatabase();
    _db = db;
    final storedCode = await db.settings.getInterfaceLanguage();
    final storedTheme = await db.settings.getThemeMode();
    final isExpired = await db.settings.checkIsApkExpired();
    final lang = AppLanguage.fromCode(storedCode);
    final themeMode = AppScope.themeModeFromCode(storedTheme);
    S.setLanguage(lang);
    return _AppInitData(db, lang, themeMode, isExpired);
  }

  void _retry() => setState(() {
        _initFuture = _initialize();
      });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_AppInitData>(
      future: _initFuture,
      builder: (context, snapshot) {
        final initData = snapshot.data;
        if (initData != null) {
          final isExpired = initData.isExpired || _expiredOverride;
          return AppScope(
            database: initData.database,
            initialLanguage: initData.language,
            initialThemeMode: initData.themeMode,
            child: Builder(
              builder: (ctx) {
                final activeThemeMode = AppScope.themeModeOf(ctx);
                return MaterialApp(
                  debugShowCheckedModeBanner: false,
                  title: S.appTitle,
                  theme: YadlaTheme.light(),
                  darkTheme: YadlaTheme.dark(),
                  themeMode: activeThemeMode,
                  home: isExpired
                      ? const ExpiredVersionScreen()
                      : const SubjectsScreen(),
                );
              },
            ),
          );
        }
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: S.appTitle,
          theme: YadlaTheme.light(),
          darkTheme: YadlaTheme.dark(),
          home: Scaffold(
            appBar: AppBar(title: const Text(S.appTitle)),
            body: AsyncView<_AppInitData>(
              future: _initFuture,
              onRetry: _retry,
              builder: (_, _) => const SizedBox.shrink(),
            ),
          ),
        );
      },
    );
  }
}

/// Full-screen lock displayed once 20 days have elapsed since the APK was
/// installed, blocking access until an updated build is obtained from Admin.
class ExpiredVersionScreen extends StatelessWidget {
  const ExpiredVersionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return PopScope(
      canPop: false,
      child: Scaffold(
        key: const Key('expired-version-screen'),
        appBar: AppBar(
          title: const Text(S.appTitle),
          automaticallyImplyLeading: false,
          actions: const [
            ThemeModeButton(),
            LanguageSelectorButton(),
          ],
        ),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(color: cs.error.withValues(alpha: 0.35)),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 28,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: cs.errorContainer.withValues(alpha: 0.6),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.lock_clock_outlined,
                          size: 34,
                          color: cs.error,
                        ),
                      ),
                      const SizedBox(height: 20),
                      SelectableText(
                        S.expiredVersionFullMessage,
                        key: const Key('expired-version-message'),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 20),
                      FilledButton.tonalIcon(
                        key: const Key('copy-admin-link-button'),
                        onPressed: () async {
                          await Clipboard.setData(
                            const ClipboardData(text: S.adminTelegramUrl),
                          );
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(S.adminLinkCopied)),
                          );
                        },
                        icon: const Icon(Icons.copy_rounded, size: 18),
                        label: Text(S.copyAdminLink),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
