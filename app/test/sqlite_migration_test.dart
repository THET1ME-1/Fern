import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fern/models/deck.dart';
import 'package:fern/models/word_card.dart';
import 'package:fern/services/deck_repository.dart';

import 'test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final repo = DeckRepository.instance;

  setUp(resetStorage);

  test('колоды и карты из prefs переносятся в SQLite на первом init', () async {
    final deck = Deck(
      id: 'leg',
      languageCode: 'en',
      name: 'Из прошлой версии',
      colorValue: 1,
      shapeIndex: 0,
      createdAt: 5,
    );
    // Карта с ненулевым прогрессом FSRS — проверяем, что состояние переносится.
    final card = WordCard(
      id: 'lc1',
      deckId: 'leg',
      front: 'sun',
      back: 'солнце',
      review: ReviewState(stability: 12.5, difficulty: 6, reps: 3),
    );
    SharedPreferences.setMockInitialValues({
      'decks': [jsonEncode(deck.toJson())],
      'cards': [jsonEncode(card.toJson())],
      'seededDemo': true,
    });
    repo.resetForTest();

    await repo.init();
    expect((await repo.loadDecks()).where((d) => d.id == 'leg').length, 1);
    final cards = await repo.cardsForDeck('leg');
    expect(cards.length, 1);
    expect(cards.first.review.reps, 3, reason: 'состояние FSRS не должно потеряться');
    expect(cards.first.review.stability, 12.5);
  });

  test('повторный запуск не дублирует перенесённые данные', () async {
    final deck = Deck(
      id: 'leg',
      languageCode: 'en',
      name: 'L',
      colorValue: 1,
      shapeIndex: 0,
      createdAt: 1,
    );
    SharedPreferences.setMockInitialValues({
      'decks': [jsonEncode(deck.toJson())],
      'cards': [
        jsonEncode(
            WordCard(id: 'lc1', deckId: 'leg', front: 'a', back: 'б').toJson()),
      ],
      'seededDemo': true,
    });
    repo.resetForTest();
    await repo.init();

    // «Перезапуск» приложения: кэш и соединение сброшены, файл БД остаётся.
    repo.resetForTest();
    await repo.init();

    expect((await repo.cardsForDeck('leg')).length, 1,
        reason: 'миграция одноразовая — дублей быть не должно');
    expect((await repo.loadDecks()).where((d) => d.id == 'leg').length, 1);
  });
}
