import 'package:flutter_test/flutter_test.dart';
import 'package:fern/models/fsrs.dart';
import 'package:fern/models/word_card.dart';

void main() {
  final fsrs = Fsrs.forSimulation();
  final now = DateTime.now();

  ReviewState mature({double stability = 4.5, int elapsedDays = 365}) =>
      ReviewState(
        stability: stability,
        difficulty: 5,
        state: FsrsState.review,
        lastReview: now.subtract(Duration(days: elapsedDays)),
        due: now.subtract(Duration(days: elapsedDays - 4)),
      );

  test('Забывание не увеличивает прочность', () {
    // Слово не спрашивали год, человек его не вспомнил. Прочность обязана
    // упасть: «не помню» — это потеря памяти, а не награда за долгий перерыв.
    final before = mature();
    final after = fsrs.review(before, Rating.again, now);
    expect(after.stability, lessThan(before.stability),
        reason: 'после срыва прочность падает');
  });

  test('Забывание слабого слова после долгого перерыва тоже не награда', () {
    final before = mature(stability: 1.0, elapsedDays: 60);
    final after = fsrs.review(before, Rating.again, now);
    expect(after.stability, lessThan(before.stability));
  });

  test('Слова, пройденные одинаково, не слипаются на одну дату', () {
    // Тридцать слов введены за вечер и пройдены одним и тем же путём: у них
    // побитово одинаковая прочность. Если разброс считать только из неё, все
    // тридцать получат один и тот же день — ровно то, ради чего разброс и
    // задуман.
    final dates = <DateTime>{};
    for (var i = 0; i < 30; i++) {
      final state = ReviewState(
        stability: 12.0,
        difficulty: 5,
        state: FsrsState.review,
        lastReview: now.subtract(const Duration(days: 12)),
        due: now,
      );
      final next = fsrs.review(state, Rating.good, now, fuzzKey: 'card$i');
      dates.add(DateTime(next.due!.year, next.due!.month, next.due!.day));
    }
    expect(dates.length, greaterThan(1),
        reason: 'нагрузка расходится по дням, а не встаёт одним комом');
  });

  test('Одна и та же карта планируется одинаково при повторном расчёте', () {
    ReviewState plan() => fsrs.review(
          ReviewState(
            stability: 12.0,
            difficulty: 5,
            state: FsrsState.review,
            lastReview: now.subtract(const Duration(days: 12)),
            due: now,
          ),
          Rating.good,
          now,
          fuzzKey: 'один-и-тот-же',
        );
    expect(plan().due, plan().due);
  });
}
