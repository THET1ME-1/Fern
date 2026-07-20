import 'package:flutter_test/flutter_test.dart';

import 'package:fern/models/review_event.dart';
import 'package:fern/models/word_card.dart';
import 'package:fern/services/fsrs_optimizer.dart';

/// Оптимизатор должен подгонять начальную прочность по НАСТОЯЩЕМУ интервалу.
///
/// Пара для подгонки бралась как «второе событие карты», а в Fern второе
/// событие — это внутридневной шаг: новая карта плюс «Хорошо» дают срок через
/// десять минут. Прочность в ДНЯХ подгонялась против 0.007 дня, оптимум
/// упирался в границу сетки, и гейт качества результат отбивал. Кнопка
/// «Оптимизировать» после двухсот повторов не срабатывала никогда.
List<ReviewEvent> _history({required int cards, required bool recalled}) {
  final events = <ReviewEvent>[];
  for (var i = 0; i < cards; i++) {
    final id = 'c$i';
    // Новая карта, «Хорошо» — срок через десять минут.
    events.add(ReviewEvent(
      cardId: id,
      ts: 1000 + i,
      grade: 3,
      elapsedDays: 0,
      stateBefore: FsrsState.newCard.index,
    ));
    // Внутридневной шаг: те же десять минут спустя.
    events.add(ReviewEvent(
      cardId: id,
      ts: 2000 + i,
      grade: 3,
      elapsedDays: 0.0069,
      stateBefore: FsrsState.learning.index,
    ));
    // Первый настоящий интервал: три дня.
    events.add(ReviewEvent(
      cardId: id,
      ts: 3000 + i,
      grade: recalled ? 3 : 1,
      elapsedDays: 3.0,
      stateBefore: FsrsState.review.index,
    ));
    // Добиваем журнал зрелыми повторами, чтобы хватило на minTotal.
    for (var k = 0; k < 4; k++) {
      events.add(ReviewEvent(
        cardId: id,
        ts: 4000 + i * 10 + k,
        grade: 3,
        elapsedDays: 10.0 + k,
        stateBefore: FsrsState.review.index,
      ));
    }
  }
  return events;
}

void main() {
  test('начальная прочность считается по межсуточному повтору', () {
    final result = FsrsOptimizer.optimize(_history(cards: 40, recalled: true));

    expect(result.fittedRatings, greaterThan(0));
    // «Хорошо» на первом показе → w[2]. Слово держалось три дня, значит
    // начальная прочность не может измеряться десятыми долями дня.
    expect(result.weights[2], greaterThan(1.0),
        reason: 'подгонка по десятиминутному шагу вжимала вес в нижнюю '
            'границу сетки (0.1), и результат отбивался гейтом качества');
  });

  test('забытое через три дня слово даёт прочность меньше, чем помнимое', () {
    final remembered =
        FsrsOptimizer.optimize(_history(cards: 40, recalled: true));
    final forgotten =
        FsrsOptimizer.optimize(_history(cards: 40, recalled: false));

    expect(forgotten.weights[2], lessThan(remembered.weights[2]),
        reason: 'иначе подгонка не отражает реальную кривую забывания');
  });
}
