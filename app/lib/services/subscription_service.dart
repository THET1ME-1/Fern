import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fern_account.dart';
import 'license_service.dart';

/// В каком состоянии подписка.
enum SubStatus {
  /// Подписки не было.
  none,

  /// Оплачено и продлевается.
  active,

  /// Отменена, но оплаченный срок ещё идёт.
  cancelled,

  /// Срок вышел.
  expired,

  /// Деньги вернули.
  refunded,

  /// Куплено навсегда, до перехода на подписку.
  lifetime,
}

/// Подписка Fern Pro.
///
/// Сервер держит один срок на все три кассы (счёт lava, Google Play, App
/// Store) и отдаёт вместе с ним ТАЛОН — подписанную строку со сроком внутри.
/// Талон проверяется на устройстве, поэтому Pro не гаснет без сети: приложение
/// офлайн-first, и подписка не повод менять это.
class SubscriptionService extends ChangeNotifier {
  SubscriptionService._();

  static final SubscriptionService instance = SubscriptionService._();

  static const String _kUntil = 'fernProUntil';
  static const String _kStatus = 'fernProStatus';
  static const String _kPlan = 'fernProPlan';
  static const String _kCheckedAt = 'fernProCheckedAt';

  /// Как часто ходить за свежим талоном при обычном запуске.
  static const Duration refreshEvery = Duration(hours: 20);

  @visibleForTesting
  static DateTime? debugNow;

  static DateTime get _now => debugNow ?? DateTime.now().toUtc();

  DateTime? _until;
  List<String> _plans = const ['month', 'year'];
  SubStatus _status = SubStatus.none;
  String? _plan;
  DateTime? _checkedAt;

  /// До какого дня оплачено. `null` — подписки не было.
  DateTime? get until => _until;

  SubStatus get status => _status;

  /// Тариф: `month` или `year`.
  String? get plan => _plan;

  /// Тарифы, которые сервер готов продать. Пока годовой не заведён в кабинете
  /// lava, его тут нет — и приложение не рисует кнопку, которая ответит
  /// ошибкой.
  List<String> get plans => _plans;

  /// Когда последний раз говорили с сервером.
  DateTime? get checkedAt => _checkedAt;

  /// Работает ли Pro прямо сейчас. Решает талон, а не эти поля: они лишь для
  /// показа. Так подписка переживает и отсутствие сети, и молчание сервера.
  bool get active => LicenseService.instance.ticketValid;

  /// Поднимает последнее известное состояние с диска.
  Future<void> load() async {
    final prefs = SharedPreferencesAsync();
    final until = await prefs.getString(_kUntil);
    _until = until == null ? null : _parseDay(until);
    _status = _statusFrom(await prefs.getString(_kStatus));
    _plan = await prefs.getString(_kPlan);
    final checked = await prefs.getString(_kCheckedAt);
    _checkedAt = checked == null ? null : DateTime.tryParse(checked);
    notifyListeners();
  }

  /// Спрашивает сервер: срок, состояние и свежий талон.
  ///
  /// Возвращает `false`, когда до сервера не достучались. Прежнее состояние
  /// при этом не трогаем — иначе поездка в метро выглядела бы как отмена
  /// подписки.
  Future<bool> refresh() async {
    if (!FernAccount.instance.signedIn) return false;
    final Object? answer;
    try {
      answer = await FernAccount.instance.pb
          .send('/api/fern/me', method: 'GET')
          .timeout(FernAccount.netTimeout);
    } catch (e) {
      debugPrint('SubscriptionService.refresh: $e');
      return false;
    }
    if (answer is! Map) return false;

    final until = answer['until'];
    _until = until is String ? _parseDay(until) : null;
    _status = _statusFrom(answer['status']?.toString());
    _plan = answer['plan']?.toString();
    final plans = answer['plans'];
    if (plans is List && plans.isNotEmpty) {
      _plans = [for (final p in plans) p.toString()];
    }
    _checkedAt = _now;

    final ticket = answer['ticket'];
    if (ticket is String && ticket.isNotEmpty) {
      await LicenseService.instance.apply(ticket);
    } else {
      // Сервер сказал, что оплаченного срока нет. Талон убираем сразу: держать
      // его до истечения значило бы отдавать Pro тому, кому вернули деньги.
      await LicenseService.instance.clearTicket();
    }

    final prefs = SharedPreferencesAsync();
    if (_until != null) {
      await prefs.setString(_kUntil, _until!.toIso8601String());
    } else {
      await prefs.remove(_kUntil);
    }
    await prefs.setString(_kStatus, _status.name);
    if (_plan != null) await prefs.setString(_kPlan, _plan!);
    await prefs.setString(_kCheckedAt, _checkedAt!.toIso8601String());
    notifyListeners();
    return true;
  }

