import 'dart:math' as math;

import '../models/fsrs.dart';
import '../models/word_card.dart';
import 'deck_repository.dart';
import 'lemmatizer.dart';
import 'pos.dart';

/// Что человек знает о слове прямо сейчас.
enum WordStatus {
  /// Карточка есть, память крепкая.
  known,

  /// Карточка есть, но слово ещё не улеглось (новое, просрочено, слабое).
  learning,

  /// Карточки нет.
  unknown,

  /// Числа и прочие токены без букв — учить нечего.
  ignored,
}

/// Слово текста с разбором: где стоит, к чему сводится, что человек о нём знает.
class AnalyzedToken {
  /// Слово, как оно написано в тексте (регистр и форма сохранены).
  final String surface;

  /// Основа для сверки со словарём ([Lemmatizer.stem]).
  final String lemma;

  /// Часть речи (канонический код) или '' — неизвестно.
  final String pos;

  final WordStatus status;

  /// Позиции в исходном тексте: `text.substring(start, end) == surface`.
  /// На этом держится подсветка, поэтому позиции считаются, а не ищутся заново.
  final int start;
  final int end;

  /// Индекс предложения в [TextAnalysis.sentences].
  final int sentence;

  /// Карточка, которой опознано слово (null — слова нет в словаре).
  final String? cardId;

  const AnalyzedToken({
    required this.surface,
    required this.lemma,
    required this.pos,
    required this.status,
    required this.start,
    required this.end,
    required this.sentence,
    this.cardId,
  });

  /// Слово, а не число и не значок.
  bool get isWord => status != WordStatus.ignored;
}

/// Предложение текста с границами.
class AnalyzedSentence {
  /// Текст без обрамляющих пробелов.
  final String text;

  /// Границы в исходном тексте (включая пробелы перед предложением).
  final int start;
  final int end;

  const AnalyzedSentence({
    required this.text,
    required this.start,
    required this.end,
  });
}

/// Результат разбора куска текста: слова с их статусом, предложения, покрытие.
///
/// От [BookAnalysis] отличается тем, что держит ПОЗИЦИИ и порядок: книга
/// считается частотами, а короткий текст читают целиком, подсвечивая слова на
/// своих местах.
class TextAnalysis {
  final List<AnalyzedToken> tokens;
  final List<AnalyzedSentence> sentences;

  /// Уникальные незнакомые слова в порядке появления (нижний регистр).
  final List<String> unknownWords;

  const TextAnalysis({
    required this.tokens,
    required this.sentences,
    required this.unknownWords,
  });

  static const TextAnalysis empty =
      TextAnalysis(tokens: [], sentences: [], unknownWords: []);

  /// Всего слов (без чисел и значков), с повторами.
  int get totalWords => tokens.where((t) => t.isWord).length;

  int countOf(WordStatus s) => tokens.where((t) => t.status == s).length;

  /// Слов, которые человек уверенно помнит.
  int get knownCount => countOf(WordStatus.known);

  /// Слов, которые уже в словаре, но ещё не улеглись.
  int get learningCount => countOf(WordStatus.learning);

  /// Слов, которых в словаре нет.
  int get unknownCount => countOf(WordStatus.unknown);

  /// Знакомых слов (есть карточка), с повторами.
  int get knownTokens => knownCount + learningCount;

  /// Доля знакомых слов (0..1) — тот же смысл, что покрытие книги.
  double get coverage => totalWords == 0 ? 0 : knownTokens / totalWords;

  /// Предложение, в котором стоит [token].
  String sentenceOf(AnalyzedToken token) =>
      token.sentence < sentences.length ? sentences[token.sentence].text : '';
}

/// Разбор произвольного текста: предложения, слова, статус по личному словарю.
class TextParse {
  const TextParse._();

  // Слово: буквы/цифры, внутри допустимы апостроф и дефис (don't, well-known,
  // aujourd'hui). Позиции матчей и есть позиции слов в тексте.
  static final RegExp _word = RegExp(
    r"[\p{L}\p{N}]+(?:['’\-][\p{L}\p{N}]+)*",
    unicode: true,
  );
  static final RegExp _letter = RegExp(r'\p{L}', unicode: true);

  static const String _terminators = '.!?…';
  static const String _closers = '"»”\'’)]';

  // Сокращения, после которых точка НЕ заканчивает предложение: за титулом
  // всегда идёт имя с заглавной, и без списка каждый «Mr. Smith» рвался надвое.
  static const Set<String> _abbrev = {
    'mr', 'mrs', 'ms', 'dr', 'prof', 'st', 'sr', 'jr', 'vs', 'etc', 'inc',
    'ltd', 'fig', 'ср', 'см', 'напр', 'проф', 'акад', 'тов', 'гр', 'им',
  };

  /// Порог вероятности вспомнить, выше которого слово считается знакомым
  /// уверенно (тот же, что в разборе книги).
  static const double _strongRetention = 0.9;

