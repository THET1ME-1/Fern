import 'package:flutter_test/flutter_test.dart';

import 'package:fern/models/word_card.dart';
import 'package:fern/study/study_models.dart';

void main() {
  WordCard card(String id, String front, String back) =>
      WordCard(id: id, deckId: 'd', front: front, back: back);

  test('пара с похожим написанием становится упражнением', () {
    final affect = card('c1', 'affect', 'влиять');
    final pool = [affect, card('c2', 'effect', 'следствие'), card('c3', 'sun', 'солнце')];
    final twins = buildTwins(affect, pool);

    expect(twins, isNotNull);
    expect(twins!.twin.front, 'effect');
    expect(twins.options.toSet(), {'affect', 'effect'});
    expect(twins.options[twins.correctIndex], 'affect');
    expect(twins.prompt, 'влиять');
  });

  test('пара с одинаковым переводом тоже путается', () {
    final bright = card('c1', 'bright', 'яркий');
    final twins = buildTwins(bright, [bright, card('c2', 'vivid', 'яркий')]);
    expect(twins?.twin.front, 'vivid');
  });

  test('без двойника упражнения нет', () {
    final sun = card('c1', 'sun', 'солнце');
    expect(buildTwins(sun, [sun, card('c2', 'table', 'стол')]), isNull);
  });

  test('карточка правила в двойники не идёт', () {
    final rule = WordCard(
      id: 'r1',
      deckId: 'd',
      front: 'Present Perfect',
      back: 'объяснение',
      rule: 'present_perfect',
    );
    final other = WordCard(
      id: 'r2',
      deckId: 'd',
      front: 'Present Perfect Continuous',
      back: 'объяснение',
      rule: 'present_perfect_cont',
    );
    expect(buildTwins(rule, [rule, other]), isNull);
  });

  test('режим собирает только карточки с двойниками', () {
    final cards = [
      card('c1', 'affect', 'влиять'),
      card('c2', 'effect', 'следствие'),
      card('c3', 'sun', 'солнце'),
    ];
    final queue = SessionBuilder().build(StudyMode.twins, cards, DateTime.now());
    expect(queue.length, 2);
    expect(queue.every((e) => e.kind == ExerciseKind.twins), isTrue);
  });
}
