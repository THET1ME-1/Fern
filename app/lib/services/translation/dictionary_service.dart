import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Словарные данные для обогащения перевода: часть речи, примеры, транскрипция.
///
/// Машинный перевод даёт слово; словарь добавляет контекст, который реально
/// помогает учить (как в Lingualeo). Для английского — `dictionaryapi.dev`
/// (примеры/фонетика/часть речи), для прочих языков — Wiktionary REST.
/// Работает только онлайн; при ошибке тихо возвращает пустой результат.
class DictionaryEntry {
  final String? partOfSpeech;
  final String? phonetic;
  final List<String> examples;
  final List<String> definitions;

  const DictionaryEntry({
    this.partOfSpeech,
    this.phonetic,
    this.examples = const [],
    this.definitions = const [],
  });

  bool get isEmpty =>
      partOfSpeech == null &&
      phonetic == null &&
      examples.isEmpty &&
      definitions.isEmpty;
}

class DictionaryService {
  DictionaryService._();

  /// Слово [word] на языке [langCode]. Одно слово — иначе словарь бесполезен.
  static Future<DictionaryEntry> lookup(String word, String langCode) async {
    final w = word.trim();
    if (w.isEmpty || w.contains(' ')) return const DictionaryEntry();
    try {
      if (langCode == 'en') return await _freeDict(w);
      return await _wiktionary(w, langCode);
    } catch (e) {
      debugPrint('DictionaryService failed: $e');
      return const DictionaryEntry();
    }
  }

  static Future<DictionaryEntry> _freeDict(String w) async {
    final uri = Uri.https(
      'api.dictionaryapi.dev',
      '/api/v2/entries/en/${Uri.encodeComponent(w)}',
    );
    final resp = await http.get(uri).timeout(const Duration(seconds: 8));
    if (resp.statusCode != 200) return const DictionaryEntry();
    final data = jsonDecode(utf8.decode(resp.bodyBytes)) as List;
    if (data.isEmpty) return const DictionaryEntry();
    final first = data.first as Map<String, dynamic>;
    final phonetic = (first['phonetic'] as String?)?.trim();
    final meanings = first['meanings'] as List? ?? const [];
    String? pos;
    final examples = <String>[];
    final definitions = <String>[];
    for (final m in meanings) {
      final mm = m as Map<String, dynamic>;
      pos ??= mm['partOfSpeech'] as String?;
      for (final d in (mm['definitions'] as List? ?? const [])) {
        final dd = d as Map<String, dynamic>;
        final def = (dd['definition'] as String?)?.trim();
        final ex = (dd['example'] as String?)?.trim();
        if (def != null && def.isNotEmpty && definitions.length < 3) {
          definitions.add(def);
        }
        if (ex != null && ex.isNotEmpty && examples.length < 3) {
          examples.add(ex);
        }
      }
    }
    return DictionaryEntry(
      partOfSpeech: pos,
      phonetic: (phonetic != null && phonetic.isNotEmpty) ? phonetic : null,
      examples: examples,
      definitions: definitions,
    );
  }

  static Future<DictionaryEntry> _wiktionary(String w, String lang) async {
    final uri = Uri.https(
      '$lang.wiktionary.org',
      '/api/rest_v1/page/definition/${Uri.encodeComponent(w)}',
    );
    final resp = await http.get(uri).timeout(const Duration(seconds: 8));
    if (resp.statusCode != 200) return const DictionaryEntry();
    final data = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    // Ответ: { "<lang>": [ { partOfSpeech, definitions:[{definition, examples[]}] } ] }
    final entries = data[lang] as List? ?? data.values.firstOrNull as List?;
    if (entries == null || entries.isEmpty) return const DictionaryEntry();
    String? pos;
    final examples = <String>[];
    final definitions = <String>[];
    for (final e in entries) {
      final ee = e as Map<String, dynamic>;
      pos ??= ee['partOfSpeech'] as String?;
      for (final d in (ee['definitions'] as List? ?? const [])) {
        final dd = d as Map<String, dynamic>;
        final def = _stripHtml((dd['definition'] as String?) ?? '');
        if (def.isNotEmpty && definitions.length < 3) definitions.add(def);
        for (final ex in (dd['examples'] as List? ?? const [])) {
          final s = _stripHtml('$ex');
          if (s.isNotEmpty && examples.length < 3) examples.add(s);
        }
      }
    }
    return DictionaryEntry(
      partOfSpeech: pos,
      examples: examples,
      definitions: definitions,
    );
  }

  static String _stripHtml(String s) =>
      s.replaceAll(RegExp(r'<[^>]*>'), '').trim();
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
