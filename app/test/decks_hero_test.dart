import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fern/decks_screen.dart';
import 'package:fern/l10n/locale_controller.dart';
import 'package:fern/services/deck_repository.dart';

import 'test_helpers.dart';

void main() {
  final repo = DeckRepository.instance;

  testWidgets('Дневная сводка показывает серию и повторы за сегодня',
      (WidgetTester tester) async {
    await resetStorage();
    await repo.init();
    await LocaleController.instance.setCode('ru');
    // Сид грузит ассет (rootBundle), а он не работает в FakeAsync — гоняем
    // через runAsync (реальный event loop).
    await tester.runAsync(() async {
      await repo.seedDemoIfNeeded();
      await repo.logSession(reviews: 7, correct: 6); // занятие сегодня
    });

    tester.view.physicalSize = const Size(1000, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: DecksScreen()));
    await tester.pumpAndSettle();

    // Заголовок сводки, число повторов в кольце и подпись серии.
    expect(find.text('Сегодня'), findsOneWidget);
    expect(find.text('7'), findsWidgets); // кольцо: повторов сегодня
    expect(find.text('дн. подряд'), findsOneWidget); // серия активна
  });
}
