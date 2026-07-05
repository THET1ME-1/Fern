import 'package:flutter_test/flutter_test.dart';

import 'package:fern/models/deck.dart';
import 'package:fern/models/pack.dart';
import 'package:fern/models/review_log.dart';
import 'package:fern/models/word_card.dart';
import 'package:fern/services/deck_repository.dart';

import 'test_helpers.dart';

void main() {
  group('ReviewLog', () {
    test('bestStreak и daysStudied', () {
      final log = ReviewLog({
        '2026-01-01': const DayStat(reviews: 5, correct: 4),
        '2026-01-02': const DayStat(reviews: 3, correct: 3),
        '2026-01-03': const DayStat(reviews: 2, correct: 1),
        // пропуск 04
        '2026-01-05': const DayStat(reviews: 1, correct: 1),
      });
      expect(log.bestStreak(), 3); // 01-02-03
      expect(log.daysStudied, 4);
      expect(log.totalReviews, 11);
    });

    test('пустой журнал', () {
      final log = ReviewLog.empty();
      expect(log.bestStreak(), 0);
      expect(log.daysStudied, 0);
    });
  });

  group('cardsForPack', () {
    final repo = DeckRepository.instance;
    setUp(() async {
      await resetStorage();
      await repo.init();
    });

    test('возвращает карты всех колод пака', () async {
      await repo.upsertPack(Pack(
        id: 'p1',
        languageCode: 'en',
        name: 'Пак',
        colorValue: 1,
        createdAt: 1,
      ));
      await repo.upsertDeck(Deck(
        id: 'd1',
        languageCode: 'en',
        name: 'A',
        colorValue: 1,
        shapeIndex: 0,
        createdAt: 1,
        packId: 'p1',
      ));
      await repo.upsertDeck(Deck(
        id: 'd2',
        languageCode: 'en',
        name: 'B',
        colorValue: 1,
        shapeIndex: 0,
        createdAt: 2,
        packId: 'p1',
      ));
      await repo.upsertDeck(Deck(
        id: 'd3',
        languageCode: 'en',
        name: 'C',
        colorValue: 1,
        shapeIndex: 0,
        createdAt: 3,
      )); // вне пака
      await repo.addCards([
        WordCard(id: 'c1', deckId: 'd1', front: 'a', back: '1'),
        WordCard(id: 'c2', deckId: 'd2', front: 'b', back: '2'),
        WordCard(id: 'c3', deckId: 'd3', front: 'c', back: '3'),
      ]);

      final cards = await repo.cardsForPack('p1');
      expect(cards.map((c) => c.front).toSet(), {'a', 'b'});
    });
  });
}
