import 'package:fern/theme/fern_shapes.dart';
import 'package:fern/widgets/coverage_ring.dart';
import 'package:fern/widgets/morph_shapes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double _bloomProgress(WidgetTester tester) => tester
    .widget<MorphShape>(find.byKey(const ValueKey('coverage-bloom')))
    .progress;

Widget _wrap(double known) => MaterialApp(
  home: Scaffold(
    body: Center(
      child: CoverageRing(
        known: known,
        color: Colors.green,
        trackColor: Colors.grey,
      ),
    ),
  ),
);

void main() {
  testWidgets('половина текста — ровный круг', (tester) async {
    await tester.pumpWidget(_wrap(FernShapes.coverageFloor));
    expect(_bloomProgress(tester), 0);
  });

  testWidgets('комфортные 95% — полный силуэт', (tester) async {
    await tester.pumpWidget(_wrap(FernShapes.coverageComfort));
    expect(_bloomProgress(tester), 1);
    await tester.pump(const Duration(milliseconds: 800));
  });

  testWidgets('на семидесяти процентах силуэт между кругом и полным',
      (tester) async {
    await tester.pumpWidget(_wrap(0.7));
    final t = _bloomProgress(tester);
    expect(t, greaterThan(0));
    expect(t, lessThan(1));
    await tester.pump(const Duration(milliseconds: 800));
  });
}
