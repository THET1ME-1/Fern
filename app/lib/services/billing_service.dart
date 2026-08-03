import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'signed_store.dart';

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
/// Что именно мешает покупке.
enum BillingTrouble {
  /// Всё в порядке (или магазин в этой сборке не предусмотрен).
  none,

  /// Биллинг не поднялся: приложение поставлено мимо Play, устройство без
  /// сервисов Google или аккаунт не тот.
  noStore,

  /// Магазин отвечает, но товара в ответе нет: предложение в консоли не
  /// активно, цена не задана для страны, либо товар ещё не разошёлся по Play.
  noProduct,
}

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
  BillingTrouble _trouble = BillingTrouble.none;

  /// Куплено ли Pro через магазин. Флаг живёт на устройстве, поэтому Pro
  /// остаётся при выключенном интернете.
  bool get owned => _owned;

  /// Доступен ли магазин: в GitHub-сборке и на десктопе — нет.
  bool get available => _available;

  /// Почему покупка не идёт. Раньше оба случая — «магазин не поднялся» и
  /// «товара нет в ответе Play» — давали одну надпись, и отличить установку
  /// мимо магазина от неактивного предложения в консоли было нечем.
  BillingTrouble get trouble => _trouble;

  /// Цена строкой из магазина («$4.99», «399,00 ₽») — Play сам считает валюту
  /// и налоги страны, поэтому своей таблицы цен в приложении нет.
  String? get price => _product?.price;

  Future<void> load() async {
    // Флаг подписан: правка настроек снаружи — самый лёгкий путь к даровому
    // Pro, и подделанное значение читается как «не куплено». Настоящая
    // покупка вернётся сама при восстановлении из магазина.
    _owned = await SignedStore.getBool(_kOwned);
    notifyListeners();
    if (!kPlayBuild) return;
    // Магазин отвечает по сети — дальше идём молча, интерфейс уже поднят.
    unawaited(_connect());
  }

  Future<void> _connect() async {
    try {
      _available = await InAppPurchase.instance.isAvailable();
      if (!_available) {
        _trouble = BillingTrouble.noStore;
        debugPrint('[billing] магазин недоступен: isAvailable() = false');
        notifyListeners();
        return;
      }
      _sub = InAppPurchase.instance.purchaseStream.listen(
        _onPurchases,
        onError: (e) => debugPrint('[billing] поток покупок: $e'),
      );
      final response = await InAppPurchase.instance
          .queryProductDetails({productId});
      _product = response.productDetails
          .where((p) => p.id == productId)
          .firstOrNull;
      // Ответ Play пишем в лог целиком: `notFoundIDs` — единственное, что
      // отличает «приложение поставлено мимо магазина» от «предложение в
      // консоли не активно», а искать это вслепую по консоли можно днями.
      debugPrint('[billing] товаров: ${response.productDetails.length}, '
          'не найдено: ${response.notFoundIDs}, '
          'ошибка: ${response.error?.code} ${response.error?.message}');
      if (_product == null) {
        _trouble = BillingTrouble.noProduct;
      } else {
        _trouble = BillingTrouble.none;
      }
      notifyListeners();
      // Тихое восстановление: человек, переставивший приложение, не должен
      // искать кнопку «я уже покупал».
      await InAppPurchase.instance.restorePurchases();
    } catch (e) {
      debugPrint('[billing] подключение не удалось: $e');
      _available = false;
      _trouble = BillingTrouble.noStore;
      notifyListeners();
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
    final known = _owned;
    _owned = true;
    // Записываем даже когда флаг уже поднят в памяти: диск мог разойтись с
    // памятью (например, после «удалить все данные»), и ранний возврат
    // оставлял покупку незаписанной — «Восстановить покупку» не помогало.
    await SignedStore.setBool(_kOwned, true);
    if (!known) notifyListeners();
  }

  /// Заново кладёт флаг покупки на диск, если он есть в памяти. Нужно после
  /// операций, которые чистят prefs целиком.
  Future<void> persistOwned() async {
    if (_owned) await SignedStore.setBool(_kOwned, true);
  }

  @visibleForTesting
  Future<void> debugSetOwned(bool value) async {
    _owned = value;
    await SignedStore.setBool(_kOwned, value);
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
