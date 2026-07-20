import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fern/l10n/locale_controller.dart';
import 'package:fern/l10n/strings.dart';
import 'package:fern/services/reading_goal.dart';
import 'package:fern/widgets/reading_goal_card.dart';

import 'test_helpers.dart';

/// Карточка пути к книге. Это и есть витрина Fern Pro: она стоит на цифрах
/// собственной книги человека, а не на списке форматов файлов.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await resetStorage();
    await LocaleController.instance.setCode('ru');
  });

  Future<void> pump(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
    await tester.pumpAndSettle();
  }

  const goal = ReadingGoal(
    wordsToLearn: 340,
    days: 28,
    coverage: 0.78,
    target: 0.95,
  );

  testWidgets('Показывает цифры книги: сколько слов и за сколько дней',
      (tester) async {
    await pump(tester, const ReadingGoalCard(goal: goal, pro: false));

    expect(find.textContaining('340'), findsWidgets);
    expect(find.textContaining('28'), findsWidgets);
    expect(find.textContaining('78'), findsWidgets);
  });

  testWidgets('Бесплатному предлагает Pro, а не тупик', (tester) async {
    var opened = false;
    await pump(
      tester,
      ReadingGoalCard(goal: goal, pro: false, onOpenPro: () => opened = true),
    );

    await tester.tap(find.text(tr('goal_open_pro')));
    await tester.pumpAndSettle();
    expect(opened, isTrue);
  });

  testWidgets('Купившему даёт учить слова книги', (tester) async {
    var studied = false;
    await pump(
      tester,
      ReadingGoalCard(goal: goal, pro: true, onStudy: () => studied = true),
    );

    expect(find.text(tr('goal_open_pro')), findsNothing);
    await tester.tap(find.text(tr('goal_study')));
    await tester.pumpAndSettle();
    expect(studied, isTrue);
  });

  testWidgets('Достигнутая цель не зовёт платить', (tester) async {
    await pump(
      tester,
      const ReadingGoalCard(
        goal: ReadingGoal(
            wordsToLearn: 0, days: 0, coverage: 0.96, target: 0.95),
        pro: false,
      ),
    );

    expect(find.text(tr('goal_reached')), findsOneWidget);
    expect(find.text(tr('goal_open_pro')), findsNothing);
  });
}
