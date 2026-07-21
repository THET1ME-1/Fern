import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Офлайн-лицензия Fern Pro.
///
/// Ключ выдаёт бот после оплаты и подписывает приватным ключом Ed25519,
/// приложение носит только публичный и проверяет подпись на устройстве.
/// Сервера нет намеренно: дневник со словарём работает в самолёте, и покупка
/// не должна быть единственным, ради чего приложению понадобился бы интернет.
///
/// Ключ не привязан к устройству. Человек, купивший Pro, ставит его на все свои
/// телефоны — привязка защитила бы от копирования ключа в чужие руки, но ценой
/// того, что честный покупатель теряет Pro при смене телефона. Обмен ключами
/// на форуме лечится отзывом конкретного номера, а не подозрением ко всем.
///
/// Формат: `FERN` + base32(payload‖подпись), payload 8 байт, подпись 64.
class LicenseService extends ChangeNotifier {
  LicenseService._();

  static final LicenseService instance = LicenseService._();

  /// Публичный ключ выдающей стороны (base64, 32 байта).
  /// Приватная половина живёт только у владельца бота — в репозитории её нет.
  static const String publicKeyBase64 =
      'tx0Z6LnOxFk1HQt8kdeSr+lZyC7rv4Y4R6FA1Ynuw/E=';

  /// Номера отозванных лицензий: ключ утёк в общий доступ. Список приезжает
  /// с обновлением приложения — отзыв редок, ради него не нужен сервер.
  /// Не `const` ради тестов отзыва; в бою список задаётся только здесь.
  static Set<int> revoked = <int>{};

  static const String _kKey = 'licenseKey';
  static const String _prefix = 'FERN';
  static const int _formatVersion = 1;
  /// Именной ключ: внутри почта покупателя (с 1.17.3).
  static const int _formatVersionEmail = 2;
  static const int _skuPro = 1;

  /// Сколько ключ годен к вводу. Считать активации офлайн невозможно, поэтому
  /// ограничен не круг устройств, а срок жизни самого ключа: копия, ушедшая в
  /// сеть, протухает раньше, чем её кто-то увидит. Покупателя это не касается —
  /// бот выдаёт свежий ключ по первому запросу, хоть через год после оплаты.
  ///
  /// Окно действует только на именные ключи (формат 2): условия покупки тем,
  /// кто купил раньше, задним числом не меняем.
  static const int activationWindowDays = 3;

  /// Начало отсчёта дат выдачи — 1 января 2026. Дата нужна только для
  /// поддержки: по ней видно, когда ключ родился.
  static final DateTime epoch = DateTime.utc(2026, 1, 1);

  String? _key;
  LicenseInfo? _info;

  /// Публичный ключ можно подменить в тестах: проверку подписи надо гонять
  /// на своей паре, а не на боевой.
  @visibleForTesting
  static String? debugPublicKeyBase64;

  /// Подменное «сейчас» для тестов окна активации.
  @visibleForTesting
  static DateTime? debugNow;

  static DateTime get _now => debugNow ?? DateTime.now().toUtc();

  /// Ключ, лежащий на устройстве (для экрана настроек).
  String? get key => _key;

  /// Разобранная лицензия — `null`, если ключа нет или он не прошёл проверку.
  LicenseInfo? get info => _info;

  bool get isValid => _info != null;

  Future<void> load() async {
    final prefs = SharedPreferencesAsync();
    _key = await prefs.getString(_kKey);
    _info = _key == null ? null : await verify(_key!);
    // Ключ, который перестал быть годным (отозван новой версией), не держим:
    // иначе человек будет видеть «Pro» в настройках и не понимать, почему
    // функции закрыты.
    if (_key != null && _info == null) {
      await prefs.remove(_kKey);
      _key = null;
    }
    notifyListeners();
  }

  /// Проверяет ключ и, если он годный, сохраняет его на устройстве.
  ///
  /// Отдельно сообщает о просроченном ключе: человеку надо сказать, что делать
  /// («возьмите новый у бота»), а не отправлять его перепроверять буквы.
  ///
  /// [enforceWindow] снимают там, где ключ уже был принят раньше: при
  /// восстановлении резервной копии. Иначе человек, поднявший бэкап полугодовой
  /// давности, терял бы Pro на ровном месте.
  Future<ApplyResult> apply(String raw, {bool enforceWindow = true}) async {
    final info = await verify(raw);
    if (info == null) return const ApplyResult();
    if (enforceWindow && _outsideWindow(info)) {
      return const ApplyResult(expired: true);
    }
    _key = _normalize(raw);
    _info = info;
    await SharedPreferencesAsync().setString(_kKey, _key!);
    notifyListeners();
    return ApplyResult(info: info);
  }

