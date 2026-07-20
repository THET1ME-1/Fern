import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fern/l10n/locale_controller.dart';
import 'package:fern/services/deck_repository.dart';
import 'package:fern/settings_screen.dart';

import 'test_helpers.dart';

/// Настройки собраны в секции: заголовок над общим блоком пунктов.
void main() {
  setUp(() async {
    await resetStorage();
    await DeckRepository.instance.init();
    await LocaleController.instance.setCode('ru');
  });

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 3600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
    await tester.pumpAndSettle();
  }

  testWidgets('пункты секции лежат в одном блоке, а не в карточке каждый',
      (WidgetTester tester) async {
    await open(tester);

    expect(find.text('Внешний вид'), findsOneWidget);
    expect(find.text('Тема'), findsOneWidget);
    // Разделители появляются только внутри блоков — по одному между пунктами.
    expect(find.byType(Divider), findsWidgets);
  });

  testWidgets('тап по заголовку сворачивает секцию',
      (WidgetTester tester) async {
    await open(tester);
    expect(find.text('Цвет оформления'), findsOneWidget);

    await tester.tap(find.text('Внешний вид'));
    await tester.pumpAndSettle();
    expect(find.text('Цвет оформления'), findsNothing,
        reason: 'секций восемь, и до «О приложении» иначе долго листать');

    await tester.tap(find.text('Внешний вид'));
    await tester.pumpAndSettle();
    expect(find.text('Цвет оформления'), findsOneWidget);
  });

  testWidgets('свёрнутое не запоминается между заходами',
      (WidgetTester tester) async {
    await open(tester);
    await tester.tap(find.text('Данные'));
    await tester.pumpAndSettle();
    expect(find.text('Создать резервную копию'), findsNothing);

    // Экран открыт заново — всё снова видно. Свернул однажды не значит спрятал
    // навсегда: искать пропавшую настройку человек будет глазами, а не памятью.
    await tester.pumpWidget(const MaterialApp(
      key: ValueKey('again'),
      home: SettingsScreen(),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Создать резервную копию'), findsOneWidget);
  });
}
