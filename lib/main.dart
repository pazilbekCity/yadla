import 'package:flutter/material.dart';

import 'data/database/app_database.dart';
import 'ui/app_scope.dart';
import 'ui/catalog_screens.dart';
import 'ui/common.dart';
import 'ui/strings.dart';

typedef DatabaseOpener = Future<AppDatabase> Function();

void main() {
  runApp(AnkiApp(openDatabase: AppDatabase.openDefault));
}

class _AppInitData {
  const _AppInitData(this.database, this.language);

  final AppDatabase database;
  final AppLanguage language;
}

class AnkiApp extends StatefulWidget {
  const AnkiApp({super.key, required this.openDatabase});

  final DatabaseOpener openDatabase;

  @override
  State<AnkiApp> createState() => _AnkiAppState();
}

class _AnkiAppState extends State<AnkiApp> {
  late Future<_AppInitData> _initFuture = _initialize();

  Future<_AppInitData> _initialize() async {
    final db = await widget.openDatabase();
    final storedCode = await db.settings.getInterfaceLanguage();
    final lang = AppLanguage.fromCode(storedCode);
    S.setLanguage(lang);
    return _AppInitData(db, lang);
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
          return AppScope(
            database: initData.database,
            initialLanguage: initData.language,
            child: MaterialApp(
              title: S.appTitle,
              home: const SubjectsScreen(),
            ),
          );
        }
        return MaterialApp(
          title: S.appTitle,
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
