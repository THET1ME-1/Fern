import 'constructions.dart';
import 'source_library.dart';
import 'text_analysis.dart';

/// Сколько раз конструкция встречалась человеку в его собственных текстах.
class RuleStat {
  final String code;

  /// Всего вхождений во всех разобранных источниках.
  final int hits;

  /// В скольких источниках встретилась (книга, видео, разбор сообщения).
  final int sources;

  const RuleStat(this.code, this.hits, this.sources);
}

/// Статистика грамматики по Библиотеке.
///
/// Это то, чего нет ни у учебника, ни у Anki: правило показывается не «по
/// программе», а по тому, сколько раз оно уже попадалось В ТЕКСТАХ ЧЕЛОВЕКА.
/// Present Perfect, встреченный сорок семь раз в трёх книгах, стоит выучить
/// раньше, чем условное третьего типа, которое не встретилось ни разу.
class ConstructionStats {
  const ConstructionStats._();

  /// Сколько источников берём в расчёт (свежие сначала) и сколько символов из
  /// каждого. Роман целиком считать незачем: конструкции распределены по тексту
  /// ровно, а разбор мегабайта заметно тормозит экран.
  static const int maxSources = 12;
  static const int maxCharsPerSource = 40000;

  static final Map<String, Map<String, RuleStat>> _cache = {};

  /// Считает статистику языка (с кэшем на время сессии).
  static Future<Map<String, RuleStat>> forLanguage(
    String languageCode, {
    bool refresh = false,
  }) async {
    if (!refresh && _cache.containsKey(languageCode)) {
      return _cache[languageCode]!;
    }
    if (!Constructions.supports(languageCode)) {
      return _cache[languageCode] = const {};
    }
    final library = SourceLibrary.instance;
    final sources = (await library.list())
        .where((s) => s.languageCode == languageCode)
        .take(maxSources)
        .toList();

    final hits = <String, int>{};
    final inSources = <String, int>{};
    for (final source in sources) {
      final text = await _textOf(library, source);
      if (text == null || text.trim().isEmpty) continue;
      final slice = text.length > maxCharsPerSource
          ? text.substring(0, maxCharsPerSource)
          : text;
      // Словарь тут ни при чём — считаем только грамматику.
      final analysis = TextParse.analyzePlain(slice, languageCode);
      final seen = <String>{};
      for (final hit in Constructions.find(analysis, languageCode)) {
        hits[hit.code] = (hits[hit.code] ?? 0) + 1;
        seen.add(hit.code);
      }
      for (final code in seen) {
        inSources[code] = (inSources[code] ?? 0) + 1;
      }
    }
    final out = <String, RuleStat>{
      for (final e in hits.entries)
        e.key: RuleStat(e.key, e.value, inSources[e.key] ?? 0),
    };
    return _cache[languageCode] = out;
  }

  static Future<String?> _textOf(
    SourceLibrary library,
    LibrarySource source,
  ) async {
    if (source.isBook) return library.loadBookText(source.id);
    final transcript = await library.loadVideo(source.id);
    if (transcript == null) return null;
    return [for (final line in transcript.lines) line.text].join('\n');
  }

  /// Сбрасывает кэш (после разбора нового источника).
  static void invalidate([String? languageCode]) {
    if (languageCode == null) {
      _cache.clear();
    } else {
      _cache.remove(languageCode);
    }
  }
}

