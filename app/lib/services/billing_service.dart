import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'signed_store.dart';

import '../utils/build_config.dart';

/// Покупка Fern Pro в магазине: Google Play или App Store.
///
/// Работает в магазинных сборках: сборка с GitHub магазина не видит, там Pro
/// открывается ключом (см. [LicenseService]). Развилка по [kStoreBilling] —
/// родня той, по которой в проекте разведены самообновление и In-App Update.
///
/// Товар в обеих консолях называется одинаково — `fern_pro`. У Apple это
/// non-consumable, у Google — разовая покупка; `in_app_purchase` работает с
/// ними одним и тем же `buyNonConsumable`.
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

/// Чем кончилось нажатие «Восстановить покупку».
///
/// Четыре исхода вместо прежнего молчания: кнопка обязана сказать, вернула
/// она Pro, не нашла покупки, не достучалась до магазина или получила от него
/// ошибку. Снаружи все четыре случая выглядели одинаково — «нажал, ничего не
/// произошло», — и починить по такому описанию было нечего.
enum RestoreOutcome {
  /// Покупка нашлась, Pro открыт.
  restored,

  /// Магазин ответил, но покупки за этим аккаунтом нет.
  nothing,

  /// До кассы не дошли: сборка мимо магазина, устройство без сервисов Google,
  /// нет сети.
  unavailable,

  /// Магазин ответил ошибкой.
  failed,
}

class BillingService extends ChangeNotifier {
  BillingService._();

  static final BillingService instance = BillingService._();

  /// Идентификатор товара в Play Console. Меняется только вместе с консолью.
  static const String productId = 'fern_pro';

  static const String _kOwned = 'proPurchased';

  /// Сколько ждать ответ магазина после запроса на восстановление. Покупка
  /// приходит отдельным событием в поток, а сам запрос возвращается раньше:
  /// без ожидания кнопка отвечала бы до того, как что-то случилось.
  static Duration restoreWindow = const Duration(seconds: 8);

  /// Работает ли в этой сборке магазинная касса. Обычно равно [kStoreBilling];
  /// поле, а не константа, потому что канал сборки задан на компиляции, и
  /// тестовая сборка магазина не знает — проверить логику восстановления было
  /// бы нечем.
  @visibleForTesting
  static bool debugStoreBilling = kStoreBilling;

  bool _owned = false;
  bool _available = false;
  ProductDetails? _product;
  StreamSubscription<List<PurchaseDetails>>? _sub;
  BillingTrouble _trouble = BillingTrouble.none;
  Completer<void>? _restoreWaiter;

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
    if (!debugStoreBilling) return;
    // Магазин отвечает по сети — дальше идём молча, интерфейс уже поднят.
    unawaited(_connect());
  }

  /// Поднимает кассу. [silentRestore] — то самое тихое восстановление при
  /// запуске; по кнопке оно лишнее, там восстановление своё и с ответом.
  Future<void> _connect({bool silentRestore = true}) async {
    try {
      _available = await InAppPurchase.instance.isAvailable();
      if (!_available) {
        _trouble = BillingTrouble.noStore;
        debugPrint('[billing] магазин недоступен: isAvailable() = false');
        notifyListeners();
        return;
      }
      // Подключаться можно не один раз: кнопка восстановления зовёт это же
      // место, когда касса не поднялась на старте. Без отмены прежней подписки
      // одна покупка приходила бы дважды.
      await _sub?.cancel();
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
    } catch (e) {
      debugPrint('[billing] подключение не удалось: $e');
      _available = false;
      _trouble = BillingTrouble.noStore;
      notifyListeners();
      return;
    }
    if (!silentRestore) return;
    // Тихое восстановление: человек, переставивший приложение, не должен
    // искать кнопку «я уже покупал».
    //
    // Своя ловушка, и это важно: запрос восстановления падает, когда Play
    // отвечает не «ОК» хотя бы на один из двух своих запросов (разовые
    // покупки и подписки). Раньше это падение ловил общий catch подключения,
    // и `available` уходил в false при живом магазине с загруженным товаром —
    // кнопка «Восстановить покупку» после этого молчала до перезапуска
    // приложения. Сбой восстановления не говорит о кассе ничего.
    try {
      await InAppPurchase.instance.restorePurchases();
    } catch (e) {
      debugPrint('[billing] тихое восстановление не удалось: $e');
    }
  }

  /// Запускает покупку. `false` — магазин не готов, товар не подъехал.
  Future<bool> buy() async {
    final product = _product;
    if (!debugStoreBilling || !_available || product == null) return false;
    try {
      return await InAppPurchase.instance
          .buyNonConsumable(purchaseParam: PurchaseParam(productDetails: product));
    } catch (_) {
      return false;
    }
  }

  /// Явное восстановление — кнопкой в настройках, когда тихое не сработало.
  ///
  /// В App Store кнопка обязательна: без неё ревью отклоняет приложение с
  /// разовой покупкой (человек должен вернуть Pro на новом устройстве сам).
  ///
  /// Отвечает исходом, а не тишиной: интерфейсу нужно что-то показать, и
  /// «покупки за этим аккаунтом нет» — не то же самое, что «магазин не
  /// ответил».
  Future<RestoreOutcome> restore() async {
    if (!debugStoreBilling) return RestoreOutcome.unavailable;
    // Касса могла не успеть подняться к нажатию (магазин отвечает по сети, а
    // настройки открываются раньше) или отвалиться на старте из-за сбоя.
    // Прежде кнопка в обоих случаях молча выходила.
    if (!_available) await _connect(silentRestore: false);
    if (!_available) return RestoreOutcome.unavailable;
    final waiter = _restoreWaiter = Completer<void>();
    try {
      await InAppPurchase.instance.restorePurchases();
    } catch (e) {
      _restoreWaiter = null;
      debugPrint('[billing] восстановление не удалось: $e');
      return RestoreOutcome.failed;
    }
    try {
      // Ответ придёт в поток покупок, поэтому ждём событие, а не возврата
      // запроса. Ждём не вечно: когда покупки нет, события не будет вовсе.
      await waiter.future.timeout(restoreWindow);
      return RestoreOutcome.restored;
    } on TimeoutException {
      return _owned ? RestoreOutcome.restored : RestoreOutcome.nothing;
    } finally {
      _restoreWaiter = null;
    }
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
    final waiter = _restoreWaiter;
    if (waiter != null && !waiter.isCompleted) waiter.complete();
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
