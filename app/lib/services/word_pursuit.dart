import 'book_analysis.dart';
import 'deck_repository.dart';
import 'lemmatizer.dart';
import 'source_library.dart';
import 'word_priority.dart';

/// Незнакомое слово, которое попадается в РАЗНЫХ источниках.
class PursuingWord {
  final String word;

  /// В скольких источниках встретилось.
  final int sources;

  /// Сколько раз всего.
  final int count;

  const PursuingWord(this.word, this.sources, this.count);
}

/// Слова, которые преследуют человека по его же библиотеке.
///
/// Частотный словарь языка говорит, что слово частое «вообще». Здесь считается
/// другое: слово попалось в книге, в видео и в разобранном сообщении, а
/// карточки для него до сих пор нет. Такое стоит выучить раньше любого топа —
/// оно уже мешает читать три раза.
class WordPursuit {
  const WordPursuit._();

  /// Сколько источников берём и сколько символов из каждого — те же рамки, что
  /// у статистики грамматики: считать роман целиком незачем.
  static const int maxSources = 12;
  static const int maxCharsPerSource = 40000;

  /// Минимум источников, чтобы слово считалось преследователем. Один источник —
  /// это просто незнакомое слово из книги, их и так показывает разбор.
  static const int minSources = 2;

  static Future<List<PursuingWord>> forLanguage(
    String languageCode, {
    int limit = 20,
  }) async {
    final library = SourceLibrary.instance;
    final sources = (await library.list())
        .where((s) => s.languageCode == languageCode)
        .take(maxSources)
        .toList();
    if (sources.length < minSources) return const [];

    final known = <String>{
      for (final front in DeckRepository.instance
          .cardsByFrontForLanguage(languageCode)
          .keys)
        Lemmatizer.stem(front, languageCode),
    };

    final counts = <String, int>{};
    final capitals = <String, int>{};
    final inSources = <String, int>{};
    final display = <String, String>{};

    for (final source in sources) {
      final text = await _textOf(library, source);
      if (text == null || text.trim().isEmpty) continue;
      final slice = text.length > maxCharsPerSource
          ? text.substring(0, maxCharsPerSource)
          : text;
      final (freq, caps) = BookAnalysis.tokenizeWithCase(slice);
      final seen = <String>{};
      freq.forEach((word, n) {
        final stem = Lemmatizer.stem(word, languageCode);
        if (known.contains(stem)) return;
        counts[stem] = (counts[stem] ?? 0) + n;
        capitals[stem] = (capitals[stem] ?? 0) + (caps[word] ?? 0);
        // Показываем ту форму, которая встретилась первой: основа вроде «writ»
        // человеку ни о чём не говорит.
        display.putIfAbsent(stem, () => word);
        seen.add(stem);
      });
      for (final stem in seen) {
        inSources[stem] = (inSources[stem] ?? 0) + 1;
      }
    }

    final candidates = <PursuingWord>[];
    for (final entry in inSources.entries) {
      if (entry.value < minSources) continue;
      final stem = entry.key;
      final word = display[stem] ?? stem;
      final total = counts[stem] ?? 0;
      // Служебные слова и имена собственные отсекаем тем же правилом, что и
      // «учить в первую очередь» в разборе книги.
      if (WordPriority.isFunctionWord(word, languageCode)) continue;
      if (WordPriority.looksProper(
        capitalized: capitals[stem] ?? 0,
        total: total,
      )) {
        continue;
      }
      candidates.add(PursuingWord(word, entry.value, total));
    }

    candidates.sort((a, b) {
      final bySources = b.sources.compareTo(a.sources);
      if (bySources != 0) return bySources;
      final byCount = b.count.compareTo(a.count);
      return byCount != 0 ? byCount : a.word.compareTo(b.word);
    });
    return candidates.take(limit).toList();
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
}

