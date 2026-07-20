import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fern/models/deck.dart';
import 'package:fern/models/word_card.dart';
import 'package:fern/services/deck_repository.dart';

import 'test_helpers.dart';

void main() {
  // Нужно, чтобы seedDemoIfNeeded мог читать ассет колод по умолчанию.
  TestWidgetsFlutterBinding.ensureInitialized();
  final repo = DeckRepository.instance;

  setUp(resetStorage);

  Deck deckOf(String id, {String name = 'D'}) => Deck(
        id: id,
        languageCode: 'en',
        name: name,
        colorValue: 0xFF2E7D5B,
        shapeIndex: 0,
        createdAt: 1,
      );

  test('upsertDeck persists and reloads', () async {
    await repo.upsertDeck(deckOf('d1', name: 'My deck'));
    final decks = await repo.loadDecks();
    expect(decks.where((d) => d.id == 'd1').length, 1);
    expect(decks.firstWhere((d) => d.id == 'd1').name, 'My deck');
  });

  test('upsertCard persists and reloads for deck', () async {
    final card = WordCard(id: 'c1', deckId: 'd1', front: 'hi', back: 'привет');
    await repo.upsertCard(card);
    final cards = await repo.cardsForDeck('d1');
    expect(cards.length, 1);
    expect(cards.first.front, 'hi');
  });

  test('re-seed does not wipe user deck', () async {
    // Посев ждёт выбранного языка изучения — в тестах отмечаем
    // онбординг пройденным.
    await DeckRepository.instance.setOnboarded(true);
    await repo.seedDemoIfNeeded();
    await repo.upsertDeck(deckOf('mine', name: 'Mine'));
    // Посев ждёт выбранного языка изучения — в тестах отмечаем
    // онбординг пройденным.
    await DeckRepository.instance.setOnboarded(true);
    await repo.seedDemoIfNeeded();
    final after = await repo.loadDecks();
    expect(after.where((d) => d.id == 'mine').length, 1);
  });

  test('данные переживают перезапуск (кэш сброшен, стор сохранён)', () async {
    // Пользователь добавил колоду и карту...
    await repo.upsertDeck(deckOf('keep', name: 'Keep me'));
    await repo.upsertCard(
        WordCard(id: 'k1', deckId: 'keep', front: 'sun', back: 'солнце'));

    // ...и «убил» приложение: кэш пропал, но надёжный стор остался.
    repo.resetForTest();

    // Свежий запуск заново поднимает данные из стора.
    await repo.init();
    final decks = await repo.loadDecks();
    final cards = await repo.cardsForDeck('keep');
    expect(decks.where((d) => d.id == 'keep').length, 1,
        reason: 'колода должна пережить перезапуск');
    expect(cards.where((c) => c.id == 'k1').length, 1,
        reason: 'карта должна пережить перезапуск');
  });

  test('рекорд «Подбор» сохраняется и только улучшается', () async {
    expect(await repo.recordMatchMillis('d1', 5000), true); // первый — рекорд
    expect(repo.bestMatchMillis('d1'), 5000);
    expect(await repo.recordMatchMillis('d1', 6000), false); // хуже — не рекорд
    expect(repo.bestMatchMillis('d1'), 5000);
    expect(await repo.recordMatchMillis('d1', 4000), true); // лучше — рекорд
    expect(repo.bestMatchMillis('d1'), 4000);
  });

  test('данные из старого стора мигрируют на первом init', () async {
    // Старая (legacy) установка: данные лежат в SharedPreferences, флага
    // миграции ещё нет.
    final legacyDeck = Deck(
      id: 'legacy',
      languageCode: 'en',
      name: 'Из прошлой версии',
      colorValue: 0xFF3F6FB0,
      shapeIndex: 1,
      createdAt: 5,
    );
    SharedPreferences.setMockInitialValues({
      'decks': [jsonEncode(legacyDeck.toJson())],
      'seededDemo': true,
      'dailyGoal': 42,
    });
    repo.resetForTest();

    await repo.init();
    final decks = await repo.loadDecks();
    expect(decks.where((d) => d.id == 'legacy').length, 1,
        reason: 'старая колода должна подтянуться в новый стор');
    expect(await repo.dailyGoal(), 42,
        reason: 'старые настройки не должны потеряться');
  });
}
