import 'package:flutter_test/flutter_test.dart';
import 'package:fern/models/fsrs.dart';
import 'package:fern/models/word_card.dart';

/// Зонд по границам планировщика: данные, которых «не бывает», но которые
/// приходят от смены часового пояса, ручной правки времени, очень долгих
/// перерывов и первого запуска.
void main() {
  final fsrs = Fsrs.forSimulation();

  test('Нулевая прочность не даёт NaN и не делит на ноль', () {
    final r = fsrs.retrievability(3, 0);
    expect(r.isFinite, isTrue, reason: 'R при stability=0 должно быть числом');
    expect(r, inInclusiveRange(0, 1));
  });

  test('Отрицательный срок (часы перевели назад) не ломает R', () {
    final r = fsrs.retrievability(-5, 10);
    expect(r.isFinite, isTrue);
    expect(r, inInclusiveRange(0, 1));
  });

  test('Огромная прочность не переполняет интервал', () {
    final state = ReviewState(
      stability: 1e9,
      difficulty: 5,
      state: FsrsState.review,
      lastReview: DateTime.now().subtract(const Duration(days: 1)),
      due: DateTime.now(),
    );
    final next = fsrs.review(state, Rating.easy, DateTime.now());
    expect(next.due, isNotNull);
    expect(next.due!.isAfter(DateTime.now()), isTrue);
    expect(next.stability.isFinite, isTrue);
  });

  test('Оценка карты, которую «повторили в будущем», не даёт отрицательного срока',
      () {
    final now = DateTime.now();
    final state = ReviewState(
      stability: 10,
      difficulty: 5,
      state: FsrsState.review,
      lastReview: now.add(const Duration(days: 3)), // время на телефоне сдвинули
      due: now,
    );
    final next = fsrs.review(state, Rating.good, now);
    expect(next.stability.isFinite, isTrue);
    expect(next.stability, greaterThan(0));
    expect(next.due!.isAfter(now), isTrue);
  });

  test('Сложность остаётся в своих границах при череде провалов', () {
    var state = ReviewState(
      stability: 5,
      difficulty: 5,
      state: FsrsState.review,
      lastReview: DateTime.now().subtract(const Duration(days: 2)),
      due: DateTime.now(),
    );
    for (var i = 0; i < 50; i++) {
      state = fsrs.review(state, Rating.again, DateTime.now());
    }
    expect(state.difficulty, inInclusiveRange(1, 10));
    expect(state.stability, greaterThan(0));
  });

  test('Череда «легко» не разгоняет прочность до бесконечности', () {
    var state = ReviewState(
      stability: 5,
      difficulty: 5,
      state: FsrsState.review,
      lastReview: DateTime.now().subtract(const Duration(days: 2)),
      due: DateTime.now(),
    );
    for (var i = 0; i < 200; i++) {
      state = fsrs.review(
          state, Rating.easy, DateTime.now().add(Duration(days: i * 30)));
    }
    expect(state.stability.isFinite, isTrue);
    expect(state.due, isNotNull);
  });

  test('Карта с нулевой прочностью не уезжает на сто лет вперёд', () {
    // Такое состояние приходит из чужого бэкапа или импорта колоды: state
    // «повторение», а прочности нет. Формула давала NaN, а clamp NaN отдавал
    // верхнюю границу — 36500 дней, то есть повтор в следующем веке.
    final now = DateTime.now();
    final state = ReviewState(
      stability: 0,
      difficulty: 5,
      state: FsrsState.review,
      lastReview: now.subtract(const Duration(days: 5)),
      due: now,
    );
    final next = fsrs.review(state, Rating.good, now);
    expect(next.stability.isFinite, isTrue);
    expect(next.stability, greaterThan(0));
    expect(next.due!.difference(now).inDays, lessThan(365),
        reason: 'срок повтора остаётся в разумных пределах');
  });

  test('Новая карта без прошлого повтора планируется без ошибок', () {
    final next = fsrs.review(ReviewState(), Rating.good, DateTime.now());
    expect(next.due, isNotNull);
    expect(next.stability, greaterThan(0));
  });
}
