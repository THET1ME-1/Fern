import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fern/l10n/locale_controller.dart';
import 'package:fern/main.dart';
import 'package:fern/services/deck_repository.dart';
import 'package:fern/theme/theme_controller.dart';

import 'test_helpers.dart';

void main() {
  testWidgets('Флоу: колода → Карточки → показать ответ → оценить',
      (WidgetTester tester) async {
    await resetStorage();
    await DeckRepository.instance.init();
    await ThemeController.instance.load();
    await LocaleController.instance.load();
    await LocaleController.instance.setCode('ru');
    // Сид грузит ассет колод (rootBundle) — только в реальном async.
    await tester.runAsync(() => DeckRepository.instance.seedDemoIfNeeded());

    // Высокий экран, чтобы дневная сводка + сетка колод помещались и элементы
    // были кликабельны в тесте.
    tester.view.physicalSize = const Size(1000, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const FernApp());
    await tester.pumpAndSettle();

    // Демо-колода на главном экране.
    expect(find.text('Первые слова'), findsOneWidget);
    await tester.tap(find.text('Первые слова'));
    await tester.pumpAndSettle();

    // Экран колоды: режим «Карточки».
    expect(find.text('Карточки'), findsWidgets);
    await tester.tap(find.text('Карточки').first);
    await tester.pumpAndSettle();

    // Сессия: показать ответ и оценить.
    expect(find.text('Показать ответ'), findsOneWidget);
    await tester.tap(find.text('Показать ответ'));
    await tester.pumpAndSettle();

    expect(find.text('Хорошо'), findsOneWidget);
    await tester.tap(find.text('Хорошо'));
    await tester.pumpAndSettle();
    // Дошли без исключений — вертикальный срез работает.
  });
}
