import 'dart:io';
import 'dart:math';

import 'package:anki_apk/data/database/app_database.dart';
import 'package:anki_apk/data/models/flashcard.dart';
import 'package:anki_apk/data/models/review_and_settings.dart';
import 'package:anki_apk/data/services/spaced_repetition.dart';
import 'package:anki_apk/ui/app_scope.dart';
import 'package:anki_apk/ui/deck_screen.dart';
import 'package:anki_apk/ui/strings.dart';
import 'package:anki_apk/ui/study_session_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  const scheduler = SpacedRepetitionScheduler();
  late AppDatabase db;
  late DateTime currentClock;

  setUp(() async {
    currentClock = DateTime.utc(2026, 10, 29, 10, 0);
    db = await AppDatabase.open(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfiNoIsolate,
      clock: () => currentClock,
    );
  });

  tearDown(() async {
    await db.close();
  });

  Future<({String subjectId, String deckId, Flashcard card})> seedSingleCard({
    String subjectName = 'Informatika',
    String deckName = 'Sózlik',
    String target = 'Algorithm',
  }) async {
    final s = await db.subjects.create(name: subjectName);
    final b = await db.books.create(subjectId: s.id, name: 'Kitap 1');
    final t = await db.topics.create(bookId: b.id, name: 'Tema 1');
    final d = await db.decks.create(topicId: t.id, name: deckName);
    final c = await db.flashcards.create(
      deckId: d.id,
      targetText: target,
      definitionText: 'Qádemler izbe-izligi',
    );
    return (subjectId: s.id, deckId: d.id, card: c);
  }

  group('deterministic spaced-repetition scheduler', () {
    test('schedules monotonic intervals (Qayta < Qıyın <= Jaqsı < Ańsat) and UTC dates',
        () {
      final localTime = DateTime(2026, 10, 29, 15, 30); // non-UTC input
      final rAgain = scheduler.schedule(
        rating: ReviewRating.again,
        reviewedAt: localTime,
      );
      final rHard = scheduler.schedule(
        rating: ReviewRating.hard,
        reviewedAt: localTime,
      );
      final rGood = scheduler.schedule(
        rating: ReviewRating.good,
        reviewedAt: localTime,
      );
      final rEasy = scheduler.schedule(
        rating: ReviewRating.easy,
        reviewedAt: localTime,
      );

      expect(rAgain.dueAt.isUtc, isTrue);
      expect(rAgain.intervalDays, 0);
      expect(rAgain.dueAt, localTime.toUtc().add(const Duration(minutes: 1)));
      expect(rAgain.easeFactor, closeTo(2.30, 0.001));

      expect(rHard.intervalDays, 1);
      expect(rHard.easeFactor, closeTo(2.35, 0.001));

      expect(rGood.intervalDays, 1);
      expect(rGood.easeFactor, closeTo(2.50, 0.001));

      expect(rEasy.intervalDays, 5);
      expect(rEasy.easeFactor, closeTo(2.65, 0.001));

      expect(rAgain.dueAt.isBefore(rHard.dueAt), isTrue);
      expect(!rHard.dueAt.isAfter(rGood.dueAt), isTrue);
      expect(rGood.dueAt.isBefore(rEasy.dueAt), isTrue);

      // Subsequent review from an existing 5-day interval
      final prev = ReviewEntry(
        id: 'prev',
        flashcardId: 'c1',
        reviewedAt: localTime.toUtc(),
        rating: ReviewRating.easy,
        dueAt: localTime.toUtc().add(const Duration(days: 5)),
        intervalDays: 5,
        easeFactor: 2.65,
      );
      final nextAgain = scheduler.schedule(
        rating: ReviewRating.again,
        reviewedAt: prev.dueAt!,
        previous: prev,
      );
      final nextHard = scheduler.schedule(
        rating: ReviewRating.hard,
        reviewedAt: prev.dueAt!,
        previous: prev,
      );
      final nextGood = scheduler.schedule(
        rating: ReviewRating.good,
        reviewedAt: prev.dueAt!,
        previous: prev,
      );
      final nextEasy = scheduler.schedule(
        rating: ReviewRating.easy,
        reviewedAt: prev.dueAt!,
        previous: prev,
      );

      expect(nextAgain.intervalDays, 0);
      expect(nextHard.intervalDays, greaterThan(0));
      expect(nextGood.intervalDays, greaterThan(nextHard.intervalDays));
      expect(nextEasy.intervalDays, greaterThan(nextGood.intervalDays));
    });
  });

  group('new-card eligibility, due-card prioritization, and status exclusion', () {
    test(
        'new cards are immediately eligible; due cards are prioritized; mastered and suspended are excluded',
        () async {
      final seeded = await seedSingleCard(target: 'NewCard');
      final dueCard = await db.flashcards.create(
        deckId: seeded.deckId,
        targetText: 'DueCard',
      );
      final futureCard = await db.flashcards.create(
        deckId: seeded.deckId,
        targetText: 'FutureCard',
      );
      final masteredCard = await db.flashcards.create(
        deckId: seeded.deckId,
        targetText: 'MasteredCard',
      );
      final suspendedCard = await db.flashcards.create(
        deckId: seeded.deckId,
        targetText: 'SuspendedCard',
      );

      await db.flashcards.setStatus(masteredCard.id, CardStatus.mastered);
      await db.flashcards.setStatus(suspendedCard.id, CardStatus.suspended);

      // Schedule DueCard in the past and FutureCard 5 days in the future
      final pastTime = currentClock.subtract(const Duration(days: 2));
      await db.reviews.recordScheduledReview(
        flashcardId: dueCard.id,
        rating: ReviewRating.good, // 1 day interval from 2 days ago => due yesterday
        sessionId: 'sess-past',
        reviewedAt: pastTime,
      );
      await db.reviews.recordScheduledReview(
        flashcardId: futureCard.id,
        rating: ReviewRating.easy, // 5 days from now => not yet due
        sessionId: 'sess-now',
        reviewedAt: currentClock,
      );

      // Normal eligible query excludes mastered & suspended, marks NewCard and DueCard as isDue
      final eligible = await db.flashcards.listEligibleByDeck(
        seeded.deckId,
        asOf: currentClock,
      );
      expect(
        eligible.map((e) => e.card.targetText).toList(),
        containsAll(['NewCard', 'DueCard', 'FutureCard']),
      );
      expect(
        eligible.map((e) => e.card.targetText),
        isNot(containsAll(['MasteredCard', 'SuspendedCard'])),
      );

      // Queue prioritizes due cards (NewCard & DueCard) ahead of FutureCard
      final queue = StudySessionQueue.fromPrioritized(
        eligible,
        random: Random(7),
      );
      expect(queue.steps, hasLength(3));
      final firstTwo =
          queue.steps.take(2).map((s) => s.card.targetText).toSet();
      expect(firstTwo, {'NewCard', 'DueCard'});
      expect(queue.steps.last.card.targetText, 'FutureCard');

      // Due-only query returns only NewCard and DueCard
      final dueOnly = await db.flashcards.listEligibleByDeck(
        seeded.deckId,
        asOf: currentClock,
        onlyDue: true,
      );
      expect(
        dueOnly.map((e) => e.card.targetText).toSet(),
        {'NewCard', 'DueCard'},
      );

      // Subject-level eligible query also excludes unrelated subjects and non-learning cards
      final other = await seedSingleCard(
        subjectName: 'Ximiya',
        deckName: 'Elementler',
        target: 'Kislorod',
      );
      final subjectEligible = await db.flashcards.listEligibleBySubject(
        seeded.subjectId,
        asOf: currentClock,
      );
      expect(
        subjectEligible.map((e) => e.card.targetText),
        isNot(contains(other.card.targetText)),
      );
    });

    test(
        'card rated Qayta (rating 1) has intervalDays 0 and becomes due again after 1 minute',
        () async {
      final seeded = await seedSingleCard(target: 'Recursion');
      final cardId = seeded.card.id;

      // Rate the card `Qayta` at t = 0
      final res = await db.reviews.recordScheduledReview(
        flashcardId: cardId,
        rating: ReviewRating.again,
        sessionId: 'sess-again-1',
        reviewedAt: currentClock,
      );
      expect(res.entry.intervalDays, 0);
      expect(
        res.entry.dueAt,
        currentClock.toUtc().add(const Duration(minutes: 1)),
      );

      // At t + 30 seconds (before 1 minute has elapsed), the card is not yet due
      final at30Sec = currentClock.add(const Duration(seconds: 30));
      final dueAt30Sec = await db.flashcards.listEligibleByDeck(
        seeded.deckId,
        asOf: at30Sec,
        onlyDue: true,
      );
      expect(dueAt30Sec, isEmpty);

      final allEligibleAt30Sec = await db.flashcards.listEligibleByDeck(
        seeded.deckId,
        asOf: at30Sec,
      );
      expect(allEligibleAt30Sec.single.isDue, isFalse);

      // At t + 1 minute, the card becomes due and is offered for study again
      final at1Min = currentClock.add(const Duration(minutes: 1));
      final dueAt1Min = await db.flashcards.listEligibleByDeck(
        seeded.deckId,
        asOf: at1Min,
        onlyDue: true,
      );
      expect(dueAt1Min, hasLength(1));
      expect(dueAt1Min.single.card.id, cardId);
      expect(dueAt1Min.single.isDue, isTrue);
      expect(dueAt1Min.single.lastIntervalDays, 0);

      final subjectDueAt1Min = await db.flashcards.listEligibleBySubject(
        seeded.subjectId,
        asOf: at1Min,
        onlyDue: true,
      );
      expect(subjectDueAt1Min.map((e) => e.card.id), contains(cardId));
    });
  });

  group('automatic mastery after 4 consecutive distinct Ańsat sessions', () {
    test('marks card mastered after 4 consecutive distinct Ańsat sessions',
        () async {
      final seeded = await seedSingleCard();
      final cardId = seeded.card.id;

      for (var i = 1; i <= 3; i++) {
        currentClock = currentClock.add(const Duration(days: 1));
        final res = await db.reviews.recordScheduledReview(
          flashcardId: cardId,
          rating: ReviewRating.easy,
          sessionId: 'session-$i',
        );
        expect(res.consecutiveEasySessions, i);
        expect(res.autoMastered, isFalse);
        expect(res.card.status, CardStatus.learning);
      }

      // 4th distinct session rated Ańsat -> auto-mastered!
      currentClock = currentClock.add(const Duration(days: 1));
      final fourth = await db.reviews.recordScheduledReview(
        flashcardId: cardId,
        rating: ReviewRating.easy,
        sessionId: 'session-4',
      );
      expect(fourth.consecutiveEasySessions, 4);
      expect(fourth.autoMastered, isTrue);
      expect(fourth.card.status, CardStatus.mastered);

      final persisted = (await db.flashcards.getById(cardId))!;
      expect(persisted.status, CardStatus.mastered);
      expect(await db.reviews.listForFlashcard(cardId), hasLength(4));
    });

    test('non-Ańsat rating resets the consecutive session counter', () async {
      final seeded = await seedSingleCard();
      final cardId = seeded.card.id;

      for (var i = 1; i <= 3; i++) {
        await db.reviews.recordScheduledReview(
          flashcardId: cardId,
          rating: ReviewRating.easy,
          sessionId: 's-$i',
        );
      }

      // Rated Jaqsı (good) in session 4 -> resets streak to 0
      final resetRes = await db.reviews.recordScheduledReview(
        flashcardId: cardId,
        rating: ReviewRating.good,
        sessionId: 's-4',
      );
      expect(resetRes.consecutiveEasySessions, 0);
      expect(resetRes.card.status, CardStatus.learning);

      // Next Ańsat is session 1 of the new streak, not 4
      final afterReset = await db.reviews.recordScheduledReview(
        flashcardId: cardId,
        rating: ReviewRating.easy,
        sessionId: 's-5',
      );
      expect(afterReset.consecutiveEasySessions, 1);
      expect(afterReset.autoMastered, isFalse);
    });

    test(
        'multiple reviews within the same session count at most once toward mastery',
        () async {
      final seeded = await seedSingleCard();
      final cardId = seeded.card.id;

      // 4 Ańsat records with the same sessionId must only count as 1 session
      for (var i = 0; i < 4; i++) {
        final res = await db.reviews.recordScheduledReview(
          flashcardId: cardId,
          rating: ReviewRating.easy,
          sessionId: 'same-session',
        );
        expect(res.consecutiveEasySessions, 1);
        expect(res.autoMastered, isFalse);
      }
      expect((await db.flashcards.getById(cardId))!.status, CardStatus.learning);
    });

    test(
        'manual reactivation preserves review history and requires 4 new sessions for auto-mastery',
        () async {
      final seeded = await seedSingleCard();
      final cardId = seeded.card.id;

      for (var i = 1; i <= 4; i++) {
        currentClock = currentClock.add(const Duration(minutes: 10));
        await db.reviews.recordScheduledReview(
          flashcardId: cardId,
          rating: ReviewRating.easy,
          sessionId: 's-$i',
        );
      }
      expect((await db.flashcards.getById(cardId))!.status, CardStatus.mastered);

      // Manually reactivate to learning
      currentClock = currentClock.add(const Duration(minutes: 10));
      final reactivated =
          await db.flashcards.setStatus(cardId, CardStatus.learning);
      expect(reactivated.status, CardStatus.learning);
      expect(await db.reviews.listForFlashcard(cardId), hasLength(4));

      // Next single Ańsat session starts streak at 1 (does not re-trigger old 4)
      currentClock = currentClock.add(const Duration(minutes: 10));
      final nextReview = await db.reviews.recordScheduledReview(
        flashcardId: cardId,
        rating: ReviewRating.easy,
        sessionId: 's-after-reactivate-1',
      );
      expect(nextReview.consecutiveEasySessions, 1);
      expect(nextReview.autoMastered, isFalse);
      expect(await db.reviews.listForFlashcard(cardId), hasLength(5));
    });
  });

  group('UI mastery controls and file persistence', () {
    testWidgets(
        '«Yad boldı» button above rating bar marks card mastered, removes it from session, and DeckScreen allows restoring to learning',
        (tester) async {
      final seeded = await seedSingleCard(target: 'Polymorphism');
      final deck = (await db.decks.getById(seeded.deckId))!;

      await tester.pumpWidget(
        AppScope(
          database: db,
          child: MaterialApp(
            home: StudySessionScreen.forDeck(
              deckId: deck.id,
              deckName: deck.name,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify «Yad boldı» button is visible above the 4 rating buttons
      expect(find.byKey(const Key('mark-mastered-button')), findsOneWidget);
      expect(find.text(S.markMastered), findsOneWidget);

      await tester.tap(find.byKey(const Key('mark-mastered-button')));
      await tester.pumpAndSettle();

      // Session finishes and card is persisted as mastered
      expect(find.byKey(const Key('study-complete-title')), findsOneWidget);
      expect(
        (await db.flashcards.getById(seeded.card.id))!.status,
        CardStatus.mastered,
      );

      // Open DeckScreen: verify status chip and restore card to learning via menu
      await tester.pumpWidget(
        AppScope(
          database: db,
          child: MaterialApp(home: DeckScreen(deck: deck)),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(Key('card-status-chip-${seeded.card.id}')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(Key('card-status-menu-${seeded.card.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(S.restoreToLearning));
      await tester.pumpAndSettle();

      expect(
        (await db.flashcards.getById(seeded.card.id))!.status,
        CardStatus.learning,
      );
    });

    test('mastery and consecutive session history survive closing and reopening DB',
        () async {
      final dir = Directory.systemTemp.createTempSync('anki_apk_sr_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final dbPath = p.join(dir.path, 'sr.db');

      final first = await AppDatabase.open(
        path: dbPath,
        factory: databaseFactoryFfiNoIsolate,
      );
      final s = await first.subjects.create(name: 'Tariyx');
      final b = await first.books.create(subjectId: s.id, name: '9-klass');
      final t = await first.topics.create(bookId: b.id, name: 'Tema');
      final d = await first.decks.create(topicId: t.id, name: 'Toplam');
      final c = await first.flashcards.create(deckId: d.id, targetText: 'Sana');

      // Complete 3 sessions before closing DB
      for (var i = 1; i <= 3; i++) {
        await first.reviews.recordScheduledReview(
          flashcardId: c.id,
          rating: ReviewRating.easy,
          sessionId: 'persisted-sess-$i',
        );
      }
      await first.close();

      // Reopen DB and complete the 4th session -> auto-mastered!
      final second = await AppDatabase.open(
        path: dbPath,
        factory: databaseFactoryFfiNoIsolate,
      );
      final fourth = await second.reviews.recordScheduledReview(
        flashcardId: c.id,
        rating: ReviewRating.easy,
        sessionId: 'persisted-sess-4',
      );
      expect(fourth.autoMastered, isTrue);
      await second.close();

      // Reopen third time to verify mastered status and exclusion from normal queue
      final third = await AppDatabase.open(
        path: dbPath,
        factory: databaseFactoryFfiNoIsolate,
      );
      addTearDown(third.close);
      expect((await third.flashcards.getById(c.id))!.status, CardStatus.mastered);
      expect(await third.flashcards.listEligibleByDeck(d.id), isEmpty);
    });
  });
}
