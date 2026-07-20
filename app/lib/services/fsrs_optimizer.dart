import 'dart:math';

import '../models/fsrs.dart';
import '../models/review_event.dart';
import '../models/word_card.dart';

/// Результат подгонки персональных весов FSRS по истории повторов.
class FsrsOptimizeResult {
  /// Полный набор из 19 весов (дефолтные, где подгонка невозможна).
  final List<double> weights;

  /// Измеренное удержание на зрелых повторах (доля «вспомнил», 0..1).
  final double measuredRetention;

  /// Сколько зрелых повторов участвовало в измерении удержания.
  final int reviewSamples;

  /// Сколько из начальных стабильностей (w0..w3) удалось подогнать.
  final int fittedRatings;

  /// Достаточно ли данных, чтобы применять результат.
  final bool enough;

  const FsrsOptimizeResult({
    required this.weights,
    required this.measuredRetention,
    required this.reviewSamples,
    required this.fittedRatings,
    required this.enough,
  });
}

/// Персональный оптимизатор FSRS.
///
/// Полная оптимизация всех 19 весов — это градиентный спуск по FSRS-лоссу
/// (research-grade). Здесь — надёжный и безопасный ПОДмножественный вариант:
/// подгоняем НАЧАЛЬНЫЕ стабильности `w[0..3]` (по одной на каждую оценку первого
/// показа) по реальной кривой забывания пользователя и измеряем фактическое
/// удержание. Остальные веса оставляем дефолтными FSRS-5 — это исключает риск,
/// что кривой оптимизатор испортит планирование, но уже персонализирует самое
/// влияющее на новые карты. Полная оптимизация — следующий шаг.
class FsrsOptimizer {
  const FsrsOptimizer._();

  /// Минимум событий вообще, чтобы вывод был осмысленным.
  static const int minTotal = 200;

  /// Минимум пар (первый рейтинг → исход) на одну оценку для подгонки.
  static const int minPerRating = 20;

  static const double _factor = 19.0 / 81.0;
  static const double _decay = -0.5;

  static FsrsOptimizeResult optimize(List<ReviewEvent> events) {
    // 1) Фактическое удержание — на зрелых (review) повторах.
    var revTotal = 0, revRecalled = 0;
    for (final e in events) {
      if (e.stateBefore == FsrsState.review.index) {
        revTotal++;
        if (e.recalled) revRecalled++;
      }
    }
    final measured = revTotal == 0 ? 0.0 : revRecalled / revTotal;

    // 2) Пары «первый рейтинг → исход второго повтора» (события уже
    // отсортированы по карте и времени).
    final byRating = <int, List<(double, bool)>>{
      1: [],
      2: [],
      3: [],
      4: [],
    };
    String? curCard;
    var firstGrade = 0;
    var captured = false;
    for (final e in events) {
      if (e.cardId != curCard) {
        curCard = e.cardId;
        firstGrade = 0;
        captured = false;
      }
      if (firstGrade == 0) {
        if (e.stateBefore == FsrsState.newCard.index) firstGrade = e.grade;
        continue;
      }
      if (captured) continue;
      // Ждём ПЕРВЫЙ МЕЖСУТОЧНЫЙ показ. Вторым событием в Fern всегда идёт
      // внутридневной шаг: новая карта плюс «Хорошо» — это срок через десять
      // минут. Прочность в днях подгонялась против 0.007 дня, оптимум упирался
      // в границу сетки, и гейт качества отбивал результат — кнопка
      // «Оптимизировать» не срабатывала никогда. Вдобавок внутридневной шаг
      // почти всегда «вспомнил», поэтому подгонка не отличала выученное слово
      // от забытого.
      if (e.elapsedDays < 1.0) continue;
      byRating[firstGrade]!.add((e.elapsedDays, e.recalled));
      captured = true;
    }

    final w = List<double>.of(Fsrs.defaultWeights);
    var fitted = 0;
    for (var g = 1; g <= 4; g++) {
      final s = _fitStability(byRating[g]!);
      if (s != null) {
        w[g - 1] = s;
        fitted++;
      }
    }

    return FsrsOptimizeResult(
      weights: w,
      measuredRetention: measured,
      reviewSamples: revTotal,
      fittedRatings: fitted,
      enough: events.length >= minTotal && fitted > 0,
    );
  }

  /// Подгоняет стабильность S, минимизируя лог-лосс кривой забывания
  /// R(t,S) = (1 + F·t/S)^decay против фактических исходов (recalled). Сетка по
  /// логарифму — просто и устойчиво (одномерная задача). null — мало данных.
  static double? _fitStability(List<(double, bool)> pairs) {
    final data = [for (final p in pairs) if (p.$1 > 0) p];
    if (data.length < minPerRating) return null;

    double loss(double s) {
      var l = 0.0;
      for (final p in data) {
        final r = pow(1 + _factor * p.$1 / s, _decay)
            .toDouble()
            .clamp(1e-4, 1 - 1e-4);
        l += p.$2 ? -log(r) : -log(1 - r);
      }
      return l;
    }

    var best = 1.0;
    var bestLoss = double.infinity;
    for (var i = 0; i <= 80; i++) {
      final s = pow(10, -1 + (i / 80) * 3).toDouble(); // 10^-1 .. 10^2
      final l = loss(s);
      if (l < bestLoss) {
        bestLoss = l;
        best = s;
      }
    }
    return best.clamp(0.1, 100.0);
  }
}
