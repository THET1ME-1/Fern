import 'en_irregular.dart';
import 'en_verbs.dart';
import 'text_analysis.dart';

/// Найденная в тексте грамматическая конструкция.
class ConstructionHit {
  /// Код правила (`present_perfect`, `passive_past`, …). Описание к коду даёт
  /// [ConstructionCatalog]: детектор работает без ассетов, поэтому его можно
  /// гонять в обычном тесте и в фоновом изоляте.
  final String code;

  /// Индекс предложения в [TextAnalysis.sentences].
  final int sentence;

  /// Границы найденного оборота в исходном тексте.
  final int start;
  final int end;

  /// Сам оборот («have been waiting»).
  final String snippet;

  const ConstructionHit({
    required this.code,
    required this.sentence,
    required this.start,
    required this.end,
    required this.snippet,
  });
}

/// Поиск грамматических конструкций в разобранном тексте.
///
/// Смысл фичи: правило языка человек видит на СВОЁМ предложении, а не в
/// учебнике. Поэтому детектор возвращает границы оборота — экран подсвечивает
/// его прямо в тексте, а карточка правила берёт это предложение примером.
///
/// Пока разбирается английский. Для остальных языков честно возвращается
/// пустой список: набор шаблонов у каждого языка свой, и выдумывать его по
/// аналогии значит показывать человеку неверный разбор.
class Constructions {
  const Constructions._();

  static bool supports(String languageCode) =>
      languageCode.split('-').first.toLowerCase() == 'en';

  static final Set<String> _pastForms = {
    for (final e in kEnIrregular.entries) e.value.$1,
  };
  static final Set<String> _participles = {
    for (final e in kEnIrregular.entries) e.value.$2,
  };

  /// Форма на -ing (waiting, building).
  static bool isIng(String w) => w.length > 4 && w.endsWith('ing');

  /// Третья форма: неправильная из списка или правильная на -ed.
  static bool isParticiple(String w) =>
      _participles.contains(w) || (w.length > 3 && w.endsWith('ed'));

  /// Вторая форма (прошедшее время).
  static bool isPast(String w) =>
      _pastForms.contains(w) || (w.length > 3 && w.endsWith('ed'));

  /// Начальная форма: не -ing, не третья форма и не вспомогательный.
  static bool isBase(String w) =>
      w.length > 1 &&
      !isIng(w) &&
      !w.endsWith('ed') &&
      !_participles.contains(w) &&
      !_pastForms.contains(w) &&
      !EnVerbs.auxiliaries.contains(w) &&
      w != 'to' &&
      w != 'not';

  /// Все конструкции текста, по порядку появления.
  static List<ConstructionHit> find(TextAnalysis a, String languageCode) {
    if (!supports(languageCode)) return const [];
    final out = <ConstructionHit>[];
    final bySentence = <int, List<AnalyzedToken>>{};
    for (final t in a.tokens) {
      if (t.isWord) bySentence.putIfAbsent(t.sentence, () => []).add(t);
    }
    bySentence.forEach((si, tokens) {
      out.addAll(_inSentence(si, tokens, a));
    });
    out.sort((x, y) => x.start.compareTo(y.start));
    return out;
  }

  static List<ConstructionHit> _inSentence(
    int sentenceIndex,
    List<AnalyzedToken> tokens,
    TextAnalysis a,
  ) {
    final words = [for (final t in tokens) t.surface.toLowerCase()];
    final taken = List<bool>.filled(tokens.length, false);
    final hits = <ConstructionHit>[];

    void add(String code, int from, int to) {
      for (var i = from; i <= to; i++) {
        if (taken[i]) return;
      }
      for (var i = from; i <= to; i++) {
        taken[i] = true;
      }
      final start = tokens[from].start;
      final end = tokens[to].end;
      hits.add(ConstructionHit(
        code: code,
        sentence: sentenceIndex,
        start: start,
        end: end,
        // Подстрока исходного текста, а не склейка слов: оборот показывается
        // человеку как он написан, вместе с запятыми и апострофами.
        snippet: a.text.substring(start, end),
      ));
    }

    // Условные предложения смотрят на всё предложение целиком и не занимают
    // токены: внутри «If I had known, I would have told you» живут ещё и
    // перфекты, и человеку полезно видеть оба слоя.
    final conditional = _conditional(words);
    if (conditional != null) {
      hits.add(ConstructionHit(
        code: conditional,
        sentence: sentenceIndex,
        start: tokens.first.start,
        end: tokens.last.end,
        snippet: a.text.substring(tokens.first.start, tokens.last.end),
      ));
    }

    for (final rule in _rules) {
      for (var i = 0; i + rule.length <= words.length; i++) {
        if (rule.match(words, i)) add(rule.code, i, i + rule.length - 1);
      }
    }
    return hits;
  }

