import 'package:flutter_test/flutter_test.dart';

import 'package:fern/models/deck.dart';
import 'package:fern/models/word_card.dart';
import 'package:fern/services/deck_repository.dart';

import 'test_helpers.dart';

/// Целостность хранилища: что переживает восстановление, удаление и повторную
/// запись, а что молча расходится.
Deck _deck(String id) => Deck(
      id: id,
      languageCode: 'en',
      name: id,
      colorValue: 0xFF2E7D5B,
      shapeIndex: 0,
      createdAt: 1,
    );

WordCard _card(String id, String deckId) =>
    WordCard(id: id, deckId: deckId, front: id, back: 'п-$id');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final repo = DeckRepository.instance;

  setUp(() async {
    await resetStorage();
    await repo.init();
  });

  test('полная замена из снимка уносит и старый журнал повторов', () async {
    await repo.upsertDeck(_deck('d1'));
    final card = _card('c1', 'd1');
    await repo.upsertCard(card);
    for (var i = 0; i < 5; i++) {
      await repo.rateCard(card, Rating.good, DateTime(2026, 1, 1 + i));
    }
    expect((await repo.reviewEvents()).length, 5);

    // Снимок с другого устройства: там своя карточка и своя история.
    final snapshot = {
      'version': 2,
      'decks': [_deck('d9').toJson()],
      'packs': [],
      'cards': [_card('x1', 'd9').toJson()],
    };
    await repo.importMap(snapshot);

    final events = await repo.reviewEvents();
    expect(events.where((e) => e.cardId == 'c1'), isEmpty,
        reason: 'оптимизатор считает такие события своими и учится на истории '
            'карточек, которых больше нет');
  });

  test('удаление колоды не оставляет карточек-сирот', () async {
    await repo.upsertDeck(_deck('d1'));
    await repo.addCards([_card('a', 'd1'), _card('b', 'd1')]);

    await repo.deleteDeck('d1');

    final all = await repo.loadCards();
    expect(all.where((c) => c.deckId == 'd1'), isEmpty);
  });

  test('повторное добавление той же карточки не двоит кэш', () async {
    await repo.upsertDeck(_deck('d1'));
    final card = _card('c1', 'd1');
    await repo.addCards([card]);
    await repo.addCards([card]);

    final inMemory = (await repo.loadCards()).where((c) => c.id == 'c1').length;
    expect(inMemory, 1,
        reason: 'база делает upsert по id, а кэш складывал вслепую — счётчики '
            'колоды врали до перезапуска');
  });

  test('счётчик подкреплений чтением переживает свой же снимок', () async {
    await repo.addReinforcedByReading(7);
    await repo.addReading(seconds: 100, words: 40);
    expect(repo.reinforcedByReading, 7);

    final snapshot = await repo.exportMap();
    await resetStorage();
    await repo.init();
    await repo.importMap(snapshot);

    expect(repo.reinforcedByReading, 7,
        reason: 'копится месяцами чтения, а терялось при восстановлении '
            'собственного снимка, снятого минуту назад');
  });
}
