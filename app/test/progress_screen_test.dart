import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fern/l10n/locale_controller.dart';
import 'package:fern/progress_screen.dart';
import 'package:fern/services/deck_repository.dart';

import 'test_helpers.dart';

void main() {
  final repo = DeckRepository.instance;

  testWidgets('Экран прогресса: активность и серия рендерятся без ошибок',
      (WidgetTester tester) async {
    await resetStorage();
    await repo.init();
    await LocaleController.instance.setCode('ru');
    await repo.seedDemoIfNeeded();
    await repo.logSession(reviews: 9, correct: 7);

    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: ProgressScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Активность'), findsOneWidget);
    expect(find.text('Серия'), findsOneWidget);
    expect(find.text('меньше'), findsOneWidget); // легенда heatmap
  });
}
