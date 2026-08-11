import 'package:flutter_test/flutter_test.dart';

import 'package:fern/models/deck.dart';
import 'package:fern/models/word_card.dart';
import 'package:fern/services/deck_repository.dart';
import 'package:fern/services/quick_review.dart';

import 'test_helpers.dart';

void main() {
  final repo = DeckRepository.instance;

  setUp(() async {
    await resetStorage();
    await repo.init();
    await repo.upsertDeck(Deck(
      id: 'd1',
      languageCode: 'en',
      name: 'EN',
      colorValue: 0xFF2E7D5B,
      shapeIndex: 0,
      createdAt: 1,
    ));
  });

  test('ответ из шторки копится в очереди и применяется один раз', () async {
    await repo.upsertCard(WordCard(
      id: 'c1',
      deckId: 'd1',
      front: 'house',
      back: 'дом',
    ));

    await QuickReview.enqueue('c1', true);
    expect(await QuickReview.applyPending(), 1);

    final cards = await repo.loadCards();
    final card = cards.firstWhere((c) => c.id == 'c1');
    expect(card.review.reps, 1, reason: 'оценка дошла до планировщика');
    expect(card.review.due, isNotNull);

    // Очередь очищена: второй запуск ничего не применяет заново.
    expect(await QuickReview.applyPending(), 0);
    final again = (await repo.loadCards()).firstWhere((c) => c.id == 'c1');
    expect(again.review.reps, 1);
  });

  test('ответ по исчезнувшей карточке пропускается молча', () async {
    await QuickReview.enqueue('нет такой карточки', false);
    expect(await QuickReview.applyPending(), 0);
  });

  test('«не помню» и «помню» дают разные оценки', () async {
    await repo.upsertCard(WordCard(
      id: 'c1', deckId: 'd1', front: 'a', back: 'а'));
    await repo.upsertCard(WordCard(
      id: 'c2', deckId: 'd1', front: 'b', back: 'б'));

    await QuickReview.enqueue('c1', true);
    await QuickReview.enqueue('c2', false);
    expect(await QuickReview.applyPending(), 2);

    final cards = await repo.loadCards();
    final known = cards.firstWhere((c) => c.id == 'c1');
    final forgot = cards.firstWhere((c) => c.id == 'c2');
    expect(known.review.stability, greaterThan(forgot.review.stability));
  });
}
