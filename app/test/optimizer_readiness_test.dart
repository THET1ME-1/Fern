import 'package:flutter_test/flutter_test.dart';

import 'package:fern/models/review_event.dart';
import 'package:fern/models/word_card.dart';
import 'package:fern/services/fsrs_optimizer.dart';

/// Подпись под кнопкой обязана мерить то же, что и гейт оптимизатора.
///
/// Счётчик показывал ВСЕ события журнала («387 / 200»), кнопка была доступна,
/// а подгонка требует другого: слов, повторённых через сутки после знакомства.
/// Человек с полным счётчиком нажимал и получал «Пока мало данных» — надпись
/// противоречила сама себе.
List<ReviewEvent> _sameDayOnly({required int cards}) {
  final events = <ReviewEvent>[];
  for (var i = 0; i < cards; i++) {
    final id = 'c$i';
    events.add(ReviewEvent(
      cardId: id,
      ts: 1000 + i,
      grade: 3,
      elapsedDays: 0,
      stateBefore: FsrsState.newCard.index,
    ));
    // Внутридневные шаги: минута и десять минут.
    events.add(ReviewEvent(
      cardId: id,
      ts: 2000 + i,
      grade: 3,
      elapsedDays: 0.0007,
      stateBefore: FsrsState.learning.index,
    ));
    events.add(ReviewEvent(
      cardId: id,
      ts: 3000 + i,
      grade: 3,
      elapsedDays: 0.0069,
      stateBefore: FsrsState.learning.index,
    ));
  }
  return events;
}

List<ReviewEvent> _withNextDay({required int cards}) {
  final events = _sameDayOnly(cards: cards);
  for (var i = 0; i < cards; i++) {
    events.add(ReviewEvent(
      cardId: 'c$i',
      ts: 4000 + i,
      grade: 3,
      elapsedDays: 1.0,
      stateBefore: FsrsState.review.index,
    ));
  }
  events.sort((a, b) {
    final byCard = a.cardId.compareTo(b.cardId);
    return byCard != 0 ? byCard : a.ts.compareTo(b.ts);
  });
  return events;
}

void main() {
  test('журнал без межсуточных повторов к подгонке не готов', () {
    final events = _sameDayOnly(cards: 129); // 387 событий, как на скриншоте
    expect(events.length, 387);

    final r = FsrsOptimizer.readiness(events);
    expect(r.total, 387);
    expect(r.pairs, 0, reason: 'ни одно слово не дожило до следующего дня');
    expect(r.enough, isFalse);
    expect(FsrsOptimizer.optimize(events).enough, isFalse,
        reason: 'готовность обязана совпадать с гейтом самой подгонки');
  });

  test('слова, повторённые на следующий день, засчитываются в готовность', () {
    final r = FsrsOptimizer.readiness(_withNextDay(cards: 129));

    expect(r.pairs, greaterThanOrEqualTo(FsrsOptimizer.minPerRating));
    expect(r.enough, isTrue);
    expect(FsrsOptimizer.optimize(_withNextDay(cards: 129)).enough, isTrue);
  });

  test('готовность считает лучшую оценку, а не сумму по всем', () {
    // По девять слов на «Не помню» и «Хорошо»: суммарно 18 пар, но ни одной
    // оценки с двадцатью — подгонять начальную прочность ещё не на чем.
    final events = <ReviewEvent>[];
    for (var i = 0; i < 18; i++) {
      final id = 'c$i';
      events.add(ReviewEvent(
        cardId: id,
        ts: 1000,
        grade: i.isEven ? 1 : 3,
        elapsedDays: 0,
        stateBefore: FsrsState.newCard.index,
      ));
      events.add(ReviewEvent(
        cardId: id,
        ts: 2000,
        grade: 3,
        elapsedDays: 2.0,
        stateBefore: FsrsState.review.index,
      ));
    }

    final r = FsrsOptimizer.readiness(events);
    expect(r.pairs, 9);
    expect(r.enough, isFalse);
  });
}
