import 'package:flutter_test/flutter_test.dart';
import 'package:fern/services/book_analysis.dart';
import 'package:fern/services/reading_goal.dart';

/// Путь к свободному чтению книги: сколько слов осталось выучить и когда это
/// закончится при нынешнем темпе.
///
/// Считается по частотам: слова берутся от самых частых к редким, потому что
/// первые полсотни слов текста дают куда больше понимания, чем последние
/// пятьсот. Ради этого и существует весь платный сценарий, поэтому цифра
/// должна быть честной — обещание «28 дней», которое не сбудется, стоит
/// дороже, чем отсутствие обещания.
void main() {
  BookAnalysis analysis({
    required int totalTokens,
    required double coverage,
    required List<int> unknownFreqs,
  }) =>
      BookAnalysis(
        totalTokens: totalTokens,
        uniqueTypes: unknownFreqs.length + 10,
        unknownTypes: unknownFreqs.length,
        learningTypes: 5,
        knownTypes: 5,
        coverage: coverage,
        masteredCoverage: coverage,
        topUnknown: const [],
        unknownFreqs: unknownFreqs,
      );

  test('Слова берутся от частых к редким', () {
    // 100 слов текста, 90 покрыто. До 95% не хватает 5 слов текста; самые
    // частые незнакомые дают 3 и 2 — значит выучить нужно два слова.
    final goal = ReadingGoal.estimate(
      analysis(totalTokens: 100, coverage: 0.90, unknownFreqs: [3, 2, 2, 1, 1]),
      newPerDay: 12,
    );
    expect(goal.wordsToLearn, 2);
    expect(goal.days, 1);
    expect(goal.reached, isFalse);
  });

  test('Срок считается по дневному темпу', () {
    final goal = ReadingGoal.estimate(
      analysis(
        totalTokens: 1000,
        coverage: 0.5,
        unknownFreqs: List.filled(500, 1),
      ),
      newPerDay: 10,
    );
    // Не хватает 450 слов текста, каждое незнакомое встречается один раз —
    // значит 450 слов, по 10 в день это 45 дней.
    expect(goal.wordsToLearn, 450);
    expect(goal.days, 45);
  });

  test('Достигнутая цель не выдумывает работу', () {
    final goal = ReadingGoal.estimate(
      analysis(totalTokens: 100, coverage: 0.96, unknownFreqs: [1, 1]),
      newPerDay: 12,
    );
    expect(goal.reached, isTrue);
    expect(goal.wordsToLearn, 0);
    expect(goal.days, 0);
  });

  test('Пустая книга цели не ставит', () {
    final goal = ReadingGoal.estimate(BookAnalysis.empty, newPerDay: 12);
    expect(goal.reached, isTrue);
    expect(goal.wordsToLearn, 0);
  });

  test('Нулевой темп не роняет расчёт делением на ноль', () {
    final goal = ReadingGoal.estimate(
      analysis(totalTokens: 100, coverage: 0.5, unknownFreqs: List.filled(50, 1)),
      newPerDay: 0,
    );
    expect(goal.wordsToLearn, 45);
    expect(goal.days, greaterThan(0));
  });

  test('Цель по умолчанию — комфортные 95% текста', () {
    expect(ReadingGoal.comfortable, 0.95);
  });
}
