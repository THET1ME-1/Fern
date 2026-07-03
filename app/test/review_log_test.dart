import 'package:flutter_test/flutter_test.dart';

import 'package:fern/models/review_log.dart';
import 'package:fern/services/deck_repository.dart';

import 'test_helpers.dart';

void main() {
  group('ReviewLog.streak', () {
    ReviewLog logWith(List<DateTime> days) {
      final m = <String, DayStat>{};
      for (final d in days) {
        m[ReviewLog.keyFor(d)] = const DayStat(reviews: 5, correct: 4);
      }
      return ReviewLog(m);
    }

    final now = DateTime(2026, 7, 3, 15);

    test('нет занятий — серия 0', () {
      expect(ReviewLog.empty().streak(now), 0);
    });

    test('занимались сегодня и 2 дня до — серия 3', () {
      final log = logWith([
        now,
        now.subtract(const Duration(days: 1)),
        now.subtract(const Duration(days: 2)),
      ]);
      expect(log.streak(now), 3);
    });

    test('сегодня ещё не занимались, но вчера и позавчера — серия 2 (не рвётся)',
        () {
      final log = logWith([
        now.subtract(const Duration(days: 1)),
        now.subtract(const Duration(days: 2)),
      ]);
      expect(log.streak(now), 2);
    });

    test('пропуск дня рвёт серию', () {
      final log = logWith([
        now,
        now.subtract(const Duration(days: 2)), // вчера пропущено
      ]);
      expect(log.streak(now), 1);
    });
  });

  group('logSession через репозиторий', () {
    final repo = DeckRepository.instance;
    setUp(resetStorage);

    test('копит повторы за день и переживает перезапуск', () async {
      final today = DateTime(2026, 7, 3, 10);
      await repo.logSession(reviews: 8, correct: 6, at: today);
      await repo.logSession(reviews: 4, correct: 4, at: today);

      var log = await repo.reviewLog();
      expect(log.statOn(today).reviews, 12);
      expect(log.statOn(today).correct, 10);

      // Перезапуск: кэш сброшен, стор сохранён.
      repo.resetForTest();
      await repo.init();
      log = await repo.reviewLog();
      expect(log.statOn(today).reviews, 12, reason: 'журнал должен сохраниться');
    });
  });
}
