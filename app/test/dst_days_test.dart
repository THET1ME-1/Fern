import 'package:flutter_test/flutter_test.dart';

import 'package:fern/models/review_log.dart';
import 'package:fern/services/deck_repository.dart';
import 'package:fern/utils/day.dart';

import 'test_helpers.dart';

/// Сутки бывают не по 24 часа.
///
/// В ночь на 29 марта 2026 Европа переводит стрелки вперёд, и `subtract(
/// Duration(days: 1))` от 30 марта попадает в 28-е, пролетая мимо 29-го.
/// Осенью наоборот — сутки длятся 25 часов. Из семи языков приложения перевод
/// часов действует в пяти, так что дважды в год ломались серия, щиты и
/// календарь занятий.
///
/// ЭТОТ ФАЙЛ ГОНЯТЬ В ЗОНЕ С ПЕРЕВОДОМ ЧАСОВ, иначе он зелёный по построению:
///
///   TZ=Europe/Berlin flutter test test/dst_days_test.dart
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('календарная арифметика', () {
    test('предыдущий день — соседняя дата, а не «минус 24 часа»', () {
      expect(addDays(DateTime(2026, 3, 30), -1), DateTime(2026, 3, 29));
      expect(addDays(DateTime(2026, 10, 26), -1), DateTime(2026, 10, 25));
    });

    test('следующий день — соседняя дата', () {
      expect(addDays(DateTime(2026, 3, 29), 1), DateTime(2026, 3, 30));
      expect(addDays(DateTime(2026, 10, 25), 1), DateTime(2026, 10, 26));
    });

    test('шаг через границу месяца и года', () {
      expect(addDays(DateTime(2026, 3, 1), -1), DateTime(2026, 2, 28));
      expect(addDays(DateTime(2027, 1, 1), -1), DateTime(2026, 12, 31));
    });

    test('соседние дни распознаются как соседние', () {
      expect(isNextDay(DateTime(2026, 3, 29), DateTime(2026, 3, 30)), isTrue);
      expect(isNextDay(DateTime(2026, 10, 25), DateTime(2026, 10, 26)), isTrue);
      expect(isNextDay(DateTime(2026, 3, 28), DateTime(2026, 3, 30)), isFalse);
    });
  });

  group('серия занятий', () {
    ReviewLog fourDays() => ReviewLog({
          '2026-03-27': const DayStat(reviews: 5, correct: 5),
          '2026-03-28': const DayStat(reviews: 5, correct: 5),
          '2026-03-29': const DayStat(reviews: 5, correct: 5),
          '2026-03-30': const DayStat(reviews: 5, correct: 5),
        });

    test('перевод часов не съедает день серии', () {
      expect(fourDays().streak(DateTime(2026, 3, 30, 12)), 4);
    });

    test('перевод часов не рвёт лучшую серию', () {
      expect(fourDays().bestStreak(), 4);
    });

    test('осенний перевод часов тоже считается верно', () {
      final log = ReviewLog({
        '2026-10-24': const DayStat(reviews: 3, correct: 3),
        '2026-10-25': const DayStat(reviews: 3, correct: 3),
        '2026-10-26': const DayStat(reviews: 3, correct: 3),
      });
      expect(log.streak(DateTime(2026, 10, 26, 12)), 3);
      expect(log.bestStreak(), 3);
    });
  });

  group('щит серии', () {
    setUp(resetStorage);

    test('щит спасает пропущенный день перевода часов', () async {
      final repo = DeckRepository.instance;
      await repo.init();
      // Занимались 27 и 28 марта, 29-е пропустили. Утро 30-го: серия висит на
      // волоске, для этого щит и заведён.
      await repo.logSession(
          reviews: 2, correct: 2, at: DateTime(2026, 3, 27, 10));
      await repo.logSession(
          reviews: 2, correct: 2, at: DateTime(2026, 3, 28, 10));

      final before = await repo.streakFreezes();
      final spent = await repo.protectStreakIfNeeded(DateTime(2026, 3, 30, 9));

      expect(spent, isTrue, reason: 'вчера (29-е) пропущено, серия была');
      expect(await repo.streakFreezes(), before - 1);
      final log = await repo.reviewLog();
      expect(log.streak(DateTime(2026, 3, 30, 9)), 3,
          reason: '27, 28 и прикрытое щитом 29-е');
    });

    test('щит не тратится, когда вчера занимались', () async {
      final repo = DeckRepository.instance;
      await repo.init();
      await repo.logSession(
          reviews: 2, correct: 2, at: DateTime(2026, 3, 28, 10));
      await repo.logSession(
          reviews: 2, correct: 2, at: DateTime(2026, 3, 29, 10));

      final before = await repo.streakFreezes();
      final spent = await repo.protectStreakIfNeeded(DateTime(2026, 3, 30, 9));

      expect(spent, isFalse, reason: 'вчерашний день закрыт занятием');
      expect(await repo.streakFreezes(), before);
    });
  });
}
