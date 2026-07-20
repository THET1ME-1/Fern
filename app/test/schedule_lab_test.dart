import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:fern/models/fsrs.dart';
import 'package:fern/models/review_event.dart';
import 'package:fern/models/word_card.dart';
import 'package:fern/services/schedule_lab.dart';

/// История повторов «идеального» ученика: помнит почти всегда.
/// [recallRate] — доля вспомненных, распределяется ровно (i % k), чтобы прогон
/// был воспроизводимым.
List<ReviewEvent> _history({
  int cards = 40,
  int repsPerCard = 6,
  double recallRate = 0.9,
  double elapsed = 5,
}) {
  final events = <ReviewEvent>[];
  final missEvery = (1 / (1 - recallRate)).round();
  var counter = 0;
  for (var c = 0; c < cards; c++) {
    var ts = DateTime(2026, 1, 1).millisecondsSinceEpoch;
    for (var r = 0; r < repsPerCard; r++) {
      final miss = counter % missEvery == 0 && r > 0;
      events.add(ReviewEvent(
        cardId: 'c$c',
        ts: ts,
        grade: r == 0 ? 3 : (miss ? 1 : 3),
        elapsedDays: r == 0 ? 0 : elapsed,
        stateBefore: r == 0
            ? FsrsState.newCard.index
            : (r == 1 ? FsrsState.learning.index : FsrsState.review.index),
      ));
      ts += (elapsed * 86400000).round();
      counter++;
    }
  }
  return events;
}

void main() {
  group('Измерение качества расписания', () {
    test('на пустой истории метрик нет', () {
      expect(ScheduleLab.evaluate([]).hasData, false);
    });

    test('считает предсказание и факт на зрелых повторах', () {
      final q = ScheduleLab.evaluate(_history());
      expect(q.hasData, true);
      expect(q.samples, greaterThan(50));
      expect(q.actual, inInclusiveRange(0.0, 1.0));
      expect(q.predicted, inInclusiveRange(0.0, 1.0));
      expect(q.logLoss, greaterThan(0));
    });

    test('видит, что планировщик обещает больше, чем выходит', () {
      // Ученик забывает половину повторов — дефолтные веса будут оптимистичны.
      final q = ScheduleLab.evaluate(_history(recallRate: 0.5));
      expect(q.tooOptimistic, true,
          reason: 'при половине срывов обещанное удержание завышено');
    });

    test('лучше предсказывающие веса дают меньший лосс', () {
      final events = _history(recallRate: 0.55, elapsed: 9);
      final base = ScheduleLab.evaluate(events);

      // Урезаем начальные стабильности: память «короче», предсказание должно
      // приблизиться к суровой реальности этой истории.
      final pessimistic = List<double>.of(Fsrs.defaultWeights);
      for (var i = 0; i < 4; i++) {
        pessimistic[i] = max(0.1, pessimistic[i] * 0.2);
      }
      final tuned = ScheduleLab.evaluate(events, weights: pessimistic);

      expect(tuned.logLoss, lessThan(base.logLoss));
      expect(ScheduleLab.improvementPercent(base, tuned), greaterThan(0));
      expect(ScheduleLab.worthApplying(base, tuned), true);
    });

    test('одинаковые веса — нулевая разница, применять нечего', () {
      final events = _history();
      final a = ScheduleLab.evaluate(events);
      final b = ScheduleLab.evaluate(events);
      expect(ScheduleLab.improvementPercent(a, b), closeTo(0, 1e-9));
      expect(ScheduleLab.worthApplying(a, b), false);
    });

    test('на скудной истории применять не советует', () {
      final events = _history(cards: 2, repsPerCard: 4);
      final base = ScheduleLab.evaluate(events);
      final other = ScheduleLab.evaluate(
        events,
        weights: List<double>.of(Fsrs.defaultWeights)..[0] = 0.1,
      );
      expect(ScheduleLab.worthApplying(base, other), false,
          reason: 'меньше ${ScheduleLab.minSamples} повторов — вывод шумный');
    });

    test('симуляция не трогает боевые веса', () {
      final before = List<double>.of(Fsrs.instance.w);
      ScheduleLab.evaluate(
        _history(),
        weights: List<double>.of(Fsrs.defaultWeights)..[0] = 42,
      );
      expect(Fsrs.instance.w, before);
    });

    test('сравнение вариантов возвращает по метрике на каждый', () {
      final events = _history();
      final result = ScheduleLab.compare(events, {
        'default': null,
        'tweaked': List<double>.of(Fsrs.defaultWeights)..[0] = 1.0,
      });
      expect(result.keys, containsAll(['default', 'tweaked']));
      expect(result['default']!.hasData, true);
    });
  });
}
