import 'dart:math' as math;

import '../models/fsrs.dart';
import '../models/word_card.dart';
import 'deck_repository.dart';
import 'lemmatizer.dart';

/// Слово книги с частотой встречаемости.
class WordFreq {
  final String word;
  final int count;
  const WordFreq(this.word, this.count);
}

/// Разобранный текст книги: уникальные слова, их основы и частоты. Зависит
/// только от текста, поэтому считается один раз и переживает любые изменения
/// словаря.
class BookTokens {
  final List<String> words;
  final List<String> stems;
  final List<int> counts;

  const BookTokens({
    required this.words,
    required this.stems,
    required this.counts,
  });

  static const BookTokens empty =
      BookTokens(words: [], stems: [], counts: []);

  bool get isEmpty => words.isEmpty;
}

/// Точка входа для `compute` — токенизация книги в фоновом изоляте (на романе
/// это сотни миллисекунд, на UI-потоке они превращались в подвисание).
BookTokens prepareBookTokens((String, String) args) =>
    BookAnalysis.prepare(args.$1, args.$2);

/// Умный анализ словаря книги.
///
/// Идея: по тексту книги считаем уникальные слова и их частоты, а затем сверяем
/// с личным словарём (карточками этого языка). Для слов, которые уже в словаре,
/// смотрим на память по FSRS — вероятность вспомнить прямо сейчас (R). Отсюда
/// три группы:
///  * **Помнит** — слово в словаре и память крепкая (R ≥ порога);
///  * **Учит** — слово в словаре, но память слабая / просрочено / ещё новое;
///  * **Не знает** — слова нет в словаре.
///
/// Плюс «покрытие» — какую долю ВСЕХ слов текста (с учётом повторов) читатель
/// уже знает: главный ориентир, насколько книга по силам (для комфортного
/// чтения обычно нужно ~95%+ знакомых слов).
class BookAnalysis {
  /// Всего слов в тексте (с повторами).
  final int totalTokens;

  /// Уникальных слов (типов).
  final int uniqueTypes;

  /// Уникальных слов не в словаре.
  final int unknownTypes;

  /// Уникальных слов в словаре, но со слабой памятью.
  final int learningTypes;

  /// Уникальных слов в словаре с крепкой памятью.
  final int knownTypes;

  /// Доля всех слов текста (с повторами), которые есть в словаре (0..1).
  final double coverage;

  /// Доля всех слов текста, которые читатель уверенно помнит (0..1).
  final double masteredCoverage;

  /// Самые частые слова, которых ещё нет в словаре (что учить в первую очередь).
  final List<WordFreq> topUnknown;

  const BookAnalysis({
    required this.totalTokens,
    required this.uniqueTypes,
    required this.unknownTypes,
    required this.learningTypes,
    required this.knownTypes,
    required this.coverage,
    required this.masteredCoverage,
    required this.topUnknown,
  });

  /// Сколько уникальных слов книги уже в словаре (учит + помнит).
  int get inDictionaryTypes => learningTypes + knownTypes;

  /// Доля словаря книги, уже собранная в карточки (0..1).
  double get dictionaryShare =>
      uniqueTypes == 0 ? 0 : inDictionaryTypes / uniqueTypes;

  static const BookAnalysis empty = BookAnalysis(
    totalTokens: 0,
    uniqueTypes: 0,
    unknownTypes: 0,
    learningTypes: 0,
    knownTypes: 0,
    coverage: 0,
    masteredCoverage: 0,
    topUnknown: [],
  );

  // Порог вероятности вспомнить: выше — «помнит», ниже — «подзабыл/учит».
  static const double _strongRetention = 0.9;
  static const int _topUnknownLimit = 60;

  // Обрезаем ведущую/замыкающую пунктуацию, как это делает читалка при добавлении
  // слова, — чтобы совпадать с «передами» карточек.
  static final RegExp _edge = RegExp(
    r'^[^\p{L}\p{N}]+|[^\p{L}\p{N}]+$',
    unicode: true,
  );
  static final RegExp _letter = RegExp(r'\p{L}', unicode: true);
  static final RegExp _ws = RegExp(r'\S+');

  /// Считает частоты уникальных слов текста (нижний регистр). Пропускает токены
  /// без букв (числа/пунктуацию).
  static Map<String, int> tokenize(String text) {
    final freq = <String, int>{};
    for (final m in _ws.allMatches(text)) {
      final clean = m.group(0)!.replaceAll(_edge, '');
      if (clean.isEmpty || !_letter.hasMatch(clean)) continue;
      final key = clean.toLowerCase();
      freq[key] = (freq[key] ?? 0) + 1;
    }
    return freq;
  }

