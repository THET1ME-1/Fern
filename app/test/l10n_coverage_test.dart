import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fern/l10n/strings.dart';
import 'package:fern/l10n/translations.dart';

/// Плейсхолдеры вида `{n}`, `{name}` — они должны совпадать с оригиналом,
/// иначе строка соберётся с дырой или лишним текстом в фигурных скобках.
Set<String> _placeholders(String s) =>
    RegExp(r'\{(\w+)\}').allMatches(s).map((m) => m.group(1)!).toSet();

void main() {
  test('во всех языках есть все ключи', () {
    final missing = <String, List<String>>{};
    for (final lang in kTranslations.keys) {
      final have = kTranslations[lang]!;
      final gaps = [
        for (final key in kBaseStrings.keys)
          if (!have.containsKey(key) || have[key]!.isEmpty) key,
      ];
      if (gaps.isNotEmpty) missing[lang] = gaps;
    }
    expect(missing, isEmpty,
        reason: 'без ключа язык молча откатывается на английский');
  });

  test('плейсхолдеры переводов совпадают с оригиналом', () {
    final broken = <String>[];
    for (final lang in kTranslations.keys) {
      kTranslations[lang]!.forEach((key, value) {
        final origin = kBaseStrings[key]?['en'] ?? kBaseStrings[key]?['ru'];
        if (origin == null) return;
        // setEquals, а не `!=`: у Set сравнение по ссылке, и два пустых
        // множества никогда не равны.
        if (!setEquals(_placeholders(value), _placeholders(origin))) {
          broken.add('$lang/$key');
        }
      });
    }
    expect(broken, isEmpty);
  });

  test('в переводах нет ключей, которых больше нет в оригинале', () {
    final stale = <String>[];
    for (final lang in kTranslations.keys) {
      for (final key in kTranslations[lang]!.keys) {
        if (!kBaseStrings.containsKey(key)) stale.add('$lang/$key');
      }
    }
    expect(stale, isEmpty, reason: 'мёртвые ключи копятся и путают');
  });
}
