import 'dart:convert';
import 'dart:io';

import '../database/app_database.dart';
import '../database/ids.dart';
import '../models/flashcard.dart';

/// Function signature for fetching text content from a URL (injectable for tests).
typedef RemoteTextFetcher = Future<String> Function(Uri uri);

/// Metadata for a preset subject connected to a Google Sheets database.
class PresetSubjectDefinition {
  const PresetSubjectDefinition({
    required this.id,
    required this.name,
    required this.description,
    required this.spreadsheetId,
    this.topicsGid,
    this.answersGid,
    this.topicsSheetName = 'Temalar',
    this.answersSheetName = 'Juwaplar',
  });

  final String id;
  final String name;
  final String description;
  final String spreadsheetId;
  final String? topicsGid;
  final String? answersGid;
  final String topicsSheetName;
  final String answersSheetName;

  Uri get topicsCsvUri {
    final gid = topicsGid?.trim();
    if (gid != null && gid.isNotEmpty) {
      return Uri.parse(
        'https://docs.google.com/spreadsheets/d/$spreadsheetId/export?format=csv&gid=$gid',
      );
    }
    return Uri.parse(
      'https://docs.google.com/spreadsheets/d/$spreadsheetId/gviz/tq?tqx=out:csv&sheet=${Uri.encodeQueryComponent(topicsSheetName)}',
    );
  }

  Uri get answersCsvUri {
    final gid = answersGid?.trim();
    if (gid != null && gid.isNotEmpty) {
      return Uri.parse(
        'https://docs.google.com/spreadsheets/d/$spreadsheetId/export?format=csv&gid=$gid',
      );
    }
    return Uri.parse(
      'https://docs.google.com/spreadsheets/d/$spreadsheetId/gviz/tq?tqx=out:csv&sheet=${Uri.encodeQueryComponent(answersSheetName)}',
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'spreadsheet_id': spreadsheetId,
        'topics_gid': topicsGid,
        'answers_gid': answersGid,
        'topics_sheet_name': topicsSheetName,
        'answers_sheet_name': answersSheetName,
      };

  factory PresetSubjectDefinition.fromJson(Map<String, Object?> json) =>
      PresetSubjectDefinition(
        id: (json['id'] as String?) ?? '',
        name: (json['name'] as String?) ?? '',
        description: (json['description'] as String?) ?? '',
        spreadsheetId: (json['spreadsheet_id'] as String?) ?? '',
        topicsGid: json['topics_gid'] as String?,
        answersGid: json['answers_gid'] as String?,
        topicsSheetName: (json['topics_sheet_name'] as String?) ?? 'Temalar',
        answersSheetName: (json['answers_sheet_name'] as String?) ?? 'Juwaplar',
      );
}

/// Lightweight announcement / sponsor banner managed from the `Reklama`
/// worksheet in the master Google Spreadsheet.
class PromoBannerData {
  const PromoBannerData({
    required this.title,
    this.subtitle,
    this.contactOrLink,
  });

  final String title;
  final String? subtitle;
  final String? contactOrLink;

  Map<String, Object?> toJson() => {
        'title': title,
        'subtitle': subtitle,
        'contact_or_link': contactOrLink,
      };

  factory PromoBannerData.fromJson(Map<String, Object?> json) =>
      PromoBannerData(
        title: ((json['title'] as String?) ?? '').trim(),
        subtitle: (json['subtitle'] as String?)?.trim(),
        contactOrLink: (json['contact_or_link'] as String?)?.trim(),
      );
}

/// Summary of importing/syncing a preset subject into the local SQLite database.
class PresetImportResult {
  const PresetImportResult({
    required this.subjectId,
    required this.subjectName,
    required this.booksCount,
    required this.topicsCount,
    required this.cardsImported,
    required this.cardsUpdated,
  });

