// Инварианты планировщика на четырёх тысячах состояний: не конкретные числа, а
// то, что обязано выполняться всегда. Прочность конечна и неотрицательна,
// сложность внутри шкалы 1..10, срок не в прошлом и не дальше авторского
// потолка (100 лет — `maxIntervalDays` в fsrs.dart).
//
// Ровно здесь ловится класс ошибок, который уже стрелял: NaN от нулевой
// прочности уносил карточку на 36500 дней вперёд.
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:fern/models/fsrs.dart';
import 'package:fern/models/word_card.dart';

final _found = <String>[];

void main() {
  tearDown(() {
    expect(_found, isEmpty, reason: _found.take(10).join('\n'));
    _found.clear();
  });

  test('инварианты после оценки', () {
    final f = Fsrs.instance;
    final rnd = Random(42);
    final now = DateTime(2026, 8, 17, 12);

    for (var i = 0; i < 4000; i++) {
      final state = FsrsState.values[rnd.nextInt(FsrsState.values.length)];
      final stability = [0.0, 0.001, 0.4, 1.0, 7.3, 90.0, 3650.0, 1e6][rnd.nextInt(8)];
      final difficulty = [0.0, 1.0, 5.0, 9.99, 10.0, 11.0][rnd.nextInt(6)];
      final elapsed = [0, 1, 3, 30, 400, 4000][rnd.nextInt(6)];
      final rating = Rating.values[rnd.nextInt(Rating.values.length)];

      final st = ReviewState(
        stability: stability,
        difficulty: difficulty,
        state: state,
        reps: rnd.nextInt(50),
        lapses: rnd.nextInt(12),
        lastReview: now.subtract(Duration(days: elapsed)),
        due: now,
      );

      final before = 'state=$state S=$stability D=$difficulty '
          'elapsed=$elapsed rating=$rating';
      final out = f.review(st, rating, now);

      void check(String what, bool ok) {
        if (!ok) {
          _found.add('$what при $before → S=${out.stability} '
              'D=${out.difficulty} due=${out.due}');
        }
      }

      check('прочность NaN', !out.stability.isNaN);
      check('прочность бесконечна', out.stability.isFinite);
      check('прочность отрицательна', out.stability >= 0);
      check('сложность NaN', !out.difficulty.isNaN);
      // Ноль — «сложность ещё не задана» у новой карточки, он законен.
      check(
          'сложность вне шкалы',
          out.difficulty == 0 ||
              (out.difficulty >= 1 - 1e-9 && out.difficulty <= 10 + 1e-9));

      final due = out.due;
      check('срок не задан', due != null);
      if (due != null) {
        check('срок в прошлом', !due.isBefore(now));
        check('срок дальше потолка',
            due.difference(now).inDays <= 36500);
      }
    }
  });

  test('предпросмотр интервалов на кнопках', () {
    final f = Fsrs.instance;
    final now = DateTime(2026, 8, 17, 12);
    for (final state in FsrsState.values) {
      for (final s in [0.0, 0.5, 10.0, 1000.0]) {
        final st = ReviewState(
          stability: s,
          difficulty: 5,
          state: state,
          reps: 3,
          lastReview: now.subtract(const Duration(days: 5)),
          due: now,
        );
        final preview = f.preview(st, now);
        preview.forEach((rating, interval) {
          if (interval.isNegative) {
            _found.add('предпросмотр отрицателен: $state S=$s $rating '
                '→ $interval');
          }
          if (interval.inDays > 36500) {
            _found.add('предпросмотр дальше потолка: $state S=$s $rating '
                '→ ${interval.inDays} дн.');
          }
        });
      }
    }
  });
}
