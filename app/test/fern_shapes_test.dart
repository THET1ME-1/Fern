import 'package:fern/theme/fern_shapes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Обложки колод', () {
    test('индекс идёт по кругу и не падает на отрицательных', () {
      expect(FernShapes.deckCovers.length, greaterThanOrEqualTo(6));
      expect(
        FernShapes.deckCover(0),
        same(FernShapes.deckCover(FernShapes.deckCovers.length)),
      );
      expect(FernShapes.deckCover(-1), same(FernShapes.deckCover(1)));
    });
  });

  group('Покрытие книги', () {
    test('до половины текста — ровный круг', () {
      expect(FernShapes.coverageMorph(0), 0);
      expect(FernShapes.coverageMorph(0.5), 0);
    });

    test('комфортные 95% дают полный силуэт', () {
      expect(FernShapes.coverageMorph(0.95), 1);
      expect(FernShapes.coverageMorph(1), 1);
    });

    test('между половиной и 95% растёт монотонно', () {
      final a = FernShapes.coverageMorph(0.6);
      final b = FernShapes.coverageMorph(0.78);
      final c = FernShapes.coverageMorph(0.9);
      expect(a, greaterThan(0));
      expect(b, greaterThan(a));
      expect(c, greaterThan(b));
      expect(c, lessThan(1));
    });
  });

  group('Вехи серии', () {
    test('ступени меняются на 7, 30 и 100 днях', () {
      expect(FernShapes.streakStep(0), 0);
      expect(FernShapes.streakStep(6), 0);
      expect(FernShapes.streakStep(7), 1);
      expect(FernShapes.streakStep(29), 1);
      expect(FernShapes.streakStep(30), 2);
      expect(FernShapes.streakStep(99), 2);
      expect(FernShapes.streakStep(100), 3);
      expect(FernShapes.streakStep(4000), 3);
    });

    test('у каждой ступени своя форма', () {
      final shapes = [
        for (var i = 0; i < 4; i++) FernShapes.streakShape(i),
      ];
      expect(shapes.toSet().length, 4);
    });

    test('отрицательная серия не роняет расчёт', () {
      expect(FernShapes.streakStep(-3), 0);
    });
  });

  group('Ожидание', () {
    test('в кольце ожидания минимум три силуэта и нет повторов подряд', () {
      final ring = FernShapes.waitingRing;
      expect(ring.length, greaterThanOrEqualTo(3));
      for (var i = 0; i < ring.length; i++) {
        expect(ring[i], isNot(same(ring[(i + 1) % ring.length])));
      }
    });
  });
}
