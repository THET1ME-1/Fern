import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/language.dart';
import 'deck_repository.dart';

/// Реестр изучаемых языков: встроенные ([kStudyLanguages]) + свои (созданные
/// пользователем) + закреплённые (показываются вверху списка, чтобы не искать).
///
/// Единый источник правды для баннера, пикера и карточек «язык источника».
/// Свои языки и закрепления хранятся в [DeckRepository] (prefs), грузятся один
/// раз в `main` до UI. Резолвинг [byCode] проверяет сперва свои языки, поэтому
/// созданные языки подхватываются во всём приложении.
class LanguageRegistry extends ChangeNotifier {
  LanguageRegistry._();
  static final LanguageRegistry instance = LanguageRegistry._();

  final DeckRepository _repo = DeckRepository.instance;

  final List<StudyLanguage> _custom = [];
  final List<String> _pinned = []; // коды; порядок = порядок показа

  /// Загружает свои языки и закрепления. Вызывается один раз до `runApp`.
  Future<void> load() async {
    _custom
      ..clear()
      ..addAll(_parseLangs(await _repo.customLanguagesRaw()));
    _pinned
      ..clear()
      ..addAll(_parseCodes(await _repo.pinnedLanguagesRaw()));
    notifyListeners();
  }

  List<StudyLanguage> get custom => List.unmodifiable(_custom);
  List<String> get pinnedCodes => List.unmodifiable(_pinned);

  bool isCustom(String code) => _custom.any((l) => l.code == code);
  bool isPinned(String code) => _pinned.contains(code);
  bool isKnown(String code) => byCode(code) != null;

  /// Язык по коду: сперва свои (могут переопределять/дополнять встроенные),
  /// затем встроенные. `null`, если код неизвестен.
  StudyLanguage? byCode(String code) {
    for (final l in _custom) {
      if (l.code == code) return l;
    }
    return languageByCode(code);
  }

  /// Полный список для пикера: сперва закреплённые (в порядке закрепления),
  /// затем остальные (встроенные + свои; свои — после встроенных).
  List<StudyLanguage> get all {
    final merged = <StudyLanguage>[...kStudyLanguages];
    for (final c in _custom) {
      final i = merged.indexWhere((l) => l.code == c.code);
      if (i >= 0) {
        merged[i] = c; // свой переопределяет одноимённый встроенный
      } else {
        merged.add(c);
      }
    }
    final pinned = <StudyLanguage>[];
    for (final code in _pinned) {
      final l = merged.where((e) => e.code == code).firstOrNull;
      if (l != null) pinned.add(l);
    }
    final rest = merged.where((l) => !_pinned.contains(l.code)).toList();
    return [...pinned, ...rest];
  }

  /// Добавляет или обновляет свой язык (по коду). [pin] — сразу закрепить.
  Future<void> addOrUpdateCustom(StudyLanguage lang, {bool pin = false}) async {
    final i = _custom.indexWhere((l) => l.code == lang.code);
    if (i >= 0) {
      _custom[i] = lang;
    } else {
      _custom.add(lang);
    }
    if (pin && !_pinned.contains(lang.code)) _pinned.insert(0, lang.code);
    await _persist();
    notifyListeners();
  }

  /// Удаляет свой язык из списка (колоды/слова на нём НЕ трогаются).
  Future<void> removeCustom(String code) async {
    _custom.removeWhere((l) => l.code == code);
    _pinned.remove(code);
    await _persist();
    notifyListeners();
  }

  Future<void> setPinned(String code, bool pinned) async {
    if (pinned) {
      if (!_pinned.contains(code)) _pinned.add(code);
    } else {
      _pinned.remove(code);
    }
    await _persist();
    notifyListeners();
  }

  Future<void> togglePin(String code) => setPinned(code, !isPinned(code));

  Future<void> _persist() async {
    await _repo.setCustomLanguagesRaw(
        jsonEncode([for (final l in _custom) l.toJson()]));
    await _repo.setPinnedLanguagesRaw(jsonEncode(_pinned));
  }

  static List<StudyLanguage> _parseLangs(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final out = <StudyLanguage>[];
      for (final e in (jsonDecode(raw) as List)) {
        if (e is! Map) continue;
        final lang = StudyLanguage.fromJson(e.cast<String, dynamic>());
        if (lang.code.isNotEmpty) out.add(lang);
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  static List<String> _parseCodes(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      return [
        for (final e in (jsonDecode(raw) as List))
          if (e is String && e.isNotEmpty) e,
      ];
    } catch (_) {
      return const [];
    }
  }

  @visibleForTesting
  void resetForTest() {
    _custom.clear();
    _pinned.clear();
  }
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