  /// Ходит на сервер, если давно не ходили. Зовётся при запуске и возвращении
  /// в приложение: талон живёт дольше суток, дёргать сервер чаще незачем.
  Future<void> refreshIfStale() async {
    final last = _checkedAt;
    if (last != null && _now.difference(last) < refreshEvery) return;
    await refresh();
  }

  /// Адрес страницы оплаты. `null` — сервер не смог создать счёт.
  Future<String?> checkoutUrl({
    required String plan,
    String currency = 'RUB',
    String lang = 'RU',
  }) async {
    if (!FernAccount.instance.signedIn) return null;
    try {
      final answer = await FernAccount.instance.pb.send(
        '/api/fern/checkout',
        method: 'POST',
        body: {'plan': plan, 'currency': currency, 'lang': lang},
      ).timeout(const Duration(seconds: 30));
      if (answer is Map && answer['url'] is String) {
        final url = answer['url'] as String;
        if (url.isNotEmpty) return url;
      }
    } catch (e) {
      debugPrint('SubscriptionService.checkoutUrl: $e');
    }
    return null;
  }

  /// Ждёт, пока оплата дойдёт до сервера.
  ///
  /// Человек возвращается из браузера раньше, чем lava успевает прислать
  /// уведомление, поэтому спрашиваем по кругу — но недолго и редко, чтобы не
  /// выглядеть опросом каждую секунду.
  Future<bool> waitForPayment({
    Duration every = const Duration(seconds: 3),
    Duration limit = const Duration(minutes: 3),
  }) async {
    final deadline = _now.add(limit);
    while (_now.isBefore(deadline)) {
      if (await refresh() && active) return true;
      await Future<void>.delayed(every);
    }
    return active;
  }

  /// Отменяет подписку. Доступ остаётся до конца оплаченного периода.
  Future<bool> cancel() async {
    if (!FernAccount.instance.signedIn) return false;
    try {
      final answer = await FernAccount.instance.pb
          .send('/api/fern/cancel', method: 'POST')
          .timeout(FernAccount.netTimeout);
      if (answer is Map && answer['ok'] == true) {
        await refresh();
        return true;
      }
    } catch (e) {
      debugPrint('SubscriptionService.cancel: $e');
    }
    return false;
  }

  /// Забывает всё, что знает о подписке. Зовётся при выходе из аккаунта.
  Future<void> forget() async {
    _until = null;
    _status = SubStatus.none;
    _plan = null;
    _checkedAt = null;
    final prefs = SharedPreferencesAsync();
    await prefs.remove(_kUntil);
    await prefs.remove(_kStatus);
    await prefs.remove(_kPlan);
    await prefs.remove(_kCheckedAt);
    notifyListeners();
  }

  /// Дата с сервера. День без зоны разбираем как UTC: `DateTime.tryParse`
  /// на строке «2026-10-08» отдаёт ЛОКАЛЬНУЮ полночь, и в часовом поясе с
  /// плюсом «оплачено до» съезжало на сутки назад.
  static DateTime? _parseDay(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;
    if (text.length == 10) {
      final parsed = DateTime.tryParse('${text}T00:00:00Z');
      if (parsed != null) return parsed;
    }
    return DateTime.tryParse(text)?.toUtc();
  }

  static SubStatus _statusFrom(String? raw) => switch (raw) {
        'active' => SubStatus.active,
        'cancelled' => SubStatus.cancelled,
        'expired' => SubStatus.expired,
        'refunded' => SubStatus.refunded,
        'lifetime' => SubStatus.lifetime,
        _ => SubStatus.none,
      };
}
