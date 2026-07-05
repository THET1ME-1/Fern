import 'dart:convert';
import 'dart:io' show gzip;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

/// Офлайн-словарь частей речи. Точная альтернатива эвристикам по суффиксам
/// (которые путали, напр., `library`/`salary`/`motive` — существительные — с
/// прилагательными). Источник — Moby Part-of-Speech (Grady Ward, public domain,
/// ~181k английских слов, коды в порядке приоритета → берётся основной).
///
/// Ассет — `assets/pos/en.pos.gz` (gzip: строки «слово\tкод», код — 1 символ).
/// Грузится ЛЕНИВО и один раз; при ошибке деградирует на пустую карту (детекция
/// откатывается на служебные слова + консервативные суффиксы).
class PosDictionary {
  PosDictionary._();
  static final PosDictionary instance = PosDictionary._();

  Map<String, String>? _en; // слово (нижний регистр) → канонический код
  Future<void>? _loading;

  bool get isReady => _en != null;

  /// Гарантирует, что словарь языка загружен. Пока поддержан только английский.
  Future<void> ensureLoaded(String lang) {
    if (lang != 'en' || _en != null) return Future.value();
    return _loading ??= _loadEn();
  }

  Future<void> _loadEn() async {
    try {
      final data = await rootBundle.load('assets/pos/en.pos.gz');
      final bytes = data.buffer
          .asUint8List(data.offsetInBytes, data.lengthInBytes);
      final text = utf8.decode(gzip.decode(bytes));
      final map = <String, String>{};
      for (final line in const LineSplitter().convert(text)) {
        final t = line.indexOf('\t');
        if (t <= 0 || t + 1 >= line.length) continue;
        final code = _expand(line.codeUnitAt(t + 1));
        if (code != null) map[line.substring(0, t)] = code;
      }
      _en = map;
    } catch (e) {
      debugPrint('PosDictionary: не загрузился словарь ($e)');
      _en = <String, String>{}; // деградация на эвристику
    } finally {
      _loading = null;
    }
  }

  /// Часть речи слова (ожидается нижний регистр) или null, если нет в словаре /
  /// язык не поддержан / словарь ещё не загружен.
  String? lookup(String word, String lang) {
    if (lang != 'en') return null;
    return _en?[word];
  }

  // Компактный 1-символьный код в ассете → канонический код PosDetect.
  static String? _expand(int unit) {
    switch (unit) {
      case 0x6e: // n
        return 'noun';
      case 0x76: // v
        return 'verb';
      case 0x61: // a
        return 'adj';
      case 0x64: // d
        return 'adv';
      case 0x72: // r
        return 'pronoun';
      case 0x74: // t
        return 'article';
      case 0x70: // p
        return 'prep';
      case 0x63: // c
        return 'conj';
      case 0x78: // x
        return 'interj';
      default:
        return null;
    }
  }
}
