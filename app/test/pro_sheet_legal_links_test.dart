import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fern/l10n/strings.dart';
import 'package:fern/services/billing_service.dart';
import 'package:fern/widgets/pro_sheet.dart';

import 'test_helpers.dart';

/// Ссылки на условия и политику прямо на экране покупки.
///
/// Правило Apple 3.1.2(c): у приложения с автопродляемой подпиской экран
/// покупки обязан нести название тарифа, срок, цену и РАБОЧИЕ ссылки на
/// Terms of Use (EULA) и политику конфиденциальности. Отказ 09.09.2026
/// пришёл именно за отсутствие двух последних.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await resetStorage();
    BillingService.storeBilling = false;
  });

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
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

  testWidgets('в магазинной сборке обе ссылки на месте', (tester) async {
    BillingService.storeBilling = true;
    await open(tester);
    expect(find.text(tr('sub_terms')), findsOneWidget);
    expect(find.text(tr('sub_privacy')), findsOneWidget);
  });

  testWidgets('в сборке с сайта обе ссылки на месте', (tester) async {
    await open(tester);
    expect(find.text(tr('sub_terms')), findsOneWidget);
    expect(find.text(tr('sub_privacy')), findsOneWidget);
  });

  test('адреса рабочие и разведены по каналам', () {
    // В сборке для App Store условия — стандартный EULA Apple: свой текст
    // Apple требует класть отдельным полем в консоли, а ссылка на их
    // собственный документ принимается как есть.
    final apple = Uri.parse(ProSheet.termsUrlFor(appStore: true));
    expect(apple.scheme, 'https');
    expect(apple.host, 'www.apple.com');
    expect(apple.path, contains('stdeula'));

    final own = Uri.parse(ProSheet.termsUrlFor(appStore: false));
    expect(own.scheme, 'https');
    expect(own.host, 'thet1me-1.github.io');

    final privacy = Uri.parse(ProSheet.privacyUrl);
    expect(privacy.scheme, 'https');
    expect(privacy.host, 'thet1me-1.github.io');
  });

  test('срок подписки назван у обоих тарифов', () {
    // «Отменить можно в любой день» не говорит, на сколько берут деньги, а
    // длительность — обязательный пункт того же правила.
    for (final lang in ['ru', 'en']) {
      expect(kBaseStrings['sub_month_note']![lang], isNotNull);
      expect(kBaseStrings['sub_month_note']![lang]!.toLowerCase(),
          anyOf(contains('месяц'), contains('month')));
    }
  });
}
