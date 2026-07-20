import 'package:flutter_test/flutter_test.dart';

import 'package:fern/models/word_card.dart';
import 'package:fern/services/interference.dart';
import 'package:fern/study/study_models.dart';

WordCard _c(String id, String front, String back) =>
    WordCard(id: id, deckId: 'd1', front: front, back: back);

WordCard _learning(String id, String front, String back) => WordCard(
      id: id,
      deckId: 'd1',
      front: front,
      back: back,
      review: ReviewState(
        stability: 0.5,
        difficulty: 5,
        state: FsrsState.learning,
        reps: 1,
        lastReview: DateTime.now().subtract(const Duration(minutes: 30)),
        due: DateTime.now().subtract(const Duration(minutes: 1)),
      ),
    );

void main() {
  group('Что считается путаемым', () {
    test('слова, различающиеся парой букв', () {
      expect(
        Interference.conflict(
          _c('c1', 'affect', 'влиять'),
          _c('c2', 'effect', 'следствие'),
        ),
        true,
      );
    });

    test('разные слова с одинаковым переводом', () {
      expect(
        Interference.conflict(
          _c('c1', 'bright', 'яркий'),
          _c('c2', 'vivid', 'яркий'),
        ),
        true,
        reason: 'на вопрос «как будет яркий» верны оба — карточки дерутся',
      );
    });

    test('непохожие слова конфликтом не считаются', () {
      expect(
        Interference.conflict(
          _c('c1', 'table', 'стол'),
          _c('c2', 'window', 'окно'),
        ),
        false,
      );
    });

    test('короткие слова по написанию не сравниваются', () {
      expect(
        Interference.conflict(_c('c1', 'cat', 'кот'), _c('c2', 'car', 'машина')),
        false,
        reason: 'у трёхбуквенных две правки — это уже другое слово',
      );
    });
  });

  group('Отбор новых слов', () {
    test('путаемая пара не идёт в один заход', () {
      final picked = Interference.pickNew(
        [
          _c('c1', 'affect', 'влиять'),
          _c('c2', 'effect', 'следствие'),
          _c('c3', 'window', 'окно'),
        ],
        [],
      );
      expect(picked.take(2).map((c) => c.front), ['affect', 'window']);
    });

    test('спорное слово откладывается, а не теряется', () {
      final picked = Interference.pickNew(
        [_c('c1', 'affect', 'влиять'), _c('c2', 'effect', 'следствие')],
        [],
      );
      expect(picked.length, 2, reason: 'лучше спорная карта, чем пустая сессия');
    });

    test('учитывает слова, которые уже в работе', () {
      final picked = Interference.pickNew(
        [_c('c1', 'effect', 'следствие'), _c('c2', 'window', 'окно')],
        [_learning('c0', 'affect', 'влиять')],
      );
      expect(picked.first.front, 'window');
    });
  });

  group('Разведение внутри очереди', () {
    test('путаемые слова расходятся', () {
      final queue = Interference.spread([
        _c('c1', 'affect', 'влиять'),
        _c('c2', 'effect', 'следствие'),
        _c('c3', 'window', 'окно'),
        _c('c4', 'table', 'стол'),
        _c('c5', 'river', 'река'),
        _c('c6', 'stone', 'камень'),
      ]);
      final i1 = queue.indexWhere((c) => c.front == 'affect');
      final i2 = queue.indexWhere((c) => c.front == 'effect');
      expect((i1 - i2).abs(), greaterThan(1));
      expect(queue.length, 6, reason: 'ни одна карта не потерялась');
    });

    test('короткую очередь не трогает', () {
      final cards = [_c('c1', 'affect', 'влиять'), _c('c2', 'effect', 'сл')];
      expect(Interference.spread(cards), cards);
    });

    test('очередь из одних путаемых слов не зацикливается', () {
      final queue = Interference.spread([
        _c('c1', 'bright', 'яркий'),
        _c('c2', 'vivid', 'яркий'),
        _c('c3', 'shiny', 'яркий'),
        _c('c4', 'lucid', 'яркий'),
      ]);
      expect(queue.length, 4);
    });
  });

  test('билдер сессии разводит путаемые новые слова', () {
    final queue = SessionBuilder().build(
      StudyMode.flashcards,
      [
        _c('c1', 'affect', 'влиять'),
        _c('c2', 'effect', 'следствие'),
        _c('c3', 'window', 'окно'),
      ],
      DateTime.now(),
      newAllowed: 2,
    );
    expect(
      queue.map((e) => e.card.front).toSet(),
      {'affect', 'window'},
      reason: 'в один заход берём непутаемую пару',
    );
  });

  group('Счёт разведённых пар', () {
    test('считает пары, а не слова', () {
      final cards = [
        _c('c1', 'affect', 'влиять'),
        _c('c2', 'effect', 'эффект'),
        _c('c3', 'table', 'стол'),
      ];
      expect(Interference.countConflicts(cards), 1);
    });

    test('без путаницы — ноль', () {
      final cards = [
        _c('c1', 'table', 'стол'),
        _c('c2', 'window', 'окно'),
      ];
      expect(Interference.countConflicts(cards), 0);
    });
  });
}
