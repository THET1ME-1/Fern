import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fern/l10n/strings.dart';
import 'package:fern/services/license_service.dart';
import 'package:fern/utils/build_config.dart';
import 'package:fern/widgets/pro_sheet.dart';

import 'test_helpers.dart';

/// Ключ приходит из бота уже скопированным: в Telegram тап по моноширинному
/// тексту кладёт его в буфер. Лист Pro обязан это заметить и предложить одну
/// кнопку — набирать ключ руками человек не должен.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const testPublicKey = 'O6hgyWBgECdLZtmodoHQy0nXKG76CdzGo74d/OYTlGU=';

  // Та же лицензия №42 на vasya@mail.ru, что в license_named_test.
  const named = 'FERNAIAQAAAAFIAMSDLWMFZXSYKANVQWS3BOOJ234M4NUW2SDTA7KQSZELK2'
      'FJOJAP3NKNJ34XJKS6WO2MRPVUFFM52YTDGSU5VLFKPDH7XBKRSEJN5KJHNSYY3B7YX24UV'
      'HCWFER3FFBY';

  String? clipboard;

  setUp(() async {
    await resetStorage();
    // Служба живёт синглтоном: без сброса второй тест видит ключ первого.
    await LicenseService.instance.clear();
    LicenseService.debugPublicKeyBase64 = testPublicKey;
    LicenseService.revoked = <int>{};
    LicenseService.debugNow = DateTime.utc(2026, 7, 22);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.getData') {
        return clipboard == null ? null : <String, dynamic>{'text': clipboard};
      }
      return null;
    });
  });

  tearDown(() {
    LicenseService.debugPublicKeyBase64 = null;
    LicenseService.debugNow = null;
    LicenseService.revoked = <int>{};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Future<void> openSheet(WidgetTester tester) async {
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

  testWidgets('ключ из буфера предлагается одной кнопкой', (tester) async {
    clipboard = named;
    await openSheet(tester);
    expect(find.text(tr('pro_key_in_clipboard')), findsOneWidget);
    // Почта покупателя видна, но не целиком.
    expect(find.textContaining('@mail.ru'), findsOneWidget);

    await tester.tap(find.text(tr('pro_key_apply')));
    await tester.pumpAndSettle();
    expect(LicenseService.instance.info?.id, 42);
    // В магазинной сборке ключей нет вовсе: карточку буфера там не строят, и
    // проверять нечего (тот же приём, что у листа Pro в pro_gate_test).
  }, skip: kStoreBilling);

  testWidgets('чужой текст в буфере ничего не предлагает', (tester) async {
    clipboard = 'просто скопированное слово';
    await openSheet(tester);
    expect(find.text(tr('pro_key_in_clipboard')), findsNothing);
    expect(LicenseService.instance.info, isNull);
  });
}
