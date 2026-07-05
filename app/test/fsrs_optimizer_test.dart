import 'package:flutter_test/flutter_test.dart';

import 'package:fern/models/review_event.dart';
import 'package:fern/models/word_card.dart';
import 'package:fern/services/fsrs_optimizer.dart';

void main() {
  // Синтетика: N карт, у каждой первый показ (good) и второй повтор через 5
  // дней; recallRate — доля вспомнивших на втором.
  List<ReviewEvent> synth(int n, {double recallRate = 0.9}) {
    final out = <ReviewEvent>[];
    for (var i = 0; i < n; i++) {
      final recalled = (i % 10) < (recallRate * 10).round();
      out.add(ReviewEvent(
        cardId: 'c$i',
        ts: i * 1000,
        grade: 3, // good — первый показ
        elapsedDays: 0,
        stateBefore: FsrsState.newCard.index,
      ));
      out.add(ReviewEvent(
        cardId: 'c$i',
        ts: i * 1000 + 1,
        grade: recalled ? 3 : 1,
        elapsedDays: 5,
        stateBefore: FsrsState.review.index,
      ));
    }
    return out;
  }

  test('мало данных → enough == false, веса дефолтные', () {
    final r = FsrsOptimizer.optimize(synth(10));
    expect(r.enough, false);
    expect(r.weights.length, 19);
    expect(r.weights[2], closeTo(3.173, 0.0001)); // дефолтный w2 не тронут
  });

  test('достаточно данных → подгоняет w2 и измеряет удержание', () {
    final r = FsrsOptimizer.optimize(synth(250, recallRate: 0.9));
    expect(r.enough, true);
    expect(r.fittedRatings, greaterThanOrEqualTo(1));
    expect(r.reviewSamples, 250);
    // 90% вспомнили на втором повторе.
    expect(r.measuredRetention, closeTo(0.9, 0.02));
    // R(5, S)=0.9 ⇒ S≈5 → w2 (good) уходит от дефолтного 3.173 в сторону ~5.
    expect(r.weights[2], greaterThan(3.5));
    expect(r.weights[2], lessThan(9));
  });

  test('весь набор из 19 значений и все конечные', () {
    final r = FsrsOptimizer.optimize(synth(250));
    expect(r.weights.length, 19);
    expect(r.weights.every((w) => w.isFinite), true);
  });
}