  final String subjectId;
  final String subjectName;
  final int booksCount;
  final int topicsCount;
  final int cardsImported;
  final int cardsUpdated;
}

class PresetCatalogException implements Exception {
  const PresetCatalogException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() => 'PresetCatalogException: $message';
}

/// Service that downloads and imports preset subjects (such as «Informatika»)
/// directly from Google Sheets CSV export endpoints into the local offline
/// SQLite database.
class PresetCatalogService {
  const PresetCatalogService({
    this.fetchText,
  });

  final RemoteTextFetcher? fetchText;

  /// Master Google Spreadsheet ID that hosts `Informatika` and optionally a
  /// `Pánler` catalog worksheet listing additional subjects.
  static const String masterCatalogSpreadsheetId =
      '1RaSNsKj74uRSk1X2qBBwHZGV46KbOWysOAjomZKqzsU';

  /// Settings key used to persist dynamically linked Google Sheets subjects
  /// so they can be synced (`🔄 Bazadan jańalaw`) anytime later.
  static const String linkedPresetsSettingKey = 'linked_preset_subjects';

  /// Settings key used to cache the latest `Reklama` / `Daǵaza` banner from
  /// Google Sheets for offline display.
  static const String cachedPromoBannerSettingKey = 'cached_promo_banner';

  /// Registered preset subjects available out of the box.
  static const List<PresetSubjectDefinition> availablePresets = [
    PresetSubjectDefinition(
      id: 'informatika',
      name: 'Informatika',
      description: '5–11-klass Informatika hám AT sabaqlıqları boyınsha smart kartalar',
      spreadsheetId: masterCatalogSpreadsheetId,
      topicsGid: '0',
      answersGid: '623643907',
    ),
  ];

  static Uri get masterCatalogCsvUri => Uri.parse(
        'https://docs.google.com/spreadsheets/d/$masterCatalogSpreadsheetId/gviz/tq?tqx=out:csv&sheet=P%C3%A1nler',
      );

  static Uri get promoBannerCsvUri => Uri.parse(
        'https://docs.google.com/spreadsheets/d/$masterCatalogSpreadsheetId/gviz/tq?tqx=out:csv&sheet=Reklama',
      );

  /// Extracts a Google Sheets `spreadsheetId` from a full URL
  /// (`https://docs.google.com/spreadsheets/d/<ID>/edit...`) or a raw ID string.
  /// Returns `null` if the input is not a valid spreadsheet URL or ID.
  static String? extractSpreadsheetId(String urlOrId) {
    final trimmed = urlOrId.trim();
    if (trimmed.isEmpty) return null;
    final urlMatch = RegExp(
      r'spreadsheets/d/([a-zA-Z0-9_-]{15,})',
    ).firstMatch(trimmed);
    if (urlMatch != null) {
      return urlMatch.group(1);
    }
    if (RegExp(r'^[a-zA-Z0-9_-]{20,}$').hasMatch(trimmed)) {
      return trimmed;
    }
    return null;
  }

  /// Extracts a numeric `gid` from a Google Sheets URL if present (e.g.
  /// `...#gid=623643907` or `...?gid=623643907`).
  static String? extractGidFromUrl(String url) {
    final match = RegExp(r'[?#&]gid=(\d+)').firstMatch(url.trim());
    return match?.group(1);
  }

