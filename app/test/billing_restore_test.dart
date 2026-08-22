import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase_platform_interface/in_app_purchase_platform_interface.dart';

import 'package:fern/services/billing_service.dart';

import 'test_helpers.dart';

/// «Восстановить покупку» — единственный способ вернуть Pro на новом телефоне,
/// и у App Store он обязателен по правилам ревью. Кнопка молчаливая: магазин
/// отвечает не сразу, ошибки прежде глотались, и любой сбой выглядел одинаково
/// — «нажал, ничего не произошло».
///
/// Тесты держат три обещания: сбой при запуске не выключает кассу до
/// перезапуска, нажатие доводит покупку до флага, и каждый исход отличим от
/// остальных, чтобы интерфейсу было что сказать человеку.

/// Магазин, которым управляет тест: доступность, наличие товара, наличие
/// прошлой покупки и падение восстановления задаются по отдельности.
class _FakeStore extends InAppPurchasePlatform {
  /// Магазин отвечает вообще.
  bool storeUp = true;

  /// Товар `fern_pro` есть в ответе магазина.
  bool hasProduct = true;

  /// За аккаунтом числится прошлая покупка.
  bool hasPurchase = false;

  /// Запрос восстановления падает — так ведёт себя Play, когда отвечает не
  /// «ОК» хотя бы на один из двух своих запросов.
  bool restoreThrows = false;

  final _purchases = StreamController<List<PurchaseDetails>>.broadcast();

  @override
  Stream<List<PurchaseDetails>> get purchaseStream => _purchases.stream;

  @override
  Future<bool> isAvailable() async => storeUp;

  @override
  Future<ProductDetailsResponse> queryProductDetails(Set<String> ids) async {
    return ProductDetailsResponse(
      productDetails: hasProduct
          ? [
              ProductDetails(
                id: BillingService.productId,
                title: 'Fern Pro',
                description: '',
                price: r'$4.99',
                rawPrice: 4.99,
                currencyCode: 'USD',
              ),
            ]
          : [],
      notFoundIDs: hasProduct ? [] : ids.toList(),
    );
  }

  @override
  Future<void> restorePurchases({String? applicationUserName}) async {
    if (restoreThrows) {
      throw IAPError(
        source: 'test',
        code: 'restore_transactions_failed',
        message: 'Play ответил не OK',
      );
    }
    if (!hasPurchase) return;
    _purchases.add([
      PurchaseDetails(
        productID: BillingService.productId,
        purchaseID: 'p1',
        verificationData: PurchaseVerificationData(
          localVerificationData: '',
          serverVerificationData: '',
          source: 'test',
        ),
        transactionDate: null,
        status: PurchaseStatus.restored,
      ),
    ]);
  }

  @override
  Future<void> completePurchase(PurchaseDetails purchase) async {}

  void close() => _purchases.close();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeStore store;

  setUp(() async {
    await resetStorage();
    BillingService.debugStoreBilling = true;
    // Ждать магазин восемь секунд в тесте незачем: проверяем логику, а не
    // терпение.
    BillingService.restoreWindow = const Duration(milliseconds: 50);
    // `InAppPurchase.instance` при создании сам регистрирует платформу по
    // `defaultTargetPlatform` — на андроидной он затирает подмену и лезет в
    // канал плагина, которого в тесте нет. Платформа без своей кассы оставляет
    // подставленную на месте.
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    store = _FakeStore();
    InAppPurchasePlatform.instance = store;
    await BillingService.instance.debugSetOwned(false);
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    BillingService.debugStoreBilling = false;
    BillingService.restoreWindow = const Duration(seconds: 8);
    store.close();
  });

  /// Запуск приложения: `load()` поднимает кассу в фоне.
  Future<void> start() async {
    await BillingService.instance.load();
    await pumpEventQueue();
  }

  test('сбой тихого восстановления не выключает кассу', () async {
    store.restoreThrows = true;
    await start();
    // Магазин ответил и товар отдал — падение восстановления к этому
    // отношения не имеет. Раньше общий catch гасил `available`, и кнопка
    // после этого молчала до перезапуска приложения.
    expect(BillingService.instance.available, isTrue);
    expect(BillingService.instance.trouble, BillingTrouble.none);
  });

  test('нажатие возвращает покупку из магазина', () async {
    await start();
    store.hasPurchase = true;
    expect(await BillingService.instance.restore(), RestoreOutcome.restored);
    expect(BillingService.instance.owned, isTrue);
  });

  test('покупки в аккаунте нет — так и говорим', () async {
    await start();
    expect(await BillingService.instance.restore(), RestoreOutcome.nothing);
    expect(BillingService.instance.owned, isFalse);
  });

  test('сбой восстановления отличим от пустого ответа', () async {
    await start();
    store.restoreThrows = true;
    expect(await BillingService.instance.restore(), RestoreOutcome.failed);
  });

  test('магазина нет — восстановление не притворяется работающим', () async {
    store.storeUp = false;
    await start();
    expect(await BillingService.instance.restore(), RestoreOutcome.unavailable);
  });

  test('касса, отвалившаяся на старте, поднимается по нажатию', () async {
    store.storeUp = false;
    await start();
    // Телефон был без сети, человек включил её и нажал кнопку: второй попытки
    // подключения прежде не было вовсе.
    store.storeUp = true;
    store.hasPurchase = true;
    expect(await BillingService.instance.restore(), RestoreOutcome.restored);
  });
}
