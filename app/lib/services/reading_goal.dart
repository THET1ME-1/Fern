import 'dart:math' as math;

import 'book_analysis.dart';

/// Путь к свободному чтению книги: сколько слов осталось и когда это кончится.
///
/// Ради этой цифры и существует платный сценарий, поэтому она считается
/// честно: слова берутся от самых частых к редким (первые полсотни дают больше
/// понимания, чем последние пятьсот), а срок — из настоящего дневного лимита
/// новых слов, а не из круглого числа для витрины. Обещание «28 дней», которое
/// не сбудется, стоит дороже, чем отсутствие обещания.
class ReadingGoal {
  /// Доля слов текста, при которой чтение перестаёт спотыкаться о словарь.
  /// Порог общепринятый в исследованиях по объёму словаря при чтении.
  static const double comfortable = 0.95;

  /// Сколько уникальных слов осталось выучить.
  final int wordsToLearn;

  /// За сколько дней при нынешнем темпе.
  final int days;

  /// Покрытие книги сейчас (0..1).
  final double coverage;

  /// Цель, к которой считали (0..1).
  final double target;

  const ReadingGoal({
    required this.wordsToLearn,
    required this.days,
    required this.coverage,
    required this.target,
  });

  /// Цель уже достигнута — книгу можно читать без словаря.
  bool get reached => wordsToLearn == 0;

  static ReadingGoal estimate(
    BookAnalysis analysis, {
    required int newPerDay,
    double target = comfortable,
  }) {
    final total = analysis.totalTokens;
    if (total == 0) {
      return ReadingGoal(
          wordsToLearn: 0, days: 0, coverage: analysis.coverage, target: target);
    }

    // Сколько слов текста (с повторами) не хватает до цели.
    final missing = (target - analysis.coverage) * total;
    if (missing <= 0) {
      return ReadingGoal(
          wordsToLearn: 0, days: 0, coverage: analysis.coverage, target: target);
    }

    // Частые слова закрывают разрыв быстрее, поэтому идём по убыванию частоты.
    final freqs = [...analysis.unknownFreqs]..sort((a, b) => b.compareTo(a));
    var covered = 0;
    var words = 0;
    for (final freq in freqs) {
      if (covered >= missing) break;
      covered += freq;
      words++;
    }

    // Темп берём хотя бы единичным: ноль новых слов в день означает не
    // «никогда», а «человек ещё не настроил лимит».
    final pace = math.max(1, newPerDay);
    return ReadingGoal(
      wordsToLearn: words,
      days: (words / pace).ceil(),
      coverage: analysis.coverage,
      target: target,
    );
  }
}
