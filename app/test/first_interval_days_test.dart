import 'package:flutter_test/flutter_test.dart';

import 'package:fern/models/fsrs.dart';
import 'package:fern/models/word_card.dart';

/// Число, ради которого существует персональная подгонка: через сколько дней
/// Fern впервые вернёт слово, встреченное сегодня. Экран объяснения показывает
/// его человеку, поэтому считать его должен планировщик, а не подпись.
void main() {
  test('стандартные веса дают известные сроки первого повтора', () {
    final fsrs = Fsrs.forSimulation(weights: null, retention: 0.9);

    // w0..w3 = 0.40255 / 1.18385 / 3.173 / 15.69105 дня, при цели 90%
    // интервал почти равен прочности.
    expect(fsrs.firstIntervalDays(Rating.again), 1);
    expect(fsrs.firstIntervalDays(Rating.hard), 1);
    expect(fsrs.firstIntervalDays(Rating.good), 3);
    expect(fsrs.firstIntervalDays(Rating.easy), 16);
  });

  test('цель выше — первый повтор ближе', () {
    final normal = Fsrs.forSimulation(retention: 0.9);
    final strict = Fsrs.forSimulation(retention: 0.97);

    expect(strict.firstIntervalDays(Rating.easy),
        lessThan(normal.firstIntervalDays(Rating.easy)));
  });

  test('персональные веса меняют срок', () {
    final base = List<double>.of(Fsrs.defaultWeights);
    final personal = List<double>.of(base)..[2] = 7.0; // «Хорошо» держится дольше

    expect(
      Fsrs.forSimulation(weights: personal).firstIntervalDays(Rating.good),
      greaterThan(
          Fsrs.forSimulation(weights: base).firstIntervalDays(Rating.good)),
    );
  });
}
