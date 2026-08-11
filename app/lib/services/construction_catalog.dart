import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../l10n/locale_controller.dart';

/// Описание грамматической конструкции: как называется, какого уровня, что
/// значит и на каких примерах видно.
class Construction {
  /// Код правила — тот же, что возвращает детектор.
  final String code;

  /// Уровень CEFR: A1, A2, B1, B2, C1.
  final String level;

  /// Название термином («Present Perfect»). Не переводится: в учебниках всех
  /// семи языков время называют одинаково, а перевод названия только мешает
  /// потом искать объяснение на стороне.
  final String name;

  /// Объяснение по языкам интерфейса.
  final Map<String, String> hints;

  final List<String> examples;

  const Construction({
    required this.code,
    required this.level,
    required this.name,
    required this.hints,
    required this.examples,
  });

  /// Объяснение на языке интерфейса (откат: английский → русский → пусто).
  String hint([String? uiLang]) {
    final code = uiLang ?? LocaleController.instance.code;
    return hints[code] ?? hints['en'] ?? hints['ru'] ?? '';
  }

  factory Construction.fromJson(Map<String, dynamic> j) => Construction(
        code: j['code'] as String,
        level: j['level'] as String? ?? 'A1',
        name: j['name'] as String? ?? j['code'] as String,
        hints: ((j['hint'] as Map?) ?? const {})
            .map((k, v) => MapEntry(k as String, v as String)),
        examples: [for (final e in (j['examples'] as List? ?? const [])) '$e'],
      );
}

/// Каталог конструкций: читает `assets/grammar/<язык>.json`.
///
/// Описания лежат ассетом, а не в `strings.dart`, по двум причинам: их семь
/// языков на каждое правило (файл словаря раздулся бы вдвое), и набор правил
/// свой у каждого ИЗУЧАЕМОГО языка — новый язык добавляется файлом, без правки
/// кода.
class ConstructionCatalog {
  ConstructionCatalog._();

  static final ConstructionCatalog instance = ConstructionCatalog._();

  final Map<String, Map<String, Construction>> _byLang = {};

  /// Порядок уровней для показа.
  static const List<String> levels = ['A1', 'A2', 'B1', 'B2', 'C1'];

  /// Загружает каталог языка (повторные вызовы бесплатны). Ошибку чтения глушим
  /// пустым каталогом: без описаний разбор слов работает по-прежнему.
  Future<void> ensureLoaded(String languageCode) async {
    final lang = languageCode.split('-').first.toLowerCase();
    if (_byLang.containsKey(lang)) return;
    try {
      final raw = await rootBundle.loadString('assets/grammar/$lang.json');
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final rules = <String, Construction>{};
      for (final r in (data['rules'] as List? ?? const [])) {
        final c = Construction.fromJson((r as Map).cast<String, dynamic>());
        rules[c.code] = c;
      }
      _byLang[lang] = rules;
    } catch (e) {
      debugPrint('ConstructionCatalog: $lang не загружен ($e)');
      _byLang[lang] = const {};
    }
  }

  bool isLoaded(String languageCode) =>
      _byLang.containsKey(languageCode.split('-').first.toLowerCase());

  /// Все правила языка по возрастанию уровня.
  List<Construction> all(String languageCode) {
    final rules = _byLang[languageCode.split('-').first.toLowerCase()];
    if (rules == null) return const [];
    final out = rules.values.toList()
      ..sort((a, b) {
        final byLevel =
            levels.indexOf(a.level).compareTo(levels.indexOf(b.level));
        return byLevel != 0 ? byLevel : a.name.compareTo(b.name);
      });
    return out;
  }

  /// Правило по коду или null.
  Construction? byCode(String code, String languageCode) =>
      _byLang[languageCode.split('-').first.toLowerCase()]?[code];

  @visibleForTesting
  void resetForTest() => _byLang.clear();
}

