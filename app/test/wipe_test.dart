import 'package:flutter_test/flutter_test.dart';

import 'package:fern/models/deck.dart';
import 'package:fern/models/word_card.dart';
import 'package:fern/services/deck_repository.dart';

import 'test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final repo = DeckRepository.instance;

  setUp(resetStorage);

  test('удаление всех данных очищает колоды, карты, журнал и настройки',
      () async {
    await repo.init();
    await repo.upsertDeck(Deck(
      id: 'd1',
      languageCode: 'en',
      name: 'D',
      colorValue: 1,
      shapeIndex: 0,
      createdAt: 1,
    ));
    final card = WordCard(id: 'c1', deckId: 'd1', front: 'a', back: 'б');
    await repo.upsertCard(card);
    await repo.rateCard(card, Rating.good, DateTime(2026, 1, 1));
    await repo.setDailyGoal(55);

    expect((await repo.loadDecks()).isNotEmpty, true);
    expect(await repo.reviewEventCount(), greaterThan(0));

    await repo.wipeAllData();

    expect(await repo.loadDecks(), isEmpty);
    expect(await repo.loadCards(), isEmpty);
    expect(await repo.reviewEventCount(), 0);
    expect(repo.reviewLogSync.totalReviews, 0);
    expect(await repo.dailyGoal(), 20, reason: 'настройки вернулись к дефолту');
  });
}
