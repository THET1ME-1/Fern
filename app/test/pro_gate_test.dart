import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fern/l10n/locale_controller.dart';
import 'package:fern/l10n/strings.dart';
import 'package:fern/services/billing_service.dart';
import 'package:fern/services/license_service.dart';
import 'package:fern/services/pro.dart';
import 'package:fern/widgets/pro_sheet.dart';

import 'test_helpers.dart';

/// Гейт Fern Pro: что закрыто, что открыто и чем открывается.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const testPublicKey = 'A6EHv/POEL4dcN0Y50vAmWfk1jCbpQ1fHdyGZBJVMbg=';
  const key7 = 'FERNAEAQAAAAA4AMRXNNQ7364JRZZ2NHJ5YNX2YNZLQTZLUH6SMQZLQJJBMM'
      'WDOJZ7WY2NX4NNXSAADP5DZ54MR43APQHTCJEPA4RA2MI42GSN7Q6R374UBA';

  setUp(() async {
    await resetStorage();
    LicenseService.debugPublicKeyBase64 = testPublicKey;
    await LicenseService.instance.clear();
    await BillingService.instance.debugSetOwned(false);
    await LocaleController.instance.setCode('ru');
  });

  tearDown(() => LicenseService.debugPublicKeyBase64 = null);

  test('Без покупки первый источник библиотеки бесплатен', () async {
    expect(Pro.active, isFalse);
    // Свежая установка — источников нет, значит первую книгу пустят.
    expect(await Pro.allows(ProFeature.library), isTrue);
  });

  test('Перенос чужих колод закрыт без покупки', () async {
    expect(await Pro.allows(ProFeature.deckImport), isFalse);
  });

  test('Бесплатный источник расходуется разово, удаление его не возвращает',
      () async {
    // Прежде гейт считал длину списка источников, и удалив прочитанную книгу,
    // человек получал следующую даром — платить было незачем.
    expect(await Pro.allows(ProFeature.library), isTrue);
    await Pro.noteSourceUsed();
    expect(await Pro.allows(ProFeature.library), isFalse);
    expect(Pro.freeSourcesLeft, 0);
  });

  test('Покупка открывает библиотеку и после израсходованного слота', () async {
    await Pro.noteSourceUsed();
    await BillingService.instance.debugSetOwned(true);
    expect(await Pro.allows(ProFeature.library), isTrue);
  });

  test('Уже добавленные источники засчитываются как израсходованные', () async {
    // Обновление приложения не должно дарить лишнюю книгу тем, кто свою уже
    // разобрал: счётчика у них ещё нет, поэтому берём его из библиотеки.
    await Pro.migrateFromLibrary(2);
    expect(await Pro.allows(ProFeature.library), isFalse);
  });

  test('Перенос не затирает уже накопленный счёт', () async {
    await Pro.noteSourceUsed();
    // Библиотека пуста (книгу удалили), но слот израсходован — и остаётся им.
    await Pro.migrateFromLibrary(0);
    expect(await Pro.allows(ProFeature.library), isFalse);
  });

  test('Покупка в магазине открывает всё', () async {
    await BillingService.instance.debugSetOwned(true);
    expect(Pro.active, isTrue);
    expect(await Pro.allows(ProFeature.deckImport), isTrue);
    expect(await Pro.allows(ProFeature.library), isTrue);
  });

  test('Ключ открывает то же, что покупка', () async {
    await LicenseService.instance.apply(key7);
    expect(Pro.active, isTrue);
    expect(await Pro.allows(ProFeature.deckImport), isTrue);
  });

  test('Снятый ключ закрывает обратно', () async {
    await LicenseService.instance.apply(key7);
    await LicenseService.instance.clear();
    expect(Pro.active, isFalse);
    expect(await Pro.allows(ProFeature.deckImport), isFalse);
  });

  testWidgets('Лист покупки вне магазина ведёт в бот и принимает ключ',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: ElevatedButton(
            onPressed: () => ProSheet.show(context),
            child: const Text('открыть'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('открыть'));
    await tester.pumpAndSettle();

    // Сборка не магазинная: платят на стороне, ключ выдаёт бот. Кнопка
    // «Купить» есть в обеих ветках, поэтому Play узнаётся по восстановлению
    // покупки — его умеет только магазин.
    expect(find.text(tr('pro_open_bot')), findsOneWidget);
    expect(find.text(tr('pro_buy')), findsOneWidget);
    expect(find.text(tr('pro_restore')), findsNothing);

    await tester.tap(find.text(tr('pro_have_key')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), key7);
    await tester.tap(find.text(tr('pro_key_apply')));
    await tester.pumpAndSettle();

    expect(Pro.active, isTrue);
    expect(find.byType(ProSheet), findsNothing); // лист закрылся сам
  });

  testWidgets('Закрытый лист покупки объясняет, что осталось закрытым',
      (tester) async {
    // Прежде отказ был немым: лист закрывался, действие не выполнялось, и
    // человек оставался гадать, сломалось приложение или так задумано.
    await Pro.noteSourceUsed();
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: ElevatedButton(
            onPressed: () => requirePro(context, ProFeature.library),
            child: const Text('добавить книгу'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('добавить книгу'));
    await tester.pumpAndSettle();

    // Лист показан; человек его закрывает, ничего не купив.
    expect(find.byType(ProSheet), findsOneWidget);
    Navigator.of(tester.element(find.byType(ProSheet))).pop();
    await tester.pumpAndSettle();

    expect(find.text(tr('pro_denied')), findsOneWidget);
  });

  testWidgets('Негодный ключ говорит об этом и не закрывает лист',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: ElevatedButton(
            onPressed: () => ProSheet.show(context),
            child: const Text('открыть'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('открыть'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(tr('pro_have_key')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'FERNZZZZZZZZ');
    await tester.tap(find.text(tr('pro_key_apply')));
    await tester.pumpAndSettle();

    expect(find.text(tr('pro_key_bad')), findsOneWidget);
    expect(Pro.active, isFalse);
  });
}
