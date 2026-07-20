import 'dart:math';

import '../models/fsrs.dart';
import '../models/review_event.dart';
import '../models/word_card.dart';

/// Насколько хорошо планировщик предсказывает исход повтора.
class ScheduleQuality {
  /// Сколько зрелых повторов участвовало в проверке.
  final int samples;

  /// Логарифмический лосс: меньше — точнее. Главная метрика сравнения.
  final double logLoss;

  /// Ошибка калибровки по бинам: обещали 90% — вспомнили 90%?
  final double calibrationError;

  /// Среднее предсказание («сколько мы обещали»).
  final double predicted;

  /// Фактическая доля вспомненных («сколько вышло»).
  final double actual;

  const ScheduleQuality({
    required this.samples,
    required this.logLoss,
    required this.calibrationError,
    required this.predicted,
    required this.actual,
  });

  static const ScheduleQuality empty = ScheduleQuality(
    samples: 0,
    logLoss: 0,
    calibrationError: 0,
    predicted: 0,
    actual: 0,
  );

  bool get hasData => samples > 0;

  /// Планировщик обещает больше, чем выходит (переоценивает память).
  bool get tooOptimistic => predicted - actual > 0.02;
}

/// Лаборатория расписания: прогоняет РЕАЛЬНУЮ историю повторов через заданные
/// веса и меряет, насколько точны были предсказания.
///
/// Чего здесь нет и быть не может: честного ответа «а сколько бы повторов вышло
/// при других интервалах». Поставь планировщик другой срок — и мы не знаем,
/// вспомнил бы человек в тот день или нет; такой ответ пришлось бы выдумать.
/// Зато полностью измеримо другое: планировщик на каждом повторе заявлял
/// вероятность вспомнить, а история знает, что случилось на самом деле. Отсюда
/// и метрики — лог-лосс и калибровка, как в самом проекте FSRS.
class ScheduleLab {
  const ScheduleLab._();

  /// Минимум зрелых повторов, ниже которого сравнивать бессмысленно.
  static const int minSamples = 50;

  /// Число бинов калибровки (предсказания 0..1 раскладываются по ним).
  static const int _bins = 10;

  /// Прогон истории с заданными весами.
  ///
  /// [events] — сырой журнал (ожидается порядок «по карте, затем по времени»,
  /// как его отдаёт `DeckRepository.reviewEvents`).
  static ScheduleQuality evaluate(
    List<ReviewEvent> events, {
    List<double>? weights,
    double retention = 0.9,
  }) {
    final fsrs = Fsrs.forSimulation(weights: weights, retention: retention);
    final states = <String, ReviewState>{};

    var n = 0;
    var loss = 0.0;
    var sumPredicted = 0.0;
    var recalledCount = 0;
    final binSum = List<double>.filled(_bins, 0);
    final binHits = List<int>.filled(_bins, 0);
    final binCount = List<int>.filled(_bins, 0);

    for (final e in events) {
      final at = DateTime.fromMillisecondsSinceEpoch(e.ts);
      final prev = states[e.cardId];

      // Зрелый повтор с известным состоянием — единственное, что можно
      // проверять: у новых карт предсказывать ещё нечего.
      if (prev != null &&
          e.stateBefore == FsrsState.review.index &&
          e.elapsedDays > 0 &&
          prev.stability > 0) {
        final r = fsrs
            .retrievability(e.elapsedDays, prev.stability)
            .clamp(1e-6, 1 - 1e-6);
        n++;
        sumPredicted += r;
        if (e.recalled) recalledCount++;
        loss += e.recalled ? -log(r) : -log(1 - r);

        final bin = min(_bins - 1, (r * _bins).floor());
        binSum[bin] += r;
        binCount[bin]++;
        if (e.recalled) binHits[bin]++;
      }

      states[e.cardId] = fsrs.review(
        prev ?? ReviewState(),
        Rating.values[(e.grade - 1).clamp(0, 3)],
        at,
        fuzz: false,
      );
    }

    if (n == 0) return ScheduleQuality.empty;

    var calibration = 0.0;
    for (var i = 0; i < _bins; i++) {
      if (binCount[i] == 0) continue;
      final meanPredicted = binSum[i] / binCount[i];
      final meanActual = binHits[i] / binCount[i];
      calibration += binCount[i] * pow(meanPredicted - meanActual, 2);
    }

    return ScheduleQuality(
      samples: n,
      logLoss: loss / n,
      calibrationError: sqrt(calibration / n),
      predicted: sumPredicted / n,
      actual: recalledCount / n,
    );
  }

  /// Сравнение вариантов весов на одной истории.
  static Map<String, ScheduleQuality> compare(
    List<ReviewEvent> events,
    Map<String, List<double>?> variants, {
    double retention = 0.9,
  }) =>
      {
        for (final entry in variants.entries)
          entry.key: evaluate(
            events,
            weights: entry.value,
            retention: retention,
          ),
      };

  /// Стало ли предсказание точнее, в процентах (положительное — да).
  /// Считаем по лог-лоссу: он наказывает и самоуверенность, и вялость.
  static double improvementPercent(
    ScheduleQuality before,
    ScheduleQuality after,
  ) {
    if (!before.hasData || !after.hasData || before.logLoss <= 0) return 0;
    return (before.logLoss - after.logLoss) / before.logLoss * 100;
  }

  /// Стоит ли применять новые веса: данных достаточно и предсказание не хуже.
  static bool worthApplying(
    ScheduleQuality before,
    ScheduleQuality after, {
    double minGainPercent = 1.0,
  }) {
    if (after.samples < minSamples) return false;
    return improvementPercent(before, after) >= minGainPercent;
  }
}