  static Future<String> defaultHttpFetch(Uri uri) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      var currentUri = uri;
      for (var redirects = 0; redirects < 6; redirects++) {
        final request = await client.getUrl(currentUri);
        request.followRedirects = false;
        final response = await request.close();
        if (response.isRedirect ||
            response.statusCode == HttpStatus.movedPermanently ||
            response.statusCode == HttpStatus.found ||
            response.statusCode == HttpStatus.seeOther ||
            response.statusCode == HttpStatus.temporaryRedirect ||
            response.statusCode == HttpStatus.permanentRedirect) {
          final location = response.headers.value(HttpHeaders.locationHeader);
          await response.drain<void>();
          if (location == null) {
            throw const PresetCatalogException('Redirect missing Location header.');
          }
          currentUri = currentUri.resolve(location);
          continue;
        }
        if (response.statusCode != HttpStatus.ok) {
          await response.drain<void>();
          throw PresetCatalogException(
            'HTTP ${response.statusCode} while fetching $currentUri',
          );
        }
        final bytes = await response.fold<List<int>>(
          <int>[],
          (acc, chunk) => acc..addAll(chunk),
        );
        final decoded = utf8.decode(bytes, allowMalformed: true);
        final trimmedLeft = decoded.trimLeft().toLowerCase();
        if (trimmedLeft.startsWith('<!doctype html') ||
            trimmedLeft.startsWith('<html')) {
          throw const PresetCatalogException(
            'Google Sheets returned an HTML sign-in page instead of CSV.',
          );
        }
        return decoded;
      }
      throw const PresetCatalogException('Too many redirects.');
    } finally {
      client.close(force: true);
    }
  }

  /// Downloads [preset]'s `Temalar` and `Juwaplar` sheets and imports all
  /// books, topics, and flashcards into [db] inside a single transaction.
  Future<PresetImportResult> downloadAndImportPreset({
    required AppDatabase db,
    required PresetSubjectDefinition preset,
  }) async {
    final fetcher = fetchText ?? defaultHttpFetch;
    final String topicsCsv;
    final String answersCsv;
    try {
      final results = await Future.wait([
        fetcher(preset.topicsCsvUri),
        fetcher(preset.answersCsvUri),
      ]);
      topicsCsv = results[0];
      answersCsv = results[1];
    } catch (e) {
      if (e is PresetCatalogException) rethrow;
      throw PresetCatalogException('Failed to download preset sheets.', e);
    }

    final result = await importFromCsvStrings(
      db: db,
      preset: preset,
      topicsCsv: topicsCsv,
      answersCsv: answersCsv,
    );
    await saveLinkedPreset(db, preset);
    return result;
  }

  /// Persists [preset] in `app_settings` so custom or remotely discovered
  /// subjects remain linked for future one-tap `🔄 Bazadan jańalaw` syncs.
  static Future<void> saveLinkedPreset(
    AppDatabase db,
    PresetSubjectDefinition preset,
  ) async {
    try {
      final current = await loadLinkedPresets(db);
      final byName = <String, PresetSubjectDefinition>{
        for (final p in current) p.name.trim().toLowerCase(): p,
      };
      byName[preset.name.trim().toLowerCase()] = preset;
      final encoded = jsonEncode(
        byName.values.map((p) => p.toJson()).toList(),
      );
      await db.settings.set(linkedPresetsSettingKey, encoded);
    } catch (_) {
      // Non-fatal if settings write fails.
    }
  }

  /// Loads all dynamically linked preset subjects stored in `app_settings`.
  static Future<List<PresetSubjectDefinition>> loadLinkedPresets(
    AppDatabase db,
  ) async {
    try {
      final setting = await db.settings.get(linkedPresetsSettingKey);
      if (setting == null || setting.value.trim().isEmpty) return const [];
      final decoded = jsonDecode(setting.value);
      if (decoded is! List) return const [];
      final list = <PresetSubjectDefinition>[];
      for (final item in decoded) {
        if (item is Map) {
          final def = PresetSubjectDefinition.fromJson(
            item.cast<String, Object?>(),
          );
          if (def.name.trim().isNotEmpty && def.spreadsheetId.trim().isNotEmpty) {
            list.add(def);
          }
        }
      }
      return list;
    } catch (_) {
      return const [];
    }
  }

  /// Discovers preset subjects from the remote `Pánler` worksheet in the
  /// master Google Spreadsheet (if present) and merges them with built-in
  /// [availablePresets]. Never throws if offline or if the `Pánler` worksheet
  /// has not been created yet.
  Future<List<PresetSubjectDefinition>> fetchRemoteCatalogPresets() async {
    final byName = <String, PresetSubjectDefinition>{
      for (final p in availablePresets) p.name.trim().toLowerCase(): p,
    };
    try {
      final fetcher = fetchText ?? defaultHttpFetch;
      final csv = await fetcher(masterCatalogCsvUri);
      final rows = parseCsv(csv);
      for (var i = 0; i < rows.length; i++) {
        final row = rows[i];
        if (row.length < 3) continue;
        final colA = row[0].trim();
        final colB = row[1].trim();
        final colC = row[2].trim();
        if (colA.isEmpty || colC.isEmpty) continue;
        if (i == 0 &&
            (colA.toLowerCase().contains('pán') ||
                colA.toLowerCase().contains('fan') ||
                colA.toLowerCase().contains('предмет') ||
                colA.toLowerCase() == 'klass')) {
          continue;
        }
        final sheetId = extractSpreadsheetId(colC);
        if (sheetId == null) continue;
        final topicsGid =
            row.length > 3 && row[3].trim().isNotEmpty ? row[3].trim() : '0';
        final answersGid = row.length > 4 && row[4].trim().isNotEmpty
            ? row[4].trim()
            : extractGidFromUrl(colC);
        final id = colA.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
        byName[colA.toLowerCase()] = PresetSubjectDefinition(
          id: id.isEmpty ? sheetId : id,
          name: colA,
          description: colB,
          spreadsheetId: sheetId,
          topicsGid: topicsGid,
          answersGid: answersGid,
        );
      }
    } catch (_) {
      // Ignore network/404 errors and fall back to built-in presets.
    }
    return byName.values.toList();
  }

  /// Loads the cached `Reklama` / `Daǵaza` banner from `app_settings`, or
  /// returns `null` if none is cached.
  static Future<PromoBannerData?> loadCachedPromoBanner(AppDatabase db) async {
    try {
      final setting = await db.settings.get(cachedPromoBannerSettingKey);
      if (setting == null || setting.value.trim().isEmpty) return null;
      final decoded = jsonDecode(setting.value);
      if (decoded is! Map) return null;
      final banner = PromoBannerData.fromJson(decoded.cast<String, Object?>());
      return banner.title.isEmpty ? null : banner;
    } catch (_) {
      return null;
    }
  }

  /// Fetches the `Reklama` worksheet from the master Google Spreadsheet, caches
  /// the active banner in `app_settings` (or clears the cache if the sheet row
  /// was emptied), and returns the active [PromoBannerData]. Falls back to the
  /// cached banner when offline.
  Future<PromoBannerData?> fetchAndCachePromoBanner(AppDatabase db) async {
    try {
      final fetcher = fetchText ?? defaultHttpFetch;
      final csv = await fetcher(promoBannerCsvUri);
      final rows = parseCsv(csv);
      if (rows.isEmpty) {
        return await loadCachedPromoBanner(db);
      }
      final firstColHeader = rows.first[0].trim().toLowerCase();
      // If `Reklama` sheet does not exist yet, Google gviz returns the first
      // sheet (`Temalar`, whose header is `Klass`). Ignore it safely.
      if (firstColHeader == 'klass') {
        return await loadCachedPromoBanner(db);
      }

      final isHeaderRow = firstColHeader.contains('reklama') ||
          firstColHeader.contains('daǵaza') ||
          firstColHeader.contains('dagaza') ||
          firstColHeader.contains('atama') ||
          firstColHeader.contains('title');
      final dataRowIndex = isHeaderRow ? 1 : 0;
      if (rows.length <= dataRowIndex) {
        // Active ad row was cleared in Google Sheets -> remove cached banner
        try {
          await db.settings.delete(cachedPromoBannerSettingKey);
        } catch (_) {}
        return null;
      }

      final row = rows[dataRowIndex];
      final title = row.isNotEmpty ? row[0].trim() : '';
      if (title.isEmpty) {
        try {
          await db.settings.delete(cachedPromoBannerSettingKey);
        } catch (_) {}
        return null;
      }
      final subtitle = row.length > 1 && row[1].trim().isNotEmpty
          ? row[1].trim()
          : null;
      final contact = row.length > 2 && row[2].trim().isNotEmpty
          ? row[2].trim()
          : null;
      final banner = PromoBannerData(
        title: title,
        subtitle: subtitle,
        contactOrLink: contact,
      );
      await db.settings.set(
        cachedPromoBannerSettingKey,
        jsonEncode(banner.toJson()),
      );
      return banner;
    } catch (_) {
      return await loadCachedPromoBanner(db);
    }
  }

  /// Finds a matching [PresetSubjectDefinition] by subject name (case-insensitive)
  /// across built-in presets and optional [customPresets].
  static PresetSubjectDefinition? findPresetByName(
    String subjectName, {
    List<PresetSubjectDefinition> customPresets = const [],
  }) {
    final normalized = subjectName.trim().toLowerCase();
    for (final p in availablePresets) {
      if (p.name.trim().toLowerCase() == normalized) return p;
    }
    for (final p in customPresets) {
      if (p.name.trim().toLowerCase() == normalized) return p;
    }
    return null;
  }

  /// Parses [topicsCsv] (`Temalar`) and [answersCsv] (`Juwaplar`) and writes
  /// them transactionally into [db] without duplicating or overwriting existing
  /// user data.
  Future<PresetImportResult> importFromCsvStrings({
    required AppDatabase db,
    required PresetSubjectDefinition preset,
    required String topicsCsv,
    required String answersCsv,
  }) async {
    final topicRows = parseCsv(topicsCsv);
    final answerRows = parseCsv(answersCsv);

    return db.rawDatabase.transaction((txn) async {
      final now = DateTime.now().toUtc().millisecondsSinceEpoch;

      // 1. Find or create Subject (match case-insensitively in Dart for full Unicode support)
      final allSubjects = await txn.query('subjects');
      final targetSubjNameLower = preset.name.trim().toLowerCase();
      Map<String, Object?>? matchedSubject;
      for (final s in allSubjects) {
        if ((s['name'] as String).trim().toLowerCase() == targetSubjNameLower) {
          matchedSubject = s;
          break;
        }
      }

      final String subjectId;
      if (matchedSubject != null) {
        subjectId = matchedSubject['id'] as String;
      } else {
        subjectId = generateId();
        await txn.insert('subjects', {
          'id': subjectId,
          'name': preset.name.trim(),
          'description': preset.description,
          'created_at': now,
          'updated_at': now,
        });
      }

      // Cache existing books for this subject: normalized bookName -> bookId
      final existingBooks = await txn.query(
        'books',
        where: 'subject_id = ?',
        whereArgs: [subjectId],
      );
      final bookIdByName = <String, String>{
        for (final b in existingBooks)
          (b['name'] as String).trim().toLowerCase(): b['id'] as String,
      };

      Future<String> ensureBook(String rawBookName) async {
        final trimmed = rawBookName.trim();
        final key = trimmed.toLowerCase();
        final existingId = bookIdByName[key];
        if (existingId != null) return existingId;
        final newId = generateId();
        await txn.insert('books', {
          'id': newId,
          'subject_id': subjectId,
          'name': trimmed,
          'description': null,
          'created_at': now,
          'updated_at': now,
        });
        bookIdByName[key] = newId;
        return newId;
      }

      // Cache topics per book: "$bookId\u0000$normalizedTopicName" -> topicId
      final topicIdByKey = <String, String>{};
      for (final bId in bookIdByName.values) {
        final existingTopics = await txn.query(
          'topics',
          where: 'book_id = ?',
          whereArgs: [bId],
        );
        for (final t in existingTopics) {
          final tName = (t['name'] as String).trim().toLowerCase();
          topicIdByKey['$bId\u0000$tName'] = t['id'] as String;
        }
      }

      Future<String> ensureTopic(String bookId, String rawTopicName) async {
        final trimmed = rawTopicName.trim();
        final compositeKey = '$bookId\u0000${trimmed.toLowerCase()}';
        final existingId = topicIdByKey[compositeKey];
        if (existingId != null) return existingId;
        final newId = generateId();
        await txn.insert('topics', {
          'id': newId,
          'book_id': bookId,
          'name': trimmed,
          'description': null,
          'created_at': now,
          'updated_at': now,
        });
        topicIdByKey[compositeKey] = newId;
        return newId;
      }

      // Cache default deck per topic: topicId -> deckId
      final deckIdByTopic = <String, String>{};
      Future<String> ensureDeck(String topicId, String topicName) async {
        final cached = deckIdByTopic[topicId];
        if (cached != null) return cached;
        final existingDecks = await txn.query(
          'decks',
          where: 'topic_id = ?',
          whereArgs: [topicId],
          orderBy: 'created_at ASC, id ASC',
          limit: 1,
        );
        if (existingDecks.isNotEmpty) {
          final id = existingDecks.first['id'] as String;
          deckIdByTopic[topicId] = id;
          return id;
        }
        final newId = generateId();
        await txn.insert('decks', {
          'id': newId,
          'topic_id': topicId,
          'name': topicName.trim().isEmpty ? 'Tiykarǵı' : topicName.trim(),
          'description': null,
          'created_at': now,
          'updated_at': now,
        });
        deckIdByTopic[topicId] = newId;
        return newId;
      }

      // 2. Process `Temalar` sheet rows (Col A = Klass, Col B = Tema atı)
      for (var i = 0; i < topicRows.length; i++) {
        final row = topicRows[i];
        if (row.length < 2) continue;
        final colA = row[0].trim();
        final colB = row[1].trim();
        if (colA.isEmpty || colB.isEmpty) continue;
        if (i == 0 && colA.toLowerCase() == 'klass') continue; // header row

        final bookId = await ensureBook(colA);
        await ensureTopic(bookId, colB);
      }

      // 3. Process `Juwaplar` sheet rows:
      // Col A (0): Klass
      // Col B (1): Tema
      // Col C (2): Gilt sóz
      // Col D (3): Anıqlama / Túsinik
      // Col E (4): Bet / Sáne
      // Col F (5): Sáne
      // Col G (6): Assosaciya (optional)
      final existingCardsByDeck = <String, Map<String, Map<String, Object?>>>{};
      Future<Map<String, Map<String, Object?>>> getDeckCardsMap(
        String deckId,
      ) async {
        final cached = existingCardsByDeck[deckId];
        if (cached != null) return cached;
        final rows = await txn.query(
          'flashcards',
          columns: [
            'id',
            'target_text',
            'definition_text',
            'association_text',
            'page_number',
          ],
          where: 'deck_id = ?',
          whereArgs: [deckId],
        );
        final map = <String, Map<String, Object?>>{};
        for (final r in rows) {
          final target = (r['target_text'] as String).trim().toLowerCase();
          // Always copy sqflite's read-only QueryRow into a mutable Map.
          map[target] = Map<String, Object?>.of(r);
        }
        existingCardsByDeck[deckId] = map;
        return map;
      }

      var cardsImported = 0;
      var cardsUpdated = 0;

      for (var i = 0; i < answerRows.length; i++) {
        final row = answerRows[i];
        if (row.length < 4) continue;
        final klass = row[0].trim();
        final tema = row[1].trim();
        final targetText = row[2].trim();
        final definitionText = row[3].trim();
        if (klass.isEmpty ||
            tema.isEmpty ||
            targetText.isEmpty ||
            definitionText.isEmpty) {
          continue;
        }
        if (i == 0 &&
            klass.toLowerCase() == 'klass' &&
            targetText.toLowerCase().contains('gilt')) {
          continue; // header row
        }

        final rawColE = row.length > 4 ? row[4].trim() : '';
        final pageNumber = _extractPageNumber(rawColE);

        final rawAssociation = row.length > 6 ? row[6].trim() : '';
        final associationText =
            rawAssociation.isEmpty ? null : rawAssociation;

        final bookId = await ensureBook(klass);
        final topicId = await ensureTopic(bookId, tema);
        final deckId = await ensureDeck(topicId, tema);
        final deckCards = await getDeckCardsMap(deckId);

        final targetKey = targetText.toLowerCase();
        final existingCard = deckCards[targetKey];

        if (existingCard == null) {
          final cardId = generateId();
          final ts = now + cardsImported;
          final cardMap = <String, Object?>{
            'id': cardId,
            'deck_id': deckId,
            'target_text': targetText,
            'association_text': associationText,
            'definition_text': definitionText,
            'page_number': pageNumber,
            'image_path': null,
            'image_placement': ImagePlacement.front.name,
            'status': CardStatus.learning.name,
            'status_changed_at': null,
            'created_at': ts,
            'updated_at': ts,
          };
          await txn.insert('flashcards', cardMap);
          deckCards[targetKey] = cardMap;
          cardsImported++;
        } else {
          final updates = <String, Object?>{};
          final oldDef =
              ((existingCard['definition_text'] as String?) ?? '').trim();
          if (oldDef != definitionText) {
            updates['definition_text'] = definitionText;
            existingCard['definition_text'] = definitionText;
          }
          if (associationText != null) {
            final oldAssoc =
                ((existingCard['association_text'] as String?) ?? '').trim();
            if (oldAssoc != associationText) {
              updates['association_text'] = associationText;
              existingCard['association_text'] = associationText;
            }
          }
          if (pageNumber != null) {
            final oldPage =
                ((existingCard['page_number'] as String?) ?? '').trim();
            if (oldPage != pageNumber) {
              updates['page_number'] = pageNumber;
              existingCard['page_number'] = pageNumber;
            }
          }
          if (updates.isNotEmpty) {
            final cardId = existingCard['id'] as String;
            updates['updated_at'] = now;
            await txn.update(
              'flashcards',
              updates,
              where: 'id = ?',
              whereArgs: [cardId],
            );
            cardsUpdated++;
          }
        }
      }

      return PresetImportResult(
        subjectId: subjectId,
        subjectName: preset.name,
        booksCount: bookIdByName.length,
        topicsCount: topicIdByKey.length,
        cardsImported: cardsImported,
        cardsUpdated: cardsUpdated,
      );
    });
  }

  /// Extracts a textbook page reference from `Col E` while ignoring date/time
  /// timestamps (such as `11.11.2026 10:05:35` in legacy rows).
  static String? _extractPageNumber(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    if (trimmed.contains(':') ||
        RegExp(r'\d{2}[./-]\d{2}[./-]\d{4}').hasMatch(trimmed)) {
      return null;
    }
    return trimmed;
  }

  /// RFC-4180 compliant CSV parser supporting quoted fields, escaped quotes,
  /// commas, and multiline cells.
  static List<List<String>> parseCsv(String input) {
    final rows = <List<String>>[];
    if (input.isEmpty) return rows;

    var currentRow = <String>[];
    final currentField = StringBuffer();
    var inQuotes = false;

    for (var i = 0; i < input.length; i++) {
      final ch = input[i];
      if (inQuotes) {
        if (ch == '"') {
          if (i + 1 < input.length && input[i + 1] == '"') {
            currentField.write('"');
            i++;
          } else {
            inQuotes = false;
          }
        } else {
          currentField.write(ch);
        }
      } else {
        if (ch == '"') {
          inQuotes = true;
        } else if (ch == ',') {
          currentRow.add(currentField.toString());
          currentField.clear();
        } else if (ch == '\r') {
          if (i + 1 < input.length && input[i + 1] == '\n') {
            i++;
          }
          currentRow.add(currentField.toString());
          currentField.clear();
          if (currentRow.any((cell) => cell.trim().isNotEmpty)) {
            rows.add(currentRow);
          }
          currentRow = <String>[];
        } else if (ch == '\n') {
          currentRow.add(currentField.toString());
          currentField.clear();
          if (currentRow.any((cell) => cell.trim().isNotEmpty)) {
            rows.add(currentRow);
          }
          currentRow = <String>[];
        } else {
          currentField.write(ch);
        }
      }
    }

    if (currentField.isNotEmpty || currentRow.isNotEmpty) {
      currentRow.add(currentField.toString());
      if (currentRow.any((cell) => cell.trim().isNotEmpty)) {
        rows.add(currentRow);
      }
    }

    return rows;
  }
}
