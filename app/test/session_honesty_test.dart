import 'package:flutter_test/flutter_test.dart';

import 'package:fern/models/word_card.dart';
import 'package:fern/services/interference.dart';
import 'package:fern/services/reading_warmup.dart';

WordCard _card(String id, String front, String back,
        {FsrsState state = FsrsState.review}) =>
    WordCard(id: id, deckId: 'd1', front: front, back: back)
      ..review = ReviewState(
        stability: state == FsrsState.newCard ? 0 : 20,
        difficulty: 5,
        state: state,
        reps: state == FsrsState.newCard ? 0 : 5,
        lapses: 0,
        step: 0,
        due: state == FsrsState.newCard ? null : DateTime(2026, 3, 1),
        lastReview: state == FsrsState.newCard ? null : DateTime(2026, 2, 1),
      );

void main() {
  group('разминка перед чтением', () {
    test('новые слова в разминку не идут', () {
      // Разминка освежает то, что вот-вот встретится в тексте. Новое слово
      // голой флип-карточкой — это не знакомство, для него есть «Учить». Хуже
      // того, показ засчитывался в дневной лимит новых, и вечерняя сессия
      // оставалась без единого нового слова.
      final cards = [
        _card('n1', 'water', 'вода', state: FsrsState.newCard),
        _card('n2', 'stone', 'камень', state: FsrsState.newCard),
        _card('r1', 'house', 'дом'),
      ];
      final picked = ReadingWarmup.pick(
        cards,
        {'water', 'stone', 'house'},
        'en',
        now: DateTime(2026, 3, 10),
      );

      expect(picked.map((c) => c.id), ['r1']);
    });

    test('пустая разминка, когда впереди одни незнакомые слова', () {
      final picked = ReadingWarmup.pick(
        [_card('n1', 'water', 'вода', state: FsrsState.newCard)],
        {'water'},
        'en',
        now: DateTime(2026, 3, 10),
      );
      expect(picked, isEmpty);
    });
  });

  group('счётчик разведённых ловушек', () {
    test('считает разведённые пары, а не все конфликты набора', () {
      // Гнездо однокоренных: пар в наборе сотни, а развести алгоритм может
      // лишь часть — остальные так и остаются рядом, потому что разводить
      // некуда. Экран результатов обещал «Развёл 191 путаемых слов» при
      // двадцати двух карточках в сессии.
      final nest = [
        for (var i = 0; i < 20; i++) _card('c$i', 'form$i', 'форма'),
      ];
      final others = [
        _card('x1', 'house', 'дом'),
        _card('x2', 'water', 'вода'),
      ];
      final queue = [...nest, ...others];

      final spread = Interference.spread(queue);
      final separated = Interference.countSeparated(queue, spread);

      expect(separated, lessThan(queue.length),
          reason: 'развести больше пар, чем есть карточек, невозможно');
      expect(separated, lessThanOrEqualTo(Interference.countConflicts(queue)));
    });

    test('разведённая пара считается, слипшаяся — нет', () {
      final a = _card('a', 'bat', 'летучая мышь');
      final b = _card('b', 'bat', 'бита');
      final filler = [
        for (var i = 0; i < 6; i++) _card('f$i', 'word$i', 'слово$i'),
      ];
      final before = [a, b, ...filler];
      final after = Interference.spread(before);

      expect(Interference.countSeparated(before, after), 1);
      // Тот же порядок — значит ничего не развели.
      expect(Interference.countSeparated(before, before), 0);
    });
  });
}
