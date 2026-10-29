import 'dart:math';

import 'package:anki_apk/data/database/app_database.dart';
import 'package:anki_apk/data/models/flashcard.dart';
import 'package:anki_apk/data/models/review_and_settings.dart';
import 'package:anki_apk/main.dart';
import 'package:anki_apk/ui/app_scope.dart';
import 'package:anki_apk/ui/strings.dart';
import 'package:anki_apk/ui/study_session_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  late AppDatabase db;

  setUp(() async {
    db = await AppDatabase.open(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfiNoIsolate,
    );
  });

  tearDown(() async {
    await db.close();
  });

  Future<
      ({
        String subject1Id,
        String deck1AId,
        String deck1BId,
        String subject2Id,
        String deck2Id,
        List<Flashcard> deck1ACards,
        List<Flashcard> deck1BCards,
        List<Flashcard> deck2Cards,
      })> seedTwoSubjects() async {
    final s1 = await db.subjects.create(name: 'Informatika');
    final b1 = await db.books.create(subjectId: s1.id, name: '8-klass');
    final t1 = await db.topics.create(bookId: b1.id, name: 'MS Office');
    final d1a = await db.decks.create(topicId: t1.id, name: 'Word');
    final d1b = await db.decks.create(topicId: t1.id, name: 'Excel');

    final b1extra = await db.books.create(subjectId: s1.id, name: '9-klass');
    final t1extra =
        await db.topics.create(bookId: b1extra.id, name: 'Python');
    final d1c = await db.decks.create(topicId: t1extra.id, name: 'Sintaksis');

    final s2 = await db.subjects.create(name: 'Biologiya');
    final b2 = await db.books.create(subjectId: s2.id, name: 'Botanika');
    final t2 = await db.topics.create(bookId: b2.id, name: 'Ósimlikler');
    final d2 = await db.decks.create(topicId: t2.id, name: 'Tamır');

    final c1 = await db.flashcards.create(
      deckId: d1a.id,
      targetText: 'Ribbon',
      associationText: 'Joqarǵı lenta',
      definitionText: 'Buyrıqlar paneli',
    );
    final c2 = await db.flashcards.create(
      deckId: d1a.id,
      targetText: 'Clipboard',
      associationText: 'Almasıw buferi',
      definitionText: 'Kóshirilgen maǵlıwmat saqlanatuǵın orın',
    );
    final c3 = await db.flashcards.create(
      deckId: d1b.id,
      targetText: 'Cell',
      associationText: 'Kletka',
      definitionText: 'Keste yacheykası',
    );
    final c4 = await db.flashcards.create(
      deckId: d1c.id,
      targetText: 'Loop',
      associationText: 'Qaytalaw',
      definitionText: 'Cikl operatorı',
    );
    final cOther = await db.flashcards.create(
      deckId: d2.id,
      targetText: 'Fotosintez',
      definitionText: 'Jaqtılıq járdeminde organikalıq zat payda bolıwı',
    );

    return (
      subject1Id: s1.id,
      deck1AId: d1a.id,
      deck1BId: d1b.id,
      subject2Id: s2.id,
      deck2Id: d2.id,
      deck1ACards: [c1, c2],
      deck1BCards: [c3, c4],
      deck2Cards: [cOther],
    );
  }

  group('card selection and shuffling', () {
    test('deck and subject selection never include unrelated cards', () async {
      final data = await seedTwoSubjects();

      final deckCards = await db.flashcards.listByDeck(data.deck1AId);
      expect(
        deckCards.map((c) => c.targetText).toSet(),
        {'Ribbon', 'Clipboard'},
      );

      final subject1Cards = await db.flashcards.listBySubject(data.subject1Id);
      expect(
        subject1Cards.map((c) => c.targetText).toSet(),
        {'Ribbon', 'Clipboard', 'Cell', 'Loop'},
      );
      expect(
        subject1Cards.map((c) => c.targetText),
        isNot(contains('Fotosintez')),
      );
    });

    test('StudySessionQueue shuffles initial cards and caps repetitions finitely',
        () async {
      final data = await seedTwoSubjects();
      final all = [...data.deck1ACards, ...data.deck1BCards];

      final q = StudySessionQueue(
        all,
        random: Random(42),
        maxRequeuesPerCard: 2,
      );
      expect(q.totalUniqueCards, 4);
      expect(q.remainingQueueCount, 4);

      // Rate first card `Qayta` (again) repeatedly -> should only be requeued
      // maxRequeuesPerCard (2) times (total 3 appearances), never looping forever.
      var safetyCounter = 0;
      while (!q.isCompleted) {
        safetyCounter++;
        expect(safetyCounter, lessThanOrEqualTo(15));
        expect(q.recordRating(ReviewRating.again), isTrue);
      }
      // 4 cards * (1 initial + 2 requeues) = 12 total steps max
      expect(q.totalReviewsCompleted, 12);
      expect(q.completedUniqueCount, 4);
      expect(q.remainingQueueCount, 0);
    });
  });

  group('study session UI, ratings, persistence, and navigation', () {
    testWidgets(
        'four rating buttons map to 1..4, persist to review_history without fake scheduling, and advance through session',
        (tester) async {
      final s = await db.subjects.create(name: 'Informatika');
      final b = await db.books.create(subjectId: s.id, name: '8-klass');
      final t = await db.topics.create(bookId: b.id, name: 'Word');
      final d = await db.decks.create(topicId: t.id, name: 'Sózlik');

      final c1 = await db.flashcards.create(
        deckId: d.id,
        targetText: 'Sóz 1',
        associationText: 'Assotsiaciya 1',
        definitionText: 'Anıqlama 1',
      );
      final c2 = await db.flashcards.create(
        deckId: d.id,
        targetText: 'Sóz 2',
        associationText: 'Assotsiaciya 2',
        definitionText: 'Anıqlama 2',
      );

      await tester.pumpWidget(
        AppScope(
          database: db,
          child: MaterialApp(
            home: StudySessionScreen.forDeck(
              deckId: d.id,
              deckName: d.name,
              random: Random(1),
              maxRequeuesPerCard: 1,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify Anki-style 4 rating labels and initial interval captions
      expect(find.text(S.rateAgain), findsOneWidget);
      expect(find.text(S.intervalAgain), findsOneWidget);
      expect(find.text(S.rateHard), findsOneWidget);
      expect(find.text(S.intervalHard), findsOneWidget);
      expect(find.text(S.rateGood), findsOneWidget);
      expect(find.text(S.intervalGood), findsOneWidget);
      expect(find.text(S.rateEasy), findsOneWidget);
      expect(find.text(S.intervalEasy), findsOneWidget);

      // Definition is hidden initially, revealed on tap
      expect(find.byKey(const Key('study-definition-card')), findsNothing);
      await tester.tap(find.byKey(const Key('study-toggle-definition')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('study-definition-card')), findsOneWidget);

      // Tap `Qayta` (1) on first card -> card stays in queue (requeued once)
      await tester.tap(find.byKey(const Key('rate-again')));
      await tester.pumpAndSettle();

      // Tap `Qıyın` (2) on second card -> also requeued once
      await tester.tap(find.byKey(const Key('rate-hard')));
      await tester.pumpAndSettle();

      // Navigate back to previous card and verify session progress is preserved
      // and historical card cannot be rated a second time
      expect(find.byKey(const Key('study-progress')), findsOneWidget);
      await tester.tap(find.byKey(const Key('study-prev-card')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('study-already-rated')), findsOneWidget);
      expect(find.byKey(const Key('rate-good')), findsNothing);

      // Return to active card
      await tester.tap(find.byKey(const Key('study-next-card')));
      await tester.pumpAndSettle();

      // Rate the two requeued cards as `Jaqsı` (3) and `Ańsat` (4)
      await tester.tap(find.byKey(const Key('rate-good')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('rate-easy')));
      await tester.pumpAndSettle();

      // Session is now complete
      expect(find.byKey(const Key('study-complete-title')), findsOneWidget);
      expect(find.text(S.sessionCompleteTitle), findsOneWidget);

      // Verify review_history persistence and rating values (1, 2, 3, 4)
      final r1 = await db.reviews.listForFlashcard(c1.id);
      final r2 = await db.reviews.listForFlashcard(c2.id);
      expect(r1.length + r2.length, 4);

      final allRatings = [...r1, ...r2].map((r) => r.rating.value).toSet();
      expect(allRatings, {1, 2, 3, 4});

      // Verify calculated scheduling fields are persisted in UTC with sessionId
      for (final entry in [...r1, ...r2]) {
        expect(entry.dueAt, isNotNull);
        expect(entry.dueAt!.isUtc, isTrue);
        expect(entry.intervalDays, isNotNull);
        expect(entry.easeFactor, isNotNull);
        expect(entry.sessionId, isNotEmpty);
      }
    });

    testWidgets('duplicate button taps save review only once', (tester) async {
      final s = await db.subjects.create(name: 'Matematika');
      final b = await db.books.create(subjectId: s.id, name: 'Algebra');
      final t = await db.topics.create(bookId: b.id, name: 'Teńlemeler');
      final d = await db.decks.create(topicId: t.id, name: 'Kvadrat');
      final c = await db.flashcards.create(
        deckId: d.id,
        targetText: 'Diskriminant',
        definitionText: 'D = b^2 - 4ac',
      );

      await tester.pumpWidget(
        AppScope(
          database: db,
          child: MaterialApp(
            home: StudySessionScreen.forDeck(
              deckId: d.id,
              deckName: d.name,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap `Jaqsı` twice in the same frame before rebuild settles
      final goodBtn = find.byKey(const Key('rate-good'));
      await tester.tap(goodBtn);
      await tester.tap(goodBtn, warnIfMissed: false);
      await tester.pumpAndSettle();

      final reviews = await db.reviews.listForFlashcard(c.id);
      expect(reviews, hasLength(1));
      expect(reviews.single.rating, ReviewRating.good);
    });

    testWidgets(
        'empty deck and empty subject study entry points show Karakalpak message without crashing',
        (tester) async {
      final s = await db.subjects.create(name: 'Fizika');
      final b = await db.books.create(subjectId: s.id, name: '7-klass');
      final t = await db.topics.create(bookId: b.id, name: 'Mexanika');
      await db.decks.create(topicId: t.id, name: 'Bos toplam');

      await tester.pumpWidget(AnkiApp(openDatabase: () async => db));
      await tester.pumpAndSettle();

      // Enter Subject -> tap Study Subject button
      await tester.tap(find.text('Fizika'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('study-subject-button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('study-empty')), findsOneWidget);
      expect(find.text(S.studyEmpty), findsOneWidget);
      await tester.tap(find.text(S.finishSession));
      await tester.pumpAndSettle();

      // Navigate into Book -> Topic -> Empty Deck -> tap Study Deck button
      await tester.tap(find.text('7-klass'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mexanika'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bos toplam'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('study-deck-button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('study-empty')), findsOneWidget);
    });
  });
}