  /// Делит текст на предложения. Перевод строки — жёсткая граница; точка внутри
  /// числа, после титула и после инициала предложение не заканчивает.
  static List<AnalyzedSentence> sentences(String text) {
    final out = <AnalyzedSentence>[];
    var start = 0;
    var i = 0;
    while (i < text.length) {
      final ch = text[i];
      if (ch == '\n') {
        _push(out, text, start, i);
        i++;
        start = i;
        continue;
      }
      if (_terminators.contains(ch)) {
        var j = i;
        while (j < text.length && _terminators.contains(text[j])) {
          j++;
        }
        var k = j;
        while (k < text.length && _closers.contains(text[k])) {
          k++;
        }
        if (_isBoundary(text, i, k)) {
          _push(out, text, start, k);
          start = k;
          i = k;
          continue;
        }
        i = j;
        continue;
      }
      i++;
    }
    _push(out, text, start, text.length);
    return out;
  }

  static void _push(
      List<AnalyzedSentence> out, String text, int start, int end) {
    if (end <= start) return;
    final raw = text.substring(start, end);
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return;
    out.add(AnalyzedSentence(text: trimmed, start: start, end: end));
  }

  /// Заканчивается ли предложение точкой на позиции [dot] (закрывающие кавычки
  /// уже пройдены до [after]).
  static bool _isBoundary(String text, int dot, int after) {
    // Дальше только пробелы — текст кончился.
    final rest = text.substring(after);
    if (rest.trim().isEmpty) return true;
    // «3.5»: за точкой сразу цифра или буква — это не конец, а часть слова.
    if (after < text.length && !_isSpace(text[after])) return false;
    // Следующее предложение начинается с заглавной буквы или кавычки.
    final next = rest.trimLeft();
    final first = next[0];
    if (_letter.hasMatch(first) && first.toLowerCase() == first) return false;

    // Слово перед точкой.
    var s = dot;
    while (s > 0 && _isWordChar(text[s - 1])) {
      s--;
    }
    final prev = text.substring(s, dot);
    if (prev.isEmpty) return true;
    if (_abbrev.contains(prev.toLowerCase())) return false;
    // Инициал: одна ЗАГЛАВНАЯ буква («J. R. Brown»). Строчная одиночная — это
    // хвост сокращения вроде «p.m.», и оно предложение заканчивает.
    if (prev.length == 1 &&
        _letter.hasMatch(prev) &&
        prev.toUpperCase() == prev) {
      return false;
    }
    return true;
  }

  static bool _isSpace(String c) => c.trim().isEmpty;

  static bool _isWordChar(String c) =>
      _letter.hasMatch(c) || RegExp(r'\p{N}', unicode: true).hasMatch(c);

  /// Полный разбор [text] для изучаемого языка [languageCode].
  static TextAnalysis analyze(String text, String languageCode) {
    if (text.trim().isEmpty) return TextAnalysis.empty;
    final sents = sentences(text);
    final cards = _cardsByStem(languageCode);
    final now = DateTime.now();

    final tokens = <AnalyzedToken>[];
    final unknown = <String>[];
    final seenUnknown = <String>{};
    var si = 0;

    for (final m in _word.allMatches(text)) {
      final surface = m.group(0)!;
      while (si + 1 < sents.length && m.start >= sents[si].end) {
        si++;
      }
      if (!_letter.hasMatch(surface)) {
        tokens.add(AnalyzedToken(
          surface: surface,
          lemma: surface,
          pos: '',
          status: WordStatus.ignored,
          start: m.start,
          end: m.end,
          sentence: si,
        ));
        continue;
      }
      final lower = surface.toLowerCase();
      final lemma = Lemmatizer.stem(lower, languageCode);
      final card = cards[lemma] ?? cards[lower];
      final status = card == null
          ? WordStatus.unknown
          : (_strong(card, now) ? WordStatus.known : WordStatus.learning);
      if (status == WordStatus.unknown && seenUnknown.add(lower)) {
        unknown.add(lower);
      }
      tokens.add(AnalyzedToken(
        surface: surface,
        lemma: lemma,
        pos: card != null && card.pos.isNotEmpty
            ? card.pos
            : PosDetect.detect(lower, languageCode: languageCode),
        status: status,
        start: m.start,
        end: m.end,
        sentence: si,
        cardId: card?.id,
      ));
    }

    return TextAnalysis(
      tokens: tokens,
      sentences: sents,
      unknownWords: unknown,
    );
  }

  /// Карточки языка, разложенные по основе слова (как в разборе книги: при
  /// совпадении побеждает та, у которой память крепче).
  static Map<String, WordCard> _cardsByStem(String languageCode) {
    final byFront =
        DeckRepository.instance.cardsByFrontForLanguage(languageCode);
    final out = <String, WordCard>{};
    byFront.forEach((front, card) {
      final stem = Lemmatizer.stem(front, languageCode);
      final existing = out[stem];
      if (existing == null ||
          card.review.stability > existing.review.stability) {
        out[stem] = card;
      }
    });
    return out;
  }

  static bool _strong(WordCard card, DateTime now) {
    final r = card.review;
    if (r.state != FsrsState.review || r.lastReview == null) return false;
    final elapsed =
        math.max(0.0, now.difference(r.lastReview!).inSeconds / 86400.0);
    return Fsrs.instance.retrievability(elapsed, r.stability) >=
        _strongRetention;
  }
}
