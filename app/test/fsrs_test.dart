import 'package:flutter_test/flutter_test.dart';

import 'package:fern/models/fsrs.dart';
import 'package:fern/models/word_card.dart';

void main() {
  final fsrs = Fsrs.instance;

  test('новая карта + good → learning, срок в пределах дня', () {
    final now = DateTime(2026, 1, 1, 12);
    final s = fsrs.review(ReviewState(), Rating.good, now);
    expect(s.state, FsrsState.learning);
    expect(s.stability, greaterThan(0));
    expect(s.due!.isAfter(now), true);
    expect(s.due!.difference(now).inHours < 24, true);
  });

  test('два good подряд выпускают карту в review с интервалом ≥ 1 день', () {
    final now = DateTime(2026, 1, 1, 12);
    var s = fsrs.review(ReviewState(), Rating.good, now);
    s = fsrs.review(s, Rating.good, now.add(const Duration(minutes: 10)));
    expect(s.state, FsrsState.review);
    expect(s.due!.difference(now).inDays >= 1, true);
  });

  test('easy на новой карте сразу выпускает в review', () {
    final now = DateTime(2026, 1, 1, 12);
    final s = fsrs.review(ReviewState(), Rating.easy, now);
    expect(s.state, FsrsState.review);
  });

  test('again в review повышает lapses и переводит в relearning', () {
    final now = DateTime(2026, 1, 1, 12);
    final s = ReviewState(
      state: FsrsState.review,
      stability: 10,
      difficulty: 5,
      reps: 3,
      lastReview: now.subtract(const Duration(days: 5)),
    );
    final s2 = fsrs.review(s, Rating.again, now);
    expect(s2.state, FsrsState.relearning);
    expect(s2.lapses, 1);
  });

  test('preview даёт 4 оценки, easy ≥ good', () {
    final now = DateTime(2026, 1, 1, 12);
    final s = ReviewState(
      state: FsrsState.review,
      stability: 10,
      difficulty: 5,
      reps: 3,
      lastReview: now.subtract(const Duration(days: 8)),
    );
    final p = fsrs.preview(s, now);
    expect(p.length, 4);
    expect(p[Rating.easy]! >= p[Rating.good]!, true);
  });

  test('fuzz разбрасывает длинный интервал в пределах ~±8%, но не короткий', () {
    final now = DateTime(2026, 1, 1, 12);
    final s = ReviewState(
      state: FsrsState.review,
      stability: 100, // ⇒ базовый интервал ~100 дней
      difficulty: 5,
      reps: 6,
      lastReview: now.subtract(const Duration(days: 100)),
    );
    final base = fsrs.review(s, Rating.good, now, fuzz: false).due!;
    final fuzzed = fsrs.review(s, Rating.good, now, fuzz: true).due!;
    final baseDays = base.difference(now).inDays;
    final fuzzedDays = fuzzed.difference(now).inDays;
    // Сдвиг детерминирован и ограничен ~8% (минимум ±1 день).
    expect((fuzzedDays - baseDays).abs() <= (baseDays * 0.08).round() + 1, true);
    // Тот же вход → тот же результат (воспроизводимость).
    expect(fsrs.review(s, Rating.good, now, fuzz: true).due, fuzzed);
    expect(fsrs.review(s, Rating.good, now, fuzz: true).due!.difference(now).inDays,
        fuzzedDays);
  });
}
