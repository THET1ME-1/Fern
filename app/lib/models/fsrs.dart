import 'dart:math' as math;

import 'word_card.dart';

/// FSRS — Free Spaced Repetition Scheduler (актуальный стандарт, точнее SM-2).
///
/// Реализация с дефолтными весами FSRS-5 (`w[0..18]`). Считаем стабильность
/// памяти `S`, сложность `D`, извлекаемость `R` и из них — следующий интервал.
/// Персональная оптимизация весов по истории — отдельный (поздний) шаг; логи
/// уже можно копить в `ReviewLog`. См. `docs/learning-system.md` §3.
class Fsrs {
  Fsrs._();
  static final Fsrs instance = Fsrs._();

  /// Дефолтные веса FSRS-5.
  static const List<double> defaultWeights = [
    0.40255, 1.18385, 3.173, 15.69105, 7.1949, 0.5345, 1.4604, 0.0046,
    1.54575, 0.1192, 1.01925, 1.9395, 0.11, 0.29605, 2.2698, 0.2315,
    2.9898, 0.51655, 0.6621,
  ];

  final List<double> w = defaultWeights;

  /// Целевой уровень удержания (вероятность вспомнить на момент повтора).
  double requestRetention = 0.9;

  /// Максимальный интервал в днях.
  int maximumInterval = 36500;

  static const double _decay = -0.5;
  static const double _factor = 19.0 / 81.0; // 0.9^(1/decay) − 1

  /// Внутридневные шаги для новых/переучиваемых карт.
  static const List<Duration> learningSteps = [
    Duration(minutes: 1),
    Duration(minutes: 10),
  ];
  static const List<Duration> relearningSteps = [Duration(minutes: 10)];

  // ------------------------------- Формулы -------------------------------

  /// Извлекаемость через [t] дней при стабильности [s].
  double retrievability(double t, double s) {
    if (s <= 0) return 0;
    return math.pow(1 + _factor * t / s, _decay).toDouble();
  }

  /// Оптимальный интервал (дни) для стабильности [s] и целевого retention.
  int _intervalDays(double s) {
    final ivl = (s / _factor) * (math.pow(requestRetention, 1 / _decay) - 1);
    return ivl.round().clamp(1, maximumInterval);
  }

  Duration _reviewInterval(double s) => Duration(days: _intervalDays(s));

  double _initStability(Rating g) =>
      w[g.grade - 1].clamp(0.1, maximumInterval.toDouble());

  double _initDifficulty(int grade) {
    final d = w[4] - math.exp(w[5] * (grade - 1)) + 1;
    return d.clamp(1.0, 10.0);
  }

  double _nextDifficulty(double d, Rating g) {
    final delta = -w[6] * (g.grade - 3);
    // Линейное демпфирование (FSRS-5): чем выше D, тем меньше сдвиг.
    final damped = d + delta * (10 - d) / 9;
    // Возврат к среднему (к сложности «лёгкой» первой оценки).
    final reverted = w[7] * _initDifficulty(4) + (1 - w[7]) * damped;
    return reverted.clamp(1.0, 10.0);
  }

  double _successStability(double d, double s, double r, Rating g) {
    final hard = g == Rating.hard ? w[15] : 1.0;
    final easy = g == Rating.easy ? w[16] : 1.0;
    final inc = math.exp(w[8]) *
        (11 - d) *
        math.pow(s, -w[9]) *
        (math.exp(w[10] * (1 - r)) - 1) *
        hard *
        easy;
    return s * (1 + inc);
  }

  double _failStability(double d, double s, double r) {
    return w[11] *
        math.pow(d, -w[12]) *
        (math.pow(s + 1, w[13]) - 1) *
        math.exp(w[14] * (1 - r));
  }

  /// Краткосрочная стабильность (внутри дня / на шагах learning).
  double _shortTermStability(double s, Rating g) {
    return s * math.exp(w[17] * (g.grade - 3 + w[18]));
  }

  // ------------------------------- Планирование -------------------------------

  /// Возвращает НОВОЕ состояние карты после оценки [g] в момент [now].
  ReviewState review(ReviewState prev, Rating g, DateTime now) {
    final elapsedDays = prev.lastReview == null
        ? 0.0
        : math.max(0, now.difference(prev.lastReview!).inSeconds / 86400.0)
            .toDouble();

    double s;
    double d;
    if (prev.state == FsrsState.newCard) {
      d = _initDifficulty(g.grade);
      s = _initStability(g);
    } else {
      final r = retrievability(elapsedDays, prev.stability);
      d = _nextDifficulty(prev.difficulty, g);
      if (g == Rating.again) {
        s = _failStability(prev.difficulty, prev.stability, r);
      } else if (prev.state == FsrsState.learning ||
          prev.state == FsrsState.relearning ||
          elapsedDays < 1.0) {
        s = _shortTermStability(prev.stability, g);
      } else {
        s = _successStability(prev.difficulty, prev.stability, r, g);
      }
    }
    s = s.clamp(0.01, maximumInterval.toDouble());
    d = d.clamp(1.0, 10.0);

    final next = prev.copy()
      ..stability = s
      ..difficulty = d
      ..reps = prev.reps + 1
      ..lastReview = now;

    _schedule(prev, next, g, s, now);
    return next;
  }

  void _schedule(
      ReviewState prev, ReviewState next, Rating g, double s, DateTime now) {
    if (g == Rating.again) {
      if (prev.state == FsrsState.review) next.lapses = prev.lapses + 1;
      next.state = prev.state == FsrsState.newCard
          ? FsrsState.learning
          : FsrsState.relearning;
      final steps =
          next.state == FsrsState.relearning ? relearningSteps : learningSteps;
      next.step = 0;
      next.due = now.add(steps.first);
      return;
    }

    if (g == Rating.easy) {
      next.state = FsrsState.review;
      next.step = 0;
      next.due = now.add(_reviewInterval(s));
      return;
    }

    // hard или good.
    final inSteps = prev.state == FsrsState.newCard ||
        prev.state == FsrsState.learning ||
        prev.state == FsrsState.relearning;
    if (inSteps) {
      final relearn = prev.state == FsrsState.relearning;
      final steps = relearn ? relearningSteps : learningSteps;
      final curStep = prev.state == FsrsState.newCard ? 0 : prev.step;
      if (g == Rating.hard) {
        // Повторяем текущий шаг.
        next.state = relearn ? FsrsState.relearning : FsrsState.learning;
        next.step = curStep.clamp(0, steps.length - 1);
        next.due = now.add(steps[next.step]);
      } else {
        // good — продвигаем шаг; закончились — выпускаем в review.
        final nextStep = curStep + 1;
        if (nextStep >= steps.length) {
          next.state = FsrsState.review;
          next.step = 0;
          next.due = now.add(_reviewInterval(s));
        } else {
          next.state = relearn ? FsrsState.relearning : FsrsState.learning;
          next.step = nextStep;
          next.due = now.add(steps[nextStep]);
        }
      }
    } else {
      // Карта в review, успех (hard/good) → новый интервал.
      next.state = FsrsState.review;
      next.step = 0;
      next.due = now.add(_reviewInterval(s));
    }
  }

  /// Прогноз «когда вернётся» для каждой оценки (для подписей на кнопках),
  /// без изменения состояния карты.
  Map<Rating, Duration> preview(ReviewState prev, DateTime now) {
    final map = <Rating, Duration>{};
    for (final g in Rating.values) {
      final next = review(prev, g, now);
      final due = next.due ?? now;
      map[g] = due.difference(now);
    }
    return map;
  }
}
