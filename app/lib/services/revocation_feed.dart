import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'license_service.dart';

/// Отозванные лицензии, лежащие файлом в репозитории.
///
/// Вшитый в код список приезжает только с обновлением приложения: утёкший ключ
/// работал бы у тех, кто не обновляется, месяцами. Файл `docs/revoked.json`
/// живёт по тому же адресу, откуда качается сборка, и обновляется коммитом —
/// серверной части ни на той, ни на этой стороне нет.
///
/// Ходим редко и только заодно: раз в трое суток, когда приложение и так
/// открыто. Не дозвонились — работает то, что уже лежит на устройстве, а
/// офлайн-обещание не страдает.
class RevocationFeed {
  RevocationFeed._();

  static const String url =
      'https://raw.githubusercontent.com/THET1ME-1/Fern/main/docs/revoked.json';

  /// Как часто заглядывать за списком.
  static const Duration period = Duration(days: 3);

  static const String _kIds = 'revokedIds';
  static const String _kAt = 'revokedCheckedAt';

  @visibleForTesting
  static DateTime? debugNow;

  static DateTime get _now => debugNow ?? DateTime.now().toUtc();

  /// Разбирает ответ. `null` — ответ негодный, и трогать текущий список нельзя.
  ///
  /// Разбор строгий намеренно: пропущенный по дороге номер означает работающий
  /// утёкший ключ, поэтому один чужой элемент отменяет весь список.
  static Set<int>? parse(String body) {
    try {
      final json = jsonDecode(body);
      if (json is! Map) return null;
      final list = json['revoked'];
      if (list is! List) return null;
      final out = <int>{};
      for (final item in list) {
        if (item is! int) return null;
        out.add(item);
      }
      return out;
    } catch (_) {
      return null;
    }
  }

  /// Пора ли идти за списком.
  static Future<bool> isDue() async {
    final raw = await SharedPreferencesAsync().getString(_kAt);
    final last = raw == null ? null : DateTime.tryParse(raw);
    if (last == null) return true;
    return _now.difference(last) >= period;
  }

  /// Сохраняет список и отметку времени.
  static Future<void> remember(Set<int> ids) async {
    final prefs = SharedPreferencesAsync();
    await prefs.setStringList(_kIds, [for (final id in ids) '$id']);
    await prefs.setString(_kAt, _now.toIso8601String());
  }

  /// Что лежит на устройстве с прошлого раза.
  static Future<Set<int>> stored() async {
    final list = await SharedPreferencesAsync().getStringList(_kIds) ?? const [];
    return {
      for (final s in list)
        if (int.tryParse(s) != null) int.parse(s),
    };
  }

  /// Применяет сохранённый список к проверке лицензий. Дёшево и без сети —
  /// зовётся до загрузки лицензии, иначе отозванный ключ прожил бы ещё один
  /// запуск.
  static Future<void> applyStored() async {
    _builtIn ??= LicenseService.revoked;
    LicenseService.revoked = {..._builtIn!, ...await stored()};
  }

  /// Обновляет список по сети, если пора. Зовётся фоном после запуска: старт
  /// приложения ждать ответа GitHub не должен.
  static Future<void> refresh() async {
    if (!await isDue()) return;
    try {
      final response =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return;
      final ids = parse(response.body);
      if (ids == null) return;
      await remember(ids);
      _builtIn ??= LicenseService.revoked;
      LicenseService.revoked = {..._builtIn!, ...ids};
      // Ключ мог быть отозван только что — перечитываем, чтобы Pro закрылся
      // сразу, а не со следующего запуска.
      await LicenseService.instance.load();
    } catch (_) {
      /* нет сети или GitHub недоступен — остаёмся на сохранённом списке */
    }
  }

  /// Список, вшитый в сборку: к нему приклеивается загруженный, а не наоборот —
  /// иначе повторный вызов размножал бы уже применённые номера.
  static Set<int>? _builtIn;
}
