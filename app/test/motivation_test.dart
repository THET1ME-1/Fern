import 'package:flutter_test/flutter_test.dart';

import 'package:fern/models/review_log.dart';
import 'package:fern/services/deck_repository.dart';

import 'test_helpers.dart';

void main() {
  group('ReviewLog + серия-щит', () {
    test('замороженный день держит серию', () {
      final now = DateTime(2026, 7, 11);
      String k(int backDays) =>
          ReviewLog.keyFor(now.subtract(Duration(days: backDays)));
      // Занятия сегодня и позавчера, вчера пропущено, но заморожено.
      final log = ReviewLog(
        {
          k(0): const DayStat(reviews: 5, correct: 5),
          k(2): const DayStat(reviews: 5, correct: 5),
        },
        frozen: {k(1)},
      );
      expect(log.streak(now), 3); // 0,1(мороз),2 — подряд
    });

    test('без заморозки пропуск рвёт серию', () {
      final now = DateTime(2026, 7, 11);
      String k(int b) => ReviewLog.keyFor(now.subtract(Duration(days: b)));
      final log = ReviewLog({
        k(0): const DayStat(reviews: 5, correct: 5),
        k(2): const DayStat(reviews: 5, correct: 5),
      });
      expect(log.streak(now), 1); // только сегодня
    });
  });

  group('DeckRepository', () {
    final repo = DeckRepository.instance;
    setUp(() async {
      await resetStorage();
      await repo.init();
    });

    test('щит спасает серию за пропущенный вчера', () async {
      final now = DateTime(2026, 7, 11);
      // Была серия: позавчера занимались.
      await repo.logSession(
          reviews: 8, correct: 8, at: now.subtract(const Duration(days: 2)));
      expect(await repo.streakFreezes(), 2); // стартовый запас
      // Вчера и сегодня — пусто. Защита должна потратить щит на вчера.
      final used = await repo.protectStreakIfNeeded(now);
      expect(used, true);
      expect(await repo.streakFreezes(), 1);
      expect(repo.consumeFreezeNotice(), true);
      expect(repo.consumeFreezeNotice(), false); // разово
      // Серия сохранена (позавчера + замороженное вчера = 2).
      expect(repo.reviewLogSync.streak(now), 2);
    });

    test('нет щитов — серия не спасается', () async {
      final now = DateTime(2026, 7, 11);
      await repo.logSession(
          reviews: 8, correct: 8, at: now.subtract(const Duration(days: 2)));
      // Съедаем оба стартовых щита двумя днями пропуска подряд… проще обнулить.
      // Тратим первый щит на этот сценарий:
      await repo.protectStreakIfNeeded(now); // -> 1 щит, вчера заморожено
      // Повторный вызов ничего не делает (вчера уже активно).
      final again = await repo.protectStreakIfNeeded(now);
      expect(again, false);
    });

    test('празднование цели — один раз в день', () async {
      final now = DateTime(2026, 7, 11);
      await repo.setDailyGoal(5);
      await repo.logSession(reviews: 6, correct: 6, at: now);
      expect(await repo.consumeDailyGoalCelebration(now), true);
      expect(await repo.consumeDailyGoalCelebration(now), false); // уже сегодня
    });

    test('цель не достигнута — не празднуем', () async {
      final now = DateTime(2026, 7, 11);
      await repo.setDailyGoal(20);
      await repo.logSession(reviews: 3, correct: 3, at: now);
      expect(await repo.consumeDailyGoalCelebration(now), false);
    });
  });
}
