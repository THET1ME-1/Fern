import 'package:fern/widgets/goal_ring.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: Center(child: child)));

void main() {
  const bloom = ValueKey('goal-bloom');

  testWidgets('пока цель не взята, силуэт не распускается', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const GoalRing(
          progress: 0.6,
          color: Colors.green,
          trackColor: Colors.grey,
        ),
      ),
    );
    expect(find.byKey(bloom), findsNothing);
  });

  testWidgets('на взятой цели силуэт появляется', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const GoalRing(
          progress: 1,
          color: Colors.green,
          trackColor: Colors.grey,
        ),
      ),
    );
    expect(find.byKey(bloom), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 800));
  });

  testWidgets('перебор цели тоже празднуется', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const GoalRing(
          progress: 1.8,
          color: Colors.green,
          trackColor: Colors.grey,
        ),
      ),
    );
    expect(find.byKey(bloom), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 800));
  });

  testWidgets('флагом можно погасить праздник', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const GoalRing(
          progress: 1,
          celebrate: false,
          color: Colors.green,
          trackColor: Colors.grey,
        ),
      ),
    );
    expect(find.byKey(bloom), findsNothing);
  });
}
