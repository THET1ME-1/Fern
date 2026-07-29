import 'package:fern/widgets/morph_shapes.dart';
import 'package:fern/widgets/session_progress.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(
      home: Scaffold(
        body: Center(child: SizedBox(width: 300, child: child)),
      ),
    );

void main() {
  testWidgets('короткая сессия показывается засечками по числу карточек',
      (tester) async {
    await tester.pumpWidget(_wrap(const SessionProgress(done: 3, total: 10)));
    expect(find.byType(MorphShape), findsNWidgets(10));
  });

  testWidgets('засечка занимает высоту и ширину, а не схлопывается в точку',
      (tester) async {
    await tester.pumpWidget(_wrap(const SessionProgress(done: 3, total: 10)));
    final box = tester.getSize(find.byKey(const ValueKey('seg-0')));
    expect(box.height, greaterThan(6));
    expect(box.width, greaterThan(6));
  });

  testWidgets('пройденные засечки налиты, остальные нет', (tester) async {
    await tester.pumpWidget(_wrap(const SessionProgress(done: 3, total: 10)));
    final done = tester
        .widgetList<MorphShape>(find.byType(MorphShape))
        .where((w) => w.progress == 1)
        .length;
    expect(done, 3);
  });

  testWidgets('длинная сессия идёт полосой', (tester) async {
    await tester.pumpWidget(_wrap(const SessionProgress(done: 4, total: 40)));
    expect(find.byType(MorphShape), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 700));
  });
}