  /// Тип условного предложения или null.
  static String? _conditional(List<String> w) {
    if (!w.contains('if')) return null;
    final hasWould = w.contains('would') || w.contains("'d");
    final hasWill = w.contains('will') || w.contains("'ll");
    final hasHad = w.contains('had');
    if (hasWould && hasHad) return 'conditional_3';
    if (hasWould) return 'conditional_2';
    if (hasWill) return 'conditional_1';
    return null;
  }

  static final List<_Rule> _rules = [
    // Трёхсловные шаблоны идут первыми: «have been waiting» иначе разобралось
    // бы как перфект «have been» и потеряло бы продолженность.
    _Rule('present_perfect_cont', 3, (w, i) =>
        EnVerbs.havePresent.contains(w[i]) && w[i + 1] == 'been' && isIng(w[i + 2])),
    _Rule('past_perfect_cont', 3, (w, i) =>
        w[i] == 'had' && w[i + 1] == 'been' && isIng(w[i + 2])),
    _Rule('perfect_passive', 3, (w, i) =>
        EnVerbs.have.contains(w[i]) &&
        w[i + 1] == 'been' &&
        isParticiple(w[i + 2])),
    _Rule('future_cont', 3, (w, i) =>
        (w[i] == 'will' || w[i] == "'ll") && w[i + 1] == 'be' && isIng(w[i + 2])),
    _Rule('future_perfect', 3, (w, i) =>
        (w[i] == 'will' || w[i] == "'ll") &&
        w[i + 1] == 'have' &&
        isParticiple(w[i + 2])),
    _Rule('going_to', 3, (w, i) =>
        EnVerbs.be.contains(w[i]) && w[i + 1] == 'going' && w[i + 2] == 'to'),
    _Rule('modal_perfect', 3, (w, i) =>
        EnVerbs.modals.contains(w[i]) &&
        w[i + 1] == 'have' &&
        isParticiple(w[i + 2])),

    // Двухсловные.
    _Rule('present_perfect', 2, (w, i) =>
        EnVerbs.havePresent.contains(w[i]) && isParticiple(w[i + 1])),
    _Rule('past_perfect', 2, (w, i) =>
        w[i] == 'had' && isParticiple(w[i + 1])),
    _Rule('present_cont', 2, (w, i) =>
        EnVerbs.bePresent.contains(w[i]) && isIng(w[i + 1])),
    _Rule('past_cont', 2, (w, i) =>
        EnVerbs.bePast.contains(w[i]) && isIng(w[i + 1])),
    _Rule('passive_present', 2, (w, i) =>
        EnVerbs.bePresent.contains(w[i]) && isParticiple(w[i + 1])),
    _Rule('passive_past', 2, (w, i) =>
        EnVerbs.bePast.contains(w[i]) && isParticiple(w[i + 1])),
    _Rule('used_to', 2, (w, i) => w[i] == 'used' && w[i + 1] == 'to'),
    _Rule('there_is', 2, (w, i) =>
        w[i] == 'there' && EnVerbs.be.contains(w[i + 1])),
    _Rule('future_will', 2, (w, i) =>
        (w[i] == 'will' || w[i] == "'ll") && isBase(w[i + 1])),
    _Rule('modal_verb', 2, (w, i) =>
        EnVerbs.modals.contains(w[i]) &&
        w[i] != 'will' &&
        w[i] != "'ll" &&
        isBase(w[i + 1])),
    _Rule('question_aux', 2, (w, i) =>
        EnVerbs.doAux.contains(w[i]) && _isSubject(w[i + 1])),
    _Rule('comparative', 2, (w, i) =>
        w[i] == 'more' || (w[i + 1] == 'than' && w[i].endsWith('er'))),
    _Rule('superlative', 2, (w, i) =>
        (w[i] == 'the' && w[i + 1].endsWith('est') && w[i + 1].length > 4) ||
        (w[i] == 'most' && w[i + 1].length > 2)),
    _Rule('infinitive', 2, (w, i) => w[i] == 'to' && isBase(w[i + 1])),
  ];

  /// Все коды, которые детектор умеет выдавать. Каталог описаний обязан
  /// покрывать этот список: код без объяснения превращается на экране в
  /// загадочную метку, и ловится это только сверкой.
  static List<String> get knownCodes => [
        for (final r in _rules) r.code,
        'conditional_1',
        'conditional_2',
        'conditional_3',
      ];

  static const Set<String> _subjects = {
    'i', 'you', 'he', 'she', 'it', 'we', 'they', 'this', 'that', 'these',
    'those',
  };

  static bool _isSubject(String w) => _subjects.contains(w);
}

class _Rule {
  final String code;
  final int length;
  final bool Function(List<String> words, int i) match;
  const _Rule(this.code, this.length, this.match);
}

