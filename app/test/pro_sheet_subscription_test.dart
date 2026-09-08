import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fern/l10n/strings.dart';
import 'package:fern/services/billing_service.dart';
import 'package:fern/widgets/pro_sheet.dart';

import 'test_helpers.dart';

/// Лист Pro в сборке с сайта: два тарифа и подписка вместо ключа.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await resetStorage();
    // Канал сборки задан на компиляции; в тестах кассы магазина нет.
    BillingService.storeBilling = false;
  });

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Builder(builder: (context) {
        return TextButton(
          onPressed: () => ProSheet.show(context),
          child: const Text('открыть'),
        );
      })),
    ));
    await tester.tap(find.text('открыть'));
    await tester.pumpAndSettle();
  }

  testWidgets('оба тарифа на месте, годовой выбран заранее', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await open(tester);
    expect(find.text(tr('sub_plan_year')), findsOneWidget);
    expect(find.text(tr('sub_plan_month')), findsOneWidget);
    // Валюта зависит от языка интерфейса, поэтому проверяем сам факт цены:
    // тариф без числа — не тариф.
    expect(find.textContaining(RegExp(r'\d')), findsWidgets);
    expect(find.byIcon(Icons.radio_button_checked_rounded), findsOneWidget);
    expect(find.text(tr('sub_subscribe')), findsOneWidget);
  });

  testWidgets('тариф переключается тапом', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await open(tester);
    await tester.tap(find.text(tr('sub_plan_month')));
    await tester.pumpAndSettle();
    // Выбранный по-прежнему один: два одновременно означали бы, что человек не
    // понимает, за что платит.
    expect(find.byIcon(Icons.radio_button_checked_rounded), findsOneWidget);
  });

  testWidgets('купившим раньше оставлен ввод ключа', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await open(tester);
    expect(find.text(tr('sub_have_key')), findsOneWidget);
    // Лист прокручивается: кнопка живёт ниже сгиба.
    await tester.dragUntilVisible(
      find.text(tr('sub_have_key')),
      find.byType(SingleChildScrollView).first,
      const Offset(0, -80),
    );
    await tester.tap(find.text(tr('sub_have_key')));
    await tester.pumpAndSettle();
    await tester.dragUntilVisible(
      find.text(tr('pro_key_apply')),
      find.byType(SingleChildScrollView).first,
      const Offset(0, -80),
    );
    expect(find.text(tr('pro_key_apply')), findsOneWidget);
  });
}
