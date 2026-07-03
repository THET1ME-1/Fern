import 'package:flutter_test/flutter_test.dart';

import 'package:fern/models/achievement.dart';
import 'package:fern/models/review_log.dart';
import 'package:fern/models/word_card.dart';

void main() {
  test('достижения отражают накопленную статистику', () {
    final day = DateTime(2026, 7, 3);
    final log = ReviewLog({
      ReviewLog.keyFor(day): const DayStat(reviews: 60, correct: 50),
    });
    final cards = <WordCard>[];

    final items = buildAchievements(log, cards, day);

    final first = items.firstWhere((a) => a.target == 1);
    expect(first.earned, true, reason: '60 повторов ≥ 1');

    final warmup = items.firstWhere((a) => a.target == 50 && a.current == 60);
    expect(warmup.earned, true, reason: '60 ≥ 50');

    final worker = items.firstWhere((a) => a.target == 500);
    expect(worker.earned, false, reason: '60 < 500');
    expect(worker.progress, closeTo(60 / 500, 0.001));
  });

  test('пустая статистика — ничего не получено', () {
    final items = buildAchievements(ReviewLog.empty(), [], DateTime(2026, 7, 3));
    expect(items.every((a) => !a.earned), true);
  });
}
