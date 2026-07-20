import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Настройки, которые нельзя поправить снаружи: состояние покупки и счётчик
/// бесплатных разборов.
///
/// Файл настроек Android читаем и записываем с root-правами, через adb и через
/// редакторы бэкапов — это самый лёгкий путь получить Pro даром, и приложение
/// пересобирать для него не нужно. Каждое значение хранится с подписью
/// HMAC-SHA256; значение без подписи или с чужой подписью считается
/// подделанным, и вызывающий получает свой запасной вариант.
///
/// **Чего это НЕ даёт.** Исходники Fern открыты: и сборка с вечным Pro, и соль
/// подписи доступны любому желающему. Настоящий порог здесь — доступ к файлу
/// настроек, то есть root или эмулятор; кто до файла дошёл, тот подпишет и
/// значение. Защиты от этого не существует без сервера, а гнаться за ней
/// значило бы портить жизнь честным покупателям ради тех, кто платить не
/// собирался.
class SignedStore {
  const SignedStore._();

  /// Соль подписи. В открытом коде она секретна ровно до первого желающего её
  /// прочитать: смысл не в тайне, а в том, что случайная правка значения в
  /// файле настроек перестаёт работать сама по себе.
  static const String _salt = 'fern.pro.v1.5f3a9c';

  static final _hmac = Hmac.sha256();
  static SharedPreferencesAsync get _prefs => SharedPreferencesAsync();

  static Future<String> _sign(String key, String value) async {
    final mac = await _hmac.calculateMac(
      utf8.encode('$key=$value'),
      secretKey: SecretKey(utf8.encode(_salt)),
    );
    return base64Encode(mac.bytes);
  }

  static Future<void> setBool(String key, bool value) =>
      _write(key, value ? '1' : '0', () => _prefs.setBool(key, value));

  static Future<void> setInt(String key, int value) =>
      _write(key, '$value', () => _prefs.setInt(key, value));

  static Future<void> _write(
      String key, String signed, Future<void> Function() store) async {
    await store();
    await _prefs.setString('$key.sig', await _sign(key, signed));
  }

  /// Значение или `false`, если его нет либо подпись не сошлась.
  static Future<bool> getBool(String key) async {
    final value = await _prefs.getBool(key);
    if (value == null) return false;
    return await _valid(key, value ? '1' : '0') && value;
  }

  /// Значение, `null` — если его никогда не писали, [onTampered] — если писали
  /// не мы. Отсутствие и подделка отвечают по-разному намеренно: у чистой
  /// установки нет счётчика вовсе, и путать её с попыткой обхода нельзя.
  static Future<int?> getInt(String key, {required int onTampered}) async {
    final value = await _prefs.getInt(key);
    if (value == null) return null;
    return await _valid(key, '$value') ? value : onTampered;
  }

  /// Есть ли под значением своя подпись. Ключ входит в подписываемый текст,
  /// поэтому подпись от одного значения не годится другому — иначе их можно
  /// было бы переставить местами.
  static Future<bool> _valid(String key, String value) async {
    final stored = await _prefs.getString('$key.sig');
    if (stored == null) return false;
    return stored == await _sign(key, value);
  }

  /// Забыть значение вместе с подписью.
  static Future<void> remove(String key) async {
    await _prefs.remove(key);
    await _prefs.remove('$key.sig');
  }
}
