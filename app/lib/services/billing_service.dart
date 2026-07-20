import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/build_config.dart';

/// Покупка Fern Pro в Google Play.
///
/// Работает только в play-сборке: сборка с GitHub магазина не видит, там Pro
/// открывается ключом (см. [LicenseService]). Развилка по [kPlayBuild] — та же,
/// по которой в проекте уже разведены самообновление и Play In-App Update.
///
/// Покупка разовая и не расходуемая: заплатил один раз, дальше приложение
/// восстанавливает её на любом устройстве с тем же аккаунтом Google.
///
/// Чек не проверяется на сервере, потому что сервера нет. Для приложения за
/// пять долларов серверная проверка стоит дороже потерь от тех, кто умеет
/// подделывать ответы биллинга.
class BillingService extends ChangeNotifier {
  BillingService._();

  static final BillingService instance = BillingService._();

  /// Идентификатор товара в Play Console. Меняется только вместе с консолью.
  static const String productId = 'fern_pro';

  static const String _kOwned = 'proPurchased';

  bool _owned = false;
  bool _available = false;
  ProductDetails? _product;
  StreamSubscription<List<PurchaseDetails>>? _sub;

  /// Куплено ли Pro через магазин. Флаг живёт на устройстве, поэтому Pro
  /// остаётся при выключенном интернете.
  bool get owned => _owned;

  /// Доступен ли магазин: в GitHub-сборке и на десктопе — нет.
  bool get available => _available;

  /// Цена строкой из магазина («$4.99», «399,00 ₽») — Play сам считает валюту
  /// и налоги страны, поэтому своей таблицы цен в приложении нет.
  String? get price => _product?.price;

  Future<void> load() async {
    _owned = await SharedPreferencesAsync().getBool(_kOwned) ?? false;
    notifyListeners();
    if (!kPlayBuild) return;
    // Магазин отвечает по сети — дальше идём молча, интерфейс уже поднят.
    unawaited(_connect());
  }

  Future<void> _connect() async {
    try {
      _available = await InAppPurchase.instance.isAvailable();
      if (!_available) return;
      _sub = InAppPurchase.instance.purchaseStream.listen(
        _onPurchases,
        onError: (_) {},
      );
      final response = await InAppPurchase.instance
          .queryProductDetails({productId});
      _product = response.productDetails
          .where((p) => p.id == productId)
          .firstOrNull;
      notifyListeners();
      // Тихое восстановление: человек, переставивший приложение, не должен
      // искать кнопку «я уже покупал».
      await InAppPurchase.instance.restorePurchases();
    } catch (_) {
      _available = false;
    }
  }

  /// Запускает покупку. `false` — магазин не готов, товар не подъехал.
  Future<bool> buy() async {
    final product = _product;
    if (!kPlayBuild || !_available || product == null) return false;
    try {
      return await InAppPurchase.instance
          .buyNonConsumable(purchaseParam: PurchaseParam(productDetails: product));
    } catch (_) {
      return false;
    }
  }

  /// Явное восстановление — кнопкой в настройках, когда тихое не сработало.
  Future<void> restore() async {
    if (!kPlayBuild || !_available) return;
    try {
      await InAppPurchase.instance.restorePurchases();
    } catch (_) {}
  }

  Future<void> _onPurchases(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      if (purchase.productID != productId) continue;
      final bought = purchase.status == PurchaseStatus.purchased ||
          purchase.status == PurchaseStatus.restored;
      if (bought) await _grant();
      // Магазин ждёт подтверждения; без него Play вернёт деньги через три дня.
      if (purchase.pendingCompletePurchase) {
        await InAppPurchase.instance.completePurchase(purchase);
      }
    }
  }

  Future<void> _grant() async {
    if (_owned) return;
    _owned = true;
    await SharedPreferencesAsync().setBool(_kOwned, true);
    notifyListeners();
  }

  @visibleForTesting
  Future<void> debugSetOwned(bool value) async {
    _owned = value;
    await SharedPreferencesAsync().setBool(_kOwned, value);
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
