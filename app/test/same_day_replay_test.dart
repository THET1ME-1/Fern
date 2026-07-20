import 'package:flutter_test/flutter_test.dart';

import 'package:fern/models/fsrs.dart';
import 'package:fern/models/word_card.dart';

/// Прогон одной карты по кругу в тот же день не должен растягивать интервал.
///
/// Три режима показывают карточки БЕЗ учёта срока и при этом двигают
/// расписание: «Трудные», «Под угрозой» и разминка перед чтением. Короткая
/// ветка FSRS умножает прочность на константу (×1.41 за «хорошо», ×2.36 за
/// «легко») не глядя ни на сложность, ни на прошедшее время, а ограничителя на
/// число таких умножений нет. Шесть тапов за восемнадцать минут уносили карту
/// с 84 дней на 463, а «Легко» — на десять лет вперёд. Бьёт по пиявкам:
/// именно они попадают в «Трудные» и именно им автооценка ставит «Легко» на
/// втором проходе, когда ответ уже перед глазами.
ReviewState _mature() => ReviewState(
      stability: 45,
      difficulty: 8,
      state: FsrsState.review,
      reps: 12,
      lapses: 4,
      step: 0,
      due: DateTime(2026, 3, 1),
      lastReview: DateTime(2026, 1, 20),
    );

void main() {
  final fsrs = Fsrs.instance;

  test('повторный успех в тот же день не двигает срок', () {
    final start = DateTime(2026, 3, 1, 9);
    // Честный ранний повтор: с прошлого раза прошло сорок дней.
    final first = fsrs.review(_mature(), Rating.good, start, fuzzKey: 'c1');
    final stability = first.stability;
    final due = first.due;

    var state = first;
    for (var i = 1; i <= 5; i++) {
      state = fsrs.review(
          state, Rating.good, start.add(Duration(minutes: 3 * i)),
          fuzzKey: 'c1');
    }

    expect(state.stability, stability,
        reason: 'память за восемнадцать минут не окрепла впятеро');
    expect(state.due, due);
  });

  test('«легко» на втором проходе не уносит карту на годы', () {
    final start = DateTime(2026, 3, 1, 9);
    var state = fsrs.review(_mature(), Rating.good, start, fuzzKey: 'c1');
    final due = state.due;

    // Ответ уже перед глазами, поэтому автооценка ставит «легко».
    for (var i = 1; i <= 4; i++) {
      state = fsrs.review(
          state, Rating.easy, start.add(Duration(minutes: 5 * i)),
          fuzzKey: 'c1');
    }

    expect(state.due, due);
    expect(state.due!.difference(start).inDays, lessThan(365),
        reason: 'четыре тапа за двадцать минут отправляли слово на десять лет');
  });

  test('«не помню» в тот же день срабатывает по-настоящему', () {
    final start = DateTime(2026, 3, 1, 9);
    final first = fsrs.review(_mature(), Rating.good, start, fuzzKey: 'c1');

    final failed = fsrs.review(
        first, Rating.again, start.add(const Duration(minutes: 5)),
        fuzzKey: 'c1');

    expect(failed.state, FsrsState.relearning,
        reason: 'забыл — значит забыл, в какой бы раз карту ни показали');
    expect(failed.stability, lessThan(first.stability));
    expect(failed.lapses, first.lapses + 1);
  });

  test('повтор на следующий день засчитывается', () {
    // Карта с суточным интервалом: вчера в 23:00, сегодня в 20:00. Календарно
    // это разные дни, и повтор настоящий, хотя прошло меньше суток.
    final state = ReviewState(
      stability: 1.2,
      difficulty: 6,
      state: FsrsState.review,
      reps: 3,
      lapses: 0,
      step: 0,
      due: DateTime(2026, 3, 2, 23),
      lastReview: DateTime(2026, 3, 1, 23),
    );
    final next =
        fsrs.review(state, Rating.good, DateTime(2026, 3, 2, 20), fuzzKey: 'c1');

    expect(next.stability, greaterThan(state.stability));
    expect(next.due!.isAfter(DateTime(2026, 3, 2, 20)), isTrue);
  });
}