  /// Ключ просрочен для ВВОДА. Уже принятый работает дальше без оглядки на
  /// дату: иначе Pro отвалился бы у покупателя на третий день.
  static bool _outsideWindow(LicenseInfo info) {
    if (info.email == null) return false; // формат 1 — без ограничения
    return _now.difference(info.issued).inDays > activationWindowDays;
  }

  Future<void> clear() async {
    _key = null;
    _info = null;
    await SharedPreferencesAsync().remove(_kKey);
    notifyListeners();
  }

  /// Разбирает ключ и сверяет подпись. `null` — ключ не годен, причина не
  /// уточняется: подсказка «подпись верна, но версия не та» помогает только
  /// тому, кто ключи подделывает.
  static Future<LicenseInfo?> verify(String raw) async {
    final text = _normalize(raw);
    if (!text.startsWith(_prefix)) return null;

    final Uint8List bytes;
    try {
      bytes = _Base32.decode(text.substring(_prefix.length));
    } on FormatException {
      return null;
    }
    if (bytes.length < 72) return null;

    // Формат 1 — восемь байт тела. Формат 2 добавляет длину и почту, поэтому
    // тело переменной длины; подпись всегда последние 64 байта.
    final Uint8List payload;
    final Uint8List signature;
    String? email;
    switch (bytes[0]) {
      case _formatVersion:
        if (bytes.length != 72) return null;
        payload = bytes.sublist(0, 8);
        signature = bytes.sublist(8);
      case _formatVersionEmail:
        final head = 9 + bytes[8];
        if (bytes.length != head + 64) return null;
        payload = bytes.sublist(0, head);
        signature = bytes.sublist(head);
        try {
          email = utf8.decode(payload.sublist(9));
        } on FormatException {
          return null; // почта не в UTF-8 — ключ собран не нами
        }
      default:
        return null;
    }
    if (payload[1] != _skuPro) return null;

    final id = ByteData.sublistView(payload).getUint32(2);
    if (revoked.contains(id)) return null;

    final pub = base64Decode(debugPublicKeyBase64 ?? publicKeyBase64);
    final ok = await Ed25519().verify(
      payload,
      signature: Signature(signature,
          publicKey: SimplePublicKey(pub, type: KeyPairType.ed25519)),
    );
    if (!ok) return null;

    final days = ByteData.sublistView(payload).getUint16(6);
    return LicenseInfo(
      id: id,
      issued: epoch.add(Duration(days: days)),
      email: email,
    );
  }

  /// Ключ читают из мессенджера, поэтому приводим к делу: пробелы, переносы и
  /// дефисы-разделители в счёт не идут, регистр не важен.
  static String _normalize(String raw) =>
      raw.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();
}

/// Чем закончился ввод ключа.
@immutable
class ApplyResult {
  /// Разобранная лицензия — `null`, если ключ не принят.
  final LicenseInfo? info;

  /// Ключ настоящий, но просрочен: пора взять свежий у бота.
  final bool expired;

  const ApplyResult({this.info, this.expired = false});
}

/// Что лежит внутри ключа.
@immutable
class LicenseInfo {
  /// Номер лицензии — по нему её отзывают и находят покупку в журнале бота.
  final int id;

  /// Когда ключ выдан.
  final DateTime issued;

  /// Почта покупателя — только у ключей формата 2. У выпущенных раньше `null`.
  final String? email;

  const LicenseInfo({required this.id, required this.issued, this.email});

  /// Адрес для показа: `vasya@mail.ru` → `va***@mail.ru`.
  ///
  /// Полностью показывать чужую почту незачем — узнать свою достаточно по
  /// первым буквам и домену, а на скриншоте настроек адрес не утечёт целиком.
  static String? maskEmail(String? email) {
    final value = email?.trim();
    if (value == null || value.isEmpty) return null;
    final at = value.lastIndexOf('@');
    if (at <= 0) return '***';
    final name = value.substring(0, at);
    final domain = value.substring(at);
    return name.length <= 2 ? '***$domain' : '${name.substring(0, 2)}***$domain';
  }
}

/// Base32 по RFC 4648 без выравнивания.
///
/// Своя реализация вместо пакета: нужны двадцать строк, а лишняя зависимость
/// в приложении живёт годами. Кодирование живёт на стороне бота
/// (`bot/license.py`), приложению нужно только разобрать ключ.
class _Base32 {
  static const String _alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

  static Uint8List decode(String text) {
    final out = <int>[];
    var buffer = 0;
    var bits = 0;
    for (final ch in text.split('')) {
      final value = _alphabet.indexOf(ch);
      if (value < 0) throw const FormatException('лишний символ в ключе');
      buffer = (buffer << 5) | value;
      bits += 5;
      if (bits >= 8) {
        out.add((buffer >> (bits - 8)) & 0xFF);
        bits -= 8;
      }
    }
    return Uint8List.fromList(out);
  }
}