  /// Текущая вероятность вспомнить карту (0..1) по FSRS.
  static double _retention(WordCard card, DateTime now) {
    final r = card.review;
    if (r.state == FsrsState.newCard || r.lastReview == null) return 0;
    final elapsed =
        math.max(0.0, now.difference(r.lastReview!).inSeconds / 86400.0);
    return Fsrs.instance.retrievability(elapsed, r.stability);
  }

  /// Разбор текста книги: частоты слов и их основы. От словаря НЕ зависит,
  /// поэтому считается один раз на книгу (можно в фоновом изоляте) и потом
  /// переиспользуется — добавление слова больше не гоняет токенизацию романа
  /// заново.
  static BookTokens prepare(String text, String languageCode) {
    final freq = tokenize(text);
    final words = <String>[];
    final stems = <String>[];
    final counts = <int>[];
    freq.forEach((word, count) {
      words.add(word);
      stems.add(Lemmatizer.stem(word, languageCode));
      counts.add(count);
    });
    return BookTokens(words: words, stems: stems, counts: counts);
  }

  /// Полный анализ текста для языка [languageCode] (использует кэш словаря).
  static BookAnalysis analyze(String text, String languageCode) =>
      analyzeTokens(prepare(text, languageCode), languageCode);

  /// Анализ по уже разобранному тексту — дешёвая часть: сверка с текущим
  /// словарём и подсчёт покрытия.
  static BookAnalysis analyzeTokens(BookTokens t, String languageCode) {
    if (t.isEmpty) return empty;

    // Индексируем карточки по ОСНОВЕ слова (лемматизация) — чтобы «foxes»
    // засчитывалось к карточке «fox», «runs» к «run» и т.п.
    final byFront =
        DeckRepository.instance.cardsByFrontForLanguage(languageCode);
    final cards = <String, WordCard>{};
    byFront.forEach((front, card) {
      final stem = Lemmatizer.stem(front, languageCode);
      final existing = cards[stem];
      if (existing == null ||
          card.review.stability > existing.review.stability) {
        cards[stem] = card;
      }
    });
    final now = DateTime.now();

    var totalTokens = 0;
    var unknownTypes = 0;
    var learningTypes = 0;
    var knownTypes = 0;
    var coveredTokens = 0;
    var masteredTokens = 0;
    final unknown = <WordFreq>[];

    for (var i = 0; i < t.words.length; i++) {
      final count = t.counts[i];
      totalTokens += count;
      final card = cards[t.stems[i]];
      if (card == null) {
        unknownTypes++;
        unknown.add(WordFreq(t.words[i], count));
        continue;
      }
      coveredTokens += count;
      final strong = card.review.state == FsrsState.review &&
          _retention(card, now) >= _strongRetention;
      if (strong) {
        knownTypes++;
        masteredTokens += count;
      } else {
        learningTypes++;
      }
    }

    unknown.sort((a, b) {
      final byCount = b.count.compareTo(a.count);
      return byCount != 0 ? byCount : a.word.compareTo(b.word);
    });

    return BookAnalysis(
      totalTokens: totalTokens,
      uniqueTypes: t.words.length,
      unknownTypes: unknownTypes,
      learningTypes: learningTypes,
      knownTypes: knownTypes,
      coverage: totalTokens == 0 ? 0 : coveredTokens / totalTokens,
      masteredCoverage: totalTokens == 0 ? 0 : masteredTokens / totalTokens,
      topUnknown: unknown.take(_topUnknownLimit).toList(),
    );
  }

  /// Сколько уникальных НЕзнакомых слов в каждой главе (по [chapterStarts] —
  /// индексам стартовых абзацев). Для «словаря по главам».
  static List<int> chapterUnknownCounts(
    String text,
    List<int> chapterStarts,
    String languageCode,
  ) {
    if (chapterStarts.isEmpty) return const [];
    final byFront =
        DeckRepository.instance.cardsByFrontForLanguage(languageCode);
    final knownStems = <String>{
      for (final f in byFront.keys) Lemmatizer.stem(f, languageCode),
    };
    final paragraphs = text
        .split('\n')
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();
    final counts = List<int>.filled(chapterStarts.length, 0);
    for (var ci = 0; ci < chapterStarts.length; ci++) {
      final start = chapterStarts[ci];
      final end = ci + 1 < chapterStarts.length
          ? chapterStarts[ci + 1]
          : paragraphs.length;
      final seen = <String>{};
      for (var p = start; p < end && p < paragraphs.length; p++) {
        for (final m in _ws.allMatches(paragraphs[p])) {
          final clean = m.group(0)!.replaceAll(_edge, '');
          if (clean.isEmpty || !_letter.hasMatch(clean)) continue;
          final stem = Lemmatizer.stem(clean.toLowerCase(), languageCode);
          if (!knownStems.contains(stem)) seen.add(stem);
        }
      }
      counts[ci] = seen.length;
    }
    return counts;
  }
}
