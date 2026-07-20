// Журнал занятий по дням — фундамент для серии (стрик), кольца дневной цели
// и статистики на экране «Прогресс».
//
// Храним агрегат по дню (сколько ответов и сколько верных), а не каждый повтор
// по отдельности — этого достаточно для всех экранов и дёшево по памяти/диску.

import '../utils/day.dart';

/// Итог одного дня.
class DayStat {
  final int reviews;
  final int correct;
  const DayStat({this.reviews = 0, this.correct = 0});

  DayStat plus({int reviews = 0, int correct = 0}) =>
      DayStat(reviews: this.reviews + reviews, correct: this.correct + correct);

  /// Доля верных 0..1 (0, если не было ответов).
  double get accuracy => reviews == 0 ? 0 : correct / reviews;
}

/// Журнал по дням. Ключ — локальная дата `yyyy-MM-dd`.
class ReviewLog {
  final Map<String, DayStat> days;

  /// Дни, «прикрытые» серией-щитом (заморозка): считаются активными для стрика,
  /// даже если занятий не было. Хранятся отдельно (в prefs), см. DeckRepository.
  final Set<String> frozen;

  const ReviewLog(this.days, {this.frozen = const {}});
  ReviewLog.empty()
      : days = {},
        frozen = const {};

  /// Ключ дня по локальному времени.
  static String keyFor(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  DayStat statOn(DateTime d) => days[keyFor(d)] ?? const DayStat();
  int reviewsOn(DateTime d) => statOn(d).reviews;

  /// День «активен» для серии: были занятия ИЛИ он прикрыт щитом (заморозкой).
  bool activeOn(DateTime d) => reviewsOn(d) > 0 || frozen.contains(keyFor(d));

  /// Серия: сколько дней подряд заканчиваются сегодня (или вчера) занятиями.
  ///
  /// Если сегодня ещё не занимались — серия НЕ рвётся до конца дня: считаем от
  /// вчера. Это привычный «прощающий» стрик (как в Duolingo). Замороженные щитом
  /// дни считаются активными.
  int streak(DateTime now) {
    var day = startOfDay(now);
    if (!activeOn(day)) {
      day = addDays(day, -1);
    }
    var count = 0;
    while (activeOn(day)) {
      count++;
      day = addDays(day, -1);
    }
    return count;
  }

  int get totalReviews =>
      days.values.fold(0, (s, v) => s + v.reviews);

  /// Всего дней с занятиями.
  int get daysStudied => days.values.where((v) => v.reviews > 0).length;

  /// Самая длинная серия занятий подряд за всю историю.
  int bestStreak() {
    final active = days.entries
        .where((e) => e.value.reviews > 0)
        .map((e) => e.key)
        .toList()
      ..sort();
    if (active.isEmpty) return 0;
    var best = 1, cur = 1;
    var prev = _parseKey(active.first);
    for (var i = 1; i < active.length; i++) {
      final d = _parseKey(active[i]);
      // Соседство считаем по календарю: в ночь перевода стрелок сутки короче
      // 24 часов, и разница «в днях» между соседними датами даёт ноль.
      cur = isNextDay(prev, d) ? cur + 1 : 1;
      if (cur > best) best = cur;
      prev = d;
    }
    return best;
  }

  static DateTime _parseKey(String k) {
    final p = k.split('-');
    return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
  }

  /// Максимальное число повторов за день среди [days] (для нормировки heatmap).
  int get maxDailyReviews =>
      days.values.fold(0, (m, v) => v.reviews > m ? v.reviews : m);

  Map<String, dynamic> toJson() =>
      {for (final e in days.entries) e.key: [e.value.reviews, e.value.correct]};

  factory ReviewLog.fromJson(Map<String, dynamic> j) {
    final m = <String, DayStat>{};
    j.forEach((k, v) {
      if (v is List && v.length >= 2) {
        m[k] = DayStat(
          reviews: (v[0] as num).toInt(),
          correct: (v[1] as num).toInt(),
        );
      }
    });
    return ReviewLog(m);
  }
}
