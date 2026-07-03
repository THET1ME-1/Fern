// Журнал занятий по дням — фундамент для серии (стрик), кольца дневной цели
// и статистики на экране «Прогресс».
//
// Храним агрегат по дню (сколько ответов и сколько верных), а не каждый повтор
// по отдельности — этого достаточно для всех экранов и дёшево по памяти/диску.

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
  const ReviewLog(this.days);
  ReviewLog.empty() : days = {};

  /// Ключ дня по локальному времени.
  static String keyFor(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  DayStat statOn(DateTime d) => days[keyFor(d)] ?? const DayStat();
  int reviewsOn(DateTime d) => statOn(d).reviews;

  /// Серия: сколько дней подряд заканчиваются сегодня (или вчера) занятиями.
  ///
  /// Если сегодня ещё не занимались — серия НЕ рвётся до конца дня: считаем от
  /// вчера. Это привычный «прощающий» стрик (как в Duolingo).
  int streak(DateTime now) {
    var day = DateTime(now.year, now.month, now.day);
    if (reviewsOn(day) == 0) {
      day = day.subtract(const Duration(days: 1));
    }
    var count = 0;
    while (reviewsOn(day) > 0) {
      count++;
      day = day.subtract(const Duration(days: 1));
    }
    return count;
  }

  int get totalReviews =>
      days.values.fold(0, (s, v) => s + v.reviews);

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
