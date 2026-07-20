import 'lemmatizer.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import 'source_library.dart';

/// Слова, которые человеку вот-вот встретятся в книге.
///
/// Fern знает и текст книги, и место, где чтение остановилось. Значит, может
/// подсунуть на повторение именно те слова, что попадутся вечером на следующих
/// страницах: выучил — встретил — память замкнулась на живом контексте, а не на
/// карточке. Обычному SRS такое недоступно: у него нет книги.
class ReadingHorizon {
  const ReadingHorizon._();

  /// Сколько абзацев вперёд считаем «ближайшими страницами».
  static const int lookaheadParagraphs = 120;

  /// Потолок слов в горизонте — чтобы длинный роман не вытеснил всё остальное.
  static const int maxWords = 1500;

  // Апострофов два: прямой (') и типографский (’, U+2019). В вычитанных EPUB
  // сокращения набраны вторым, и без него don’t распадалось на don и t.
  // Обрубок можно принять за настоящее слово: can из can’t — частое слово, и
  // карточка «can» ложно считалась «скоро встретится в книге».
  static final RegExp _word =
      RegExp(r"[\p{L}][\p{L}\-'\u2019]*", unicode: true);

  /// Разбор строки на слова — точка входа для тестов.
  @visibleForTesting
  static List<String> debugWords(String text) =>
      _word.allMatches(text).map((m) => m[0]!).toList();

  static Set<String> _cache = {};
  static String _cacheKey = '';

  /// Основы слов из ближайших абзацев книг, которые сейчас читаются на языке
  /// [languageCode]. Пустое множество, если открытых книг нет.
  static Future<Set<String>> upcoming(String languageCode) async {
    final library = SourceLibrary.instance;
    final sources = await library.list();
    final active = sources
        .where((s) =>
            s.isBook &&
            s.isStarted &&
            !s.isFinished &&
            s.languageCode.split('-').first == languageCode)
        .toList();
    if (active.isEmpty) {
      _cacheKey = '';
      _cache = {};
      return _cache;
    }

    // Ключ кэша — книги и позиции в них: пока человек не продвинулся, читать
    // файлы заново незачем.
    final key = active.map((s) => '${s.id}:${s.readParagraph}').join('|');
    if (key == _cacheKey) return _cache;

    final stems = <String>{};
    var budget = maxWords;
    for (final source in active) {
      if (budget <= 0) break;
      final text = await library.loadBookText(source.id);
      if (text == null) continue;
      final paragraphs = text
          .split('\n')
          .map((p) => p.trim())
          .where((p) => p.isNotEmpty)
          .toList();
      final from = source.readParagraph.clamp(0, paragraphs.length);
      final to = (from + lookaheadParagraphs).clamp(0, paragraphs.length);
      for (var i = from; i < to && budget > 0; i++) {
        for (final m in _word.allMatches(paragraphs[i])) {
          final w = m.group(0)!;
          if (w.length < 2) continue;
          stems.add(Lemmatizer.stem(w, languageCode));
          budget--;
          if (budget <= 0) break;
        }
      }
    }

    _cacheKey = key;
    _cache = stems;
    return stems;
  }

  /// Сбрасывает кэш (тесты и «удалить все данные»).
  static void resetCache() {
    _cacheKey = '';
    _cache = {};
  }
}
