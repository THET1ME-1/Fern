import 'package:flutter_test/flutter_test.dart';

import 'package:fern/models/fsrs.dart';
import 'package:fern/models/word_card.dart';

/// Три дыры в планировщике, которые вылезают на обычном пользовании.
void main() {
  final fsrs = Fsrs.instance;

  group('долгий перерыв на внутридневном шаге', () {
    // Карточки с сроком «+10 минут» бросают постоянно: сессия кончилась,
    // приложение закрыли. Через месяцы человек возвращается и ВСПОМИНАЕТ
    // слово, а планировщик считает так, будто прошло десять минут.
    ReviewState relearning() => ReviewState(
          stability: 3.466,
          difficulty: 7,
          state: FsrsState.relearning,
          reps: 9,
          lapses: 2,
          step: 0,
          due: DateTime(2026, 1, 1, 10, 10),
          lastReview: DateTime(2026, 1, 1, 10),
        );

    test('вспомнил после трёх месяцев — интервал по-настоящему длинный', () {
      final next = fsrs.review(
          relearning(), Rating.good, DateTime(2026, 4, 1, 10),
          fuzz: false, fuzzKey: 'c1');

      final days = next.due!.difference(DateTime(2026, 4, 1, 10)).inDays;
      expect(days, greaterThan(20),
          reason: 'девяносто дней без подсказок — это сильное припоминание, '
              'а карта получала пять дней и ярлык решал всё');
    });

    test('добитая в тот же день карта считается по-прежнему', () {
      final next = fsrs.review(
          relearning(), Rating.good, DateTime(2026, 1, 1, 10, 12),
          fuzz: false, fuzzKey: 'c1');
      expect(next.stability, closeTo(4.879, 0.5),
          reason: 'внутридневной шаг работает как работал');
    });
  });

  group('встреча слова в книге', () {
    test('срок не съезжает на более ранний', () {
      final prev = ReviewState(
        stability: 300,
        difficulty: 5,
        state: FsrsState.review,
        reps: 20,
        lapses: 0,
        step: 0,
        // Разброс отодвинул повтор: 324 дня вместо 300.
        due: DateTime(2026, 1, 1).add(const Duration(days: 324)),
        lastReview: DateTime(2026, 1, 1),
      );
      final now = DateTime(2026, 1, 1).add(const Duration(days: 305));

      final next = fsrs.passiveExposure(prev, now);

      expect(next, isNotNull);
      expect(next!.stability, greaterThan(prev.stability),
          reason: 'память от встречи крепнет');
      expect(next.due!.isBefore(prev.due!), isFalse,
          reason: 'слово попалось на странице — это не повод спросить его '
              'раньше, чем собирались');
    });

    test('подтягивание соседом снимается вместе с пересчётом срока', () {
      final prev = ReviewState(
        stability: 50,
        difficulty: 5,
        state: FsrsState.review,
        reps: 10,
        lapses: 1,
        step: 0,
        due: DateTime(2026, 1, 1).add(const Duration(days: 55)),
        lastReview: DateTime(2026, 1, 1),
        nudgedByNeighbour: true,
      );
      final next = fsrs.passiveExposure(
          prev, DateTime(2026, 1, 1).add(const Duration(days: 60)));

      expect(next, isNotNull);
      expect(next!.nudgedByNeighbour, isFalse,
          reason: 'метка «сосед сорвался» переживала пересчёт и висела на '
              'карточке, которую уже никто не подтягивает');
    });
  });

  group('провал на новой карте', () {
    test('срыв в learning не выкидывает минутный шаг', () {
      final fresh = ReviewState(
        stability: 3.173,
        difficulty: 5,
        state: FsrsState.learning,
        reps: 1,
        lapses: 0,
        step: 1,
        due: DateTime(2026, 1, 1, 10, 10),
        lastReview: DateTime(2026, 1, 1, 10),
      );

      final failed = fsrs.review(
          fresh, Rating.again, DateTime(2026, 1, 1, 10, 11),
          fuzzKey: 'c1');
      expect(failed.state, FsrsState.learning,
          reason: 'карта до review ни разу не доходила — переучивать нечего');
      expect(failed.step, 0);

      // Одного верного ответа мало: в learning два шага, оба надо подтвердить.
      final again = fsrs.review(
          failed, Rating.good, DateTime(2026, 1, 1, 10, 13),
          fuzzKey: 'c1');
      expect(again.state, FsrsState.learning,
          reason: 'иначе слово уходит в review после одного «хорошо» и '
              'внутридневные шаги пропадают насовсем');
    });

    test('срыв зрелой карты по-прежнему ведёт в relearning', () {
      final mature = ReviewState(
        stability: 40,
        difficulty: 6,
        state: FsrsState.review,
        reps: 20,
        lapses: 1,
        step: 0,
        due: DateTime(2026, 1, 1),
        lastReview: DateTime(2025, 12, 1),
      );
      final failed =
          fsrs.review(mature, Rating.again, DateTime(2026, 1, 2), fuzzKey: 'c');
      expect(failed.state, FsrsState.relearning);
      expect(failed.lapses, 2);
    });
  });
}
