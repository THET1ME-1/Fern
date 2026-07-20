import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart';

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

  test('база схемы v2 получает колонку времени ответа', () async {
    // Схема прошлой версии приложения: журнал повторов без `answer_ms`.
    final path = DeckRepository.debugDatabasePath!;
    final legacy = sqlite3.open(path);
    legacy.execute('''
      CREATE TABLE review_events (
        id           INTEGER PRIMARY KEY AUTOINCREMENT,
        card_id      TEXT NOT NULL,
        ts           INTEGER NOT NULL,
        grade        INTEGER NOT NULL,
        elapsed_days REAL NOT NULL,
        state_before INTEGER NOT NULL
      );
    ''');
    legacy.execute(
        'INSERT INTO review_events(card_id,ts,grade,elapsed_days,state_before) '
        "VALUES('old',1,3,0.0,0)");
    legacy.execute('PRAGMA user_version=2');
    legacy.dispose();

    await repo.init();
    final card = WordCard(id: 'c1', deckId: 'd1', front: 'a', back: 'б');
    await repo.upsertCard(card);
    await repo.rateCard(card, Rating.good, DateTime(2026, 1, 1), answerMs: 900);

    final events = await repo.reviewEvents();
    expect(events.length, 2, reason: 'прежние события не теряются');
    expect(events.firstWhere((e) => e.cardId == 'c1').answerMs, 900);
    expect(events.firstWhere((e) => e.cardId == 'old').answerMs, isNull);
  });
}
