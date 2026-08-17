import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

import 'package:fern/models/review_log.dart';
import 'package:fern/services/deck_repository.dart';
import 'package:fern/models/word_card.dart';

/// Журнал занятий приходит не только из своего кода: он лежит в резервной
/// копии, которую человек может подсунуть чужую или битую. Экран «Прогресс»
/// не должен падать на кривом ключе дня.
void main() {
  test('битый ключ дня не роняет лучшую серию', () {
    final log = ReviewLog.fromJson({
      '2026-08-01': [3, 3],
      '2026-08-02': [4, 4],
      'вчера': [5, 5],
      '2026': [1, 1],
      '': [1, 1],
      '2026-13-99': [1, 1],
    });
    expect(log.bestStreak(), 2);
  });

  test('битый ключ не мешает считать сумму и дни', () {
    final log = ReviewLog.fromJson({
      '2026-08-01': [3, 2],
      'мусор': [10, 10],
    });
    expect(log.totalReviews, 3);
    expect(log.daysStudied, 1);
  });

  test('нормальные данные считаются как раньше', () {
    final log = ReviewLog.fromJson({
      '2026-08-01': [3, 3],
      '2026-08-02': [4, 4],
      '2026-08-03': [1, 1],
      '2026-08-09': [2, 2],
    });
    expect(log.bestStreak(), 3);
    expect(log.totalReviews, 10);
  });

  group('состояние карточки из чужого файла', () {
    test('номер состояния вне списка не роняет разбор', () {
      final st = ReviewState.fromJson({'state': 99, 'phase': 77});
      expect(st.state, FsrsState.newCard);
      expect(st.phase, LearnPhase.values.first);
    });

    test('отрицательные и бесконечные числа приводятся к разумным', () {
      final st = ReviewState.fromJson({
        's': -5,
        'd': 99,
        'reps': -3,
        'lapses': -1,
        'step': -2,
      });
      expect(st.stability >= 0, isTrue);
      expect(st.difficulty <= 10, isTrue);
      expect(st.reps >= 0, isTrue);
      expect(st.lapses >= 0, isTrue);
      expect(st.step >= 0, isTrue);
    });

    test('строка вместо даты не роняет разбор', () {
      final st = ReviewState.fromJson({'due': 'вчера', 'last': {}});
      expect(st.due, isNull);
      expect(st.lastReview, isNull);
    });

    test('обычные данные читаются как раньше', () {
      final src = ReviewState(
        stability: 12.5,
        difficulty: 6.25,
        state: FsrsState.review,
        reps: 4,
        lapses: 1,
        due: DateTime(2026, 8, 20),
        lastReview: DateTime(2026, 8, 1),
      );
      final back = ReviewState.fromJson(src.toJson());
      expect(back.stability, 12.5);
      expect(back.difficulty, 6.25);
      expect(back.state, FsrsState.review);
      expect(back.due, DateTime(2026, 8, 20));
    });
  });

  group('восстановление из подпорченного снимка', () {
    setUp(() async {
      await resetStorage();
      await DeckRepository.instance.init();
    });

    test('битая карточка не отменяет восстановление остальных', () async {
      final repo = DeckRepository.instance;
      await repo.importMap({
        'decks': [
          {
            'id': 'd1',
            'languageCode': 'en',
            'name': 'Колода',
            'color': 0xFF2E7D5B,
            'shape': 0,
            'createdAt': 1,
          },
          {'нет': 'id'},
        ],
        'cards': [
          {'id': 'c1', 'deckId': 'd1', 'front': 'a', 'back': 'а'},
          {'deckId': 'd1', 'front': 'без id', 'back': 'б'},
          {'id': 'c3', 'deckId': 'd1', 'front': 'c', 'back': 'в'},
        ],
      });

      final cards = await repo.loadCards();
      expect(cards.map((c) => c.id), containsAll(['c1', 'c3']));
      expect(cards.length, 2);
      expect((await repo.loadDecks()).length, 1);
    });
  });
}
