import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fern/l10n/locale_controller.dart';
import 'package:fern/onboarding_screen.dart';
import 'package:fern/services/deck_repository.dart';

import 'test_helpers.dart';

void main() {
  final repo = DeckRepository.instance;

  testWidgets('онбординг: «Начать» завершает и ставит флаг', (tester) async {
    await resetStorage();
    await repo.init();
    await LocaleController.instance.setCode('ru');

    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var done = false;
    await tester.pumpWidget(
      MaterialApp(home: OnboardingScreen(onDone: () => done = true)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Что хочешь учить?'), findsOneWidget);

    // «Начать» кладёт готовый набор выбранного языка, а тот читается из
    // ассетов — rootBundle в FakeAsync виснет, поэтому только runAsync.
    await tester.runAsync(() async {
      await tester.tap(find.text('Начать'));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(done, true, reason: 'onDone должен вызваться');
    expect(await repo.onboarded(), true, reason: 'флаг онбординга выставлен');
  });
}
