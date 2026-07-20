import 'package:flutter_test/flutter_test.dart';

import 'package:fern/models/deck.dart';
import 'package:fern/models/word_card.dart';
import 'package:fern/services/deck_repository.dart';
import 'package:fern/services/link_propagation.dart';
import 'package:fern/services/word_links.dart';

import 'test_helpers.dart';

WordCard _mature(String id, String front, String back, {double s = 20}) {
  final at = DateTime(2026, 7, 1);
  return WordCard(
    id: id,
    deckId: 'd1',
    front: front,
    back: back,
    review: ReviewState(
      stability: s,
      difficulty: 5,
      state: FsrsState.review,
      reps: 4,
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
  final now = DateTime(2026, 7, 20);

  group('Перенос сомнения по связям', () {
    test('однокоренного соседа спрашиваем раньше', () {
      final bright = _mature('c1', 'bright', 'яркий');
      final brightness = _mature('c2', 'brightness', 'яркость');
      final dueBefore = brightness.review.due;

      final touched =
          LinkPropagation.afterLapse(bright, [bright, brightness], 'en', now: now);

      expect(touched.single.id, 'c2');
      expect(brightness.review.stability, lessThan(20));
      expect(brightness.review.due!.isBefore(dueBefore!), true);
    });

    test('несвязанные слова не задевает', () {
      final bright = _mature('c1', 'bright', 'яркий');
      final table = _mature('c2', 'table', 'стол');
      expect(
        LinkPropagation.afterLapse(bright, [bright, table], 'en', now: now),
        isEmpty,
      );
    });

    test('на антонимы сомнение не переносится', () {
      final bright = _mature('c1', 'bright', 'яркий');
      final dark = _mature('c2', 'dark', 'тёмный');
      WordLinks.connect(bright, dark, LinkKind.antonym);

      expect(
        LinkPropagation.afterLapse(bright, [bright, dark], 'en', now: now),
        isEmpty,
        reason: 'знание «dark» не держится на знании «bright»',
      );
    });

    test('новую карту не трогает', () {
      final bright = _mature('c1', 'bright', 'яркий');
      final fresh = WordCard(id: 'c2', deckId: 'd1', front: 'shiny', back: 'яркий');
      expect(
        LinkPropagation.afterLapse(bright, [bright, fresh], 'en', now: now),
        isEmpty,
      );
    });

    test('срок только приближается, но не отодвигается', () {
      final bright = _mature('c1', 'bright', 'яркий');
      final shiny = _mature('c2', 'shiny', 'яркий', s: 20);
      // Соседу и так пора — сомнение не должно отложить его повтор.
      shiny.review.due = DateTime(2026, 7, 2);

      LinkPropagation.afterLapse(bright, [bright, shiny], 'en', now: now);
      expect(shiny.review.due, DateTime(2026, 7, 2));
    });
  });

  test('срыв на оценке доходит до соседей через репозиторий', () async {
    await resetStorage();
    await repo.init();
    await repo.upsertDeck(_deck());
    final bright = _mature('c1', 'bright', 'яркий');
    final brightness = _mature('c2', 'brightness', 'яркость');
    await repo.upsertCard(bright);
    await repo.upsertCard(brightness);

    await repo.rateCard(bright, Rating.again, now);

    final stored = (await repo.cardsForDeck('d1')).firstWhere((c) => c.id == 'c2');
    expect(stored.review.stability, lessThan(20),
        reason: 'сосед по корню должен ослабнуть вместе со словом',
    );
  });

  test('верный ответ соседей не трогает', () async {
    await resetStorage();
    await repo.init();
    await repo.upsertDeck(_deck());
    final bright = _mature('c1', 'bright', 'яркий');
    final brightness = _mature('c2', 'brightness', 'яркость');
    await repo.upsertCard(bright);
    await repo.upsertCard(brightness);

    await repo.rateCard(bright, Rating.good, now);

    final stored = (await repo.cardsForDeck('d1')).firstWhere((c) => c.id == 'c2');
    expect(stored.review.stability, 20,
        reason: 'успех соседа ничего не отодвигает — перенос идёт в одну сторону');
  });
}
