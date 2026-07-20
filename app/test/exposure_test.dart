import 'package:flutter_test/flutter_test.dart';

import 'package:fern/models/deck.dart';
import 'package:fern/models/fsrs.dart';
import 'package:fern/models/word_card.dart';
import 'package:fern/services/deck_repository.dart';
import 'package:fern/services/exposure_service.dart';

import 'test_helpers.dart';

/// Карта в зрелом состоянии: повторена [daysAgo] дней назад со стабильностью [s].
WordCard _mature(
  String id,
  String front, {
  double s = 10,
  int daysAgo = 8,
  DateTime? now,
}) {
  final at = (now ?? DateTime.now()).subtract(Duration(days: daysAgo));
  return WordCard(
    id: id,
    deckId: 'd1',
    front: front,
    back: 'перевод',
    review: ReviewState(
      stability: s,
      difficulty: 5,
      state: FsrsState.review,
      reps: 3,
      lastReview: at,
      due: at.add(Duration(days: s.round())),
    ),
  );
}

Deck _deck() => Deck(
      id: 'd1',
      languageCode: 'en',
      name: 'D',
      colorValue: 0xFF2E7D5B,
      shapeIndex: 0,
      createdAt: 1,
    );

void main() {
  final repo = DeckRepository.instance;
  final fsrs = Fsrs.instance;

  group('Пассивная встреча в тексте', () {
    test('подзабытому слову прибавляет стабильность', () {
      final now = DateTime(2026, 7, 20);
      final card = _mature('c1', 'bright', s: 10, daysAgo: 20, now: now);
      final before = card.review.stability;

      final next = fsrs.passiveExposure(card.review, now);
      expect(next, isNotNull);
      expect(next!.stability, greaterThan(before));
      expect(next.lastSeen, now);
      expect(next.reps, card.review.reps,
          reason: 'встреча в тексте — не повтор, счётчик не растёт');
    });

    test('свежему в памяти слову не даёт ничего', () {
      final now = DateTime(2026, 7, 20);
      final card = _mature('c1', 'bright', s: 30, daysAgo: 1, now: now);
      expect(fsrs.passiveExposure(card.review, now), isNull);
    });

    test('новую карту не трогает', () {
      final card = WordCard(id: 'c1', deckId: 'd1', front: 'x', back: 'ы');
      expect(fsrs.passiveExposure(card.review, DateTime.now()), isNull);
    });

    test('вторая встреча в тот же день проходит мимо', () {
      final now = DateTime(2026, 7, 20);
      final card = _mature('c1', 'bright', s: 10, daysAgo: 20, now: now);
      final first = fsrs.passiveExposure(card.review, now)!;
      expect(
        fsrs.passiveExposure(first, now.add(const Duration(hours: 3))),
        isNull,
        reason: 'одна книга не должна подкармливать карту весь вечер',
      );
    });

    test('прибавка скромнее настоящего повтора', () {
      final now = DateTime(2026, 7, 20);
      final card = _mature('c1', 'bright', s: 10, daysAgo: 20, now: now);

      final passive = fsrs.passiveExposure(card.review, now)!;
      final real = fsrs.review(card.review, Rating.good, now, fuzz: false);

      expect(passive.stability, lessThan(real.stability),
          reason: 'узнать слово в тексте легче, чем вспомнить по карточке');
    });

    test('отметка встречи переживает сериализацию', () {
      final now = DateTime(2026, 7, 20);
      final card = _mature('c1', 'bright', s: 10, daysAgo: 20, now: now);
      card.review = fsrs.passiveExposure(card.review, now)!;

      final restored = WordCard.fromJson(card.toJson());
      expect(restored.review.lastSeen, now);
    });
  });

  group('Сведение прочитанного со словарём', () {
    setUp(() async {
      await resetStorage();
      await repo.init();
      await repo.upsertDeck(_deck());
    });

    test('находит карточку по словоформе из текста', () async {
      final now = DateTime(2026, 7, 20);
      await repo.upsertCard(_mature('c1', 'cat', s: 10, daysAgo: 20, now: now));

      final n = await ExposureService.record(['cats', 'ran'], 'en', now: now);
      expect(n, 1, reason: '«cats» на странице должно найти карточку «cat»');
      expect(repo.reinforcedByReading, 1);
    });

    test('слова не из словаря ничего не ломают', () async {
      final now = DateTime(2026, 7, 20);
      await repo.upsertCard(_mature('c1', 'cat', s: 10, daysAgo: 20, now: now));
      expect(await ExposureService.record(['zebra'], 'en', now: now), 0);
    });

    test('чужой язык не задевается', () async {
      final now = DateTime(2026, 7, 20);
      await repo.upsertCard(_mature('c1', 'cat', s: 10, daysAgo: 20, now: now));
      expect(await ExposureService.record(['cat'], 'es', now: now), 0);
    });

    test('прибавка доезжает до хранилища', () async {
      final now = DateTime(2026, 7, 20);
      await repo.upsertCard(_mature('c1', 'cat', s: 10, daysAgo: 20, now: now));
      final before = (await repo.cardsForDeck('d1')).single.review.stability;

      await ExposureService.record(['cat'], 'en', now: now);

      final after = (await repo.cardsForDeck('d1')).single;
      expect(after.review.stability, greaterThan(before));
      expect(after.review.lastSeen, isNotNull);
    });
  });
}
