import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'translation_provider.dart';

/// Встроенный онлайн-переводчик на бесплатном web-endpoint Google Translate
/// (`translate.googleapis.com/translate_a/single`, client=gtx). Без ключа,
/// высокое качество, все языки. `dt=t` даёт перевод, `dt=bd` — словарные
/// альтернативы по частям речи (то, что рушится у ML Kit на многозначных словах).
///
/// Неофициальный endpoint: может быть недоступен/заблокирован (в т.ч. в РФ) —
/// тогда возвращаем null и менеджер уходит на офлайн-fallback.
class OnlineMtProvider extends TranslationProvider {
  @override
  String get id => 'google';

  @override
  String get name => 'Google';

  @override
  bool get isOffline => false;

  @override
  String get kindLabel => 'online';

  @override
  bool supportsPair(String from, String to) => from != to;

  @override
  Future<bool> isReady(String from, String to) async => from != to;

  @override
  Future<TransResult?> translate(
    String text,
    String from,
    String to, {
    String? context,
  }) async {
    final q = text.trim();
    if (q.isEmpty || from == to) return null;
    final uri = Uri.https('translate.googleapis.com', '/translate_a/single', {
      'client': 'gtx',
      'sl': from,
      'tl': to,
      'dt': 't',
      'q': q,
    });
    // Второй dt (словарь альтернатив) добавляем отдельным параметром вручную,
    // т.к. Uri.https схлопывает одинаковые ключи в один.
    final full = Uri.parse('$uri&dt=bd');
    try {
      final resp = await http
          .get(full, headers: const {'User-Agent': 'Mozilla/5.0'})
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return null;
      final data = jsonDecode(utf8.decode(resp.bodyBytes)) as List;

      // [0] — предложения перевода: [[translated, original, ...], ...]
      final buf = StringBuffer();
      if (data.isNotEmpty && data[0] is List) {
        for (final seg in (data[0] as List)) {
          if (seg is List && seg.isNotEmpty && seg[0] is String) {
            buf.write(seg[0] as String);
          }
        }
      }
      final primary = buf.toString().trim();
      if (primary.isEmpty) return null;

      // [1] — словарь: [[pos, [term1, term2, ...], ...], ...]
      final alternatives = <String>[];
      String? pos;
      if (data.length > 1 && data[1] is List) {
        for (final entry in (data[1] as List)) {
          if (entry is! List || entry.length < 2) continue;
          pos ??= entry[0] as String?;
          if (entry[1] is List) {
            for (final term in (entry[1] as List)) {
              if (term is String) alternatives.add(term);
            }
          }
        }
      }
      return TransResult(
        primary: primary,
        alternatives: alternatives,
        partOfSpeech: pos,
        sourceId: id,
      );
    } catch (e) {
      debugPrint('OnlineMtProvider failed: $e');
      return null;
    }
  }
}
