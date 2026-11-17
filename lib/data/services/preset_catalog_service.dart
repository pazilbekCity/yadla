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
    required this.topicsGid,
    required this.answersGid,
  });

  final String id;
  final String name;
  final String description;
  final String spreadsheetId;
  final String topicsGid;
  final String answersGid;

  Uri get topicsCsvUri => Uri.parse(
        'https://docs.google.com/spreadsheets/d/$spreadsheetId/export?format=csv&gid=$topicsGid',
      );

  Uri get answersCsvUri => Uri.parse(
        'https://docs.google.com/spreadsheets/d/$spreadsheetId/export?format=csv&gid=$answersGid',
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

  /// Registered preset subjects available for one-tap download.
  static const List<PresetSubjectDefinition> availablePresets = [
    PresetSubjectDefinition(
      id: 'informatika',
      name: 'Informatika',
      description: '5–11-klass Informatika hám AT sabaqlıqları boyınsha smart kartalar',
      spreadsheetId: '1RaSNsKj74uRSk1X2qBBwHZGV46KbOWysOAjomZKqzsU',
      topicsGid: '0',
      answersGid: '623643907',
    ),
  ];

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
        return utf8.decode(bytes, allowMalformed: true);
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

    return importFromCsvStrings(
      db: db,
      preset: preset,
      topicsCsv: topicsCsv,
      answersCsv: answersCsv,
    );
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

      // 1. Find or create Subject
      final existingSubjects = await txn.query(
        'subjects',
        where: ' LOWER(TRIM(name)) = ? ',
        whereArgs: [preset.name.trim().toLowerCase()],
        limit: 1,
      );
      final String subjectId;
      if (existingSubjects.isNotEmpty) {
        subjectId = existingSubjects.first['id'] as String;
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
          columns: ['id', 'target_text', 'definition_text', 'association_text'],
          where: 'deck_id = ?',
          whereArgs: [deckId],
        );
        final map = <String, Map<String, Object?>>{};
        for (final r in rows) {
          final target = (r['target_text'] as String).trim().toLowerCase();
          final def =
              ((r['definition_text'] as String?) ?? '').trim().toLowerCase();
          map['$target\u0000$def'] = r;
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

        final rawAssociation = row.length > 6 ? row[6].trim() : '';
        final associationText =
            rawAssociation.isEmpty ? null : rawAssociation;

        final bookId = await ensureBook(klass);
        final topicId = await ensureTopic(bookId, tema);
        final deckId = await ensureDeck(topicId, tema);
        final deckCards = await getDeckCardsMap(deckId);

        final dedupKey =
            '${targetText.toLowerCase()}\u0000${definitionText.toLowerCase()}';
        final existingCard = deckCards[dedupKey];

        if (existingCard == null) {
          final cardId = generateId();
          final ts = now + cardsImported;
          final cardMap = <String, Object?>{
            'id': cardId,
            'deck_id': deckId,
            'target_text': targetText,
            'association_text': associationText,
            'definition_text': definitionText,
            'image_path': null,
            'image_placement': ImagePlacement.front.name,
            'status': CardStatus.learning.name,
            'status_changed_at': null,
            'created_at': ts,
            'updated_at': ts,
          };
          await txn.insert('flashcards', cardMap);
          deckCards[dedupKey] = cardMap;
          cardsImported++;
        } else if (associationText != null) {
          final oldAssoc =
              ((existingCard['association_text'] as String?) ?? '').trim();
          if (oldAssoc.isEmpty) {
            final cardId = existingCard['id'] as String;
            await txn.update(
              'flashcards',
              {
                'association_text': associationText,
                'updated_at': now,
              },
              where: 'id = ?',
              whereArgs: [cardId],
            );
            existingCard['association_text'] = associationText;
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
