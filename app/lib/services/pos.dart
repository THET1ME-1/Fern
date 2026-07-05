/// Определение части речи (part of speech) слова.
///
/// Каноничные коды: noun/verb/adj/adv/pronoun/article/prep/conj/num/particle/
/// interj. Используется, чтобы:
///  * отрезать вклеенную в слово метку при импорте («the артикль» → «the»);
///  * подхватывать часть речи из словаря при добавлении слова;
///  * раскладывать колоду по отдельным колодам под каждый тип.
class PosDetect {
  const PosDetect._();

  /// Порядок для показа/создания колод (частотные типы выше).
  static const List<String> order = [
    'noun', 'verb', 'adj', 'adv', 'pronoun', 'article',
    'prep', 'conj', 'num', 'particle', 'interj',
  ];

  /// Свой цвет (ARGB) каждой части речи — для тега на карточке и обложек колод.
  static const Map<String, int> colors = {
    'noun': 0xFF2E7D5B,
    'verb': 0xFFB5622E,
    'adj': 0xFF3F6FB0,
    'adv': 0xFF7A5AA8,
    'pronoun': 0xFF2E9E6B,
    'article': 0xFF8A8A85,
    'prep': 0xFFC28A2B,
    'conj': 0xFF6B8E23,
    'num': 0xFF4F7A34,
    'particle': 0xFFA0522D,
    'interj': 0xFFCB4E6B,
  };

  static int colorOf(String code) => colors[code] ?? 0xFF2E7D5B;

  // Слово-метка (нижний регистр, без пунктуации) → код. RU + EN + сокращения.
  static const Map<String, String> _labels = {
    // существительное
    'существительное': 'noun', 'сущ': 'noun', 'noun': 'noun',
    // глагол
    'глагол': 'verb', 'гл': 'verb', 'verb': 'verb',
    // прилагательное
    'прилагательное': 'adj', 'прил': 'adj', 'adjective': 'adj', 'adj': 'adj',
    // наречие
    'наречие': 'adv', 'нареч': 'adv', 'adverb': 'adv', 'adv': 'adv',
    // местоимение
    'местоимение': 'pronoun', 'мест': 'pronoun', 'pronoun': 'pronoun',
    'pron': 'pronoun',
    // артикль / определитель
    'артикль': 'article', 'article': 'article', 'determiner': 'article',
    'det': 'article',
    // предлог
    'предлог': 'prep', 'preposition': 'prep', 'prep': 'prep',
    // союз
    'союз': 'conj', 'conjunction': 'conj', 'conj': 'conj',
    // числительное
    'числительное': 'num', 'числ': 'num', 'numeral': 'num', 'number': 'num',
    'num': 'num',
    // частица
    'частица': 'particle', 'particle': 'particle',
    // междометие
    'междометие': 'interj', 'межд': 'interj', 'interjection': 'interj',
    'interj': 'interj', 'exclamation': 'interj',
  };

  static final RegExp _punct = RegExp(r'^[^\p{L}\p{N}]+|[^\p{L}\p{N}]+$', unicode: true);

  /// Код по слову-метке (или null).
  static String? fromLabel(String word) =>
      _labels[word.replaceAll(_punct, '').toLowerCase()];

  /// Отрезает вклеенную в конце переда метку части речи:
  /// «the артикль» → ('the', 'article'); «have глагол» → ('have', 'verb').
  /// Если метки нет — возвращает исходный перёд и null.
  static (String, String?) strip(String front) {
    final tokens = front.trim().split(RegExp(r'\s+'));
    if (tokens.length >= 2) {
      final code = fromLabel(tokens.last);
      if (code != null) {
        return (tokens.sublist(0, tokens.length - 1).join(' '), code);
      }
    }
    return (front, null);
  }

  /// Код из строки части речи, которую вернул словарь (напр. «noun»,
  /// «имя существительное», «гл.»). Ищем по вхождению ключевого слова.
  static String? fromDictionary(String? dictPos) {
    if (dictPos == null || dictPos.trim().isEmpty) return null;
    final s = dictPos.toLowerCase();
    for (final entry in _labels.entries) {
      if (entry.key.length >= 3 && s.contains(entry.key)) return entry.value;
    }
    return null;
  }

  // Частые английские служебные слова (их часть речи очевидна без словаря).
  static const Map<String, String> _enFunction = {
    // артикли
    'a': 'article', 'an': 'article', 'the': 'article',
    // местоимения
    'i': 'pronoun', 'you': 'pronoun', 'he': 'pronoun', 'she': 'pronoun',
    'it': 'pronoun', 'we': 'pronoun', 'they': 'pronoun', 'me': 'pronoun',
    'him': 'pronoun', 'her': 'pronoun', 'us': 'pronoun', 'them': 'pronoun',
    'my': 'pronoun', 'your': 'pronoun', 'his': 'pronoun', 'its': 'pronoun',
    'our': 'pronoun', 'their': 'pronoun', 'this': 'pronoun', 'that': 'pronoun',
    'these': 'pronoun', 'those': 'pronoun', 'who': 'pronoun', 'whom': 'pronoun',
    'whose': 'pronoun', 'which': 'pronoun', 'what': 'pronoun',
    // предлоги
    'of': 'prep', 'to': 'prep', 'in': 'prep', 'on': 'prep', 'at': 'prep',
    'by': 'prep', 'for': 'prep', 'with': 'prep', 'from': 'prep', 'into': 'prep',
    'onto': 'prep', 'over': 'prep', 'under': 'prep', 'about': 'prep',
    'between': 'prep', 'through': 'prep', 'during': 'prep', 'before': 'prep',
    'after': 'prep', 'above': 'prep', 'below': 'prep', 'without': 'prep',
    // союзы
    'and': 'conj', 'or': 'conj', 'but': 'conj', 'so': 'conj', 'because': 'conj',
    'if': 'conj', 'while': 'conj', 'although': 'conj', 'though': 'conj',
    'since': 'conj', 'unless': 'conj', 'nor': 'conj', 'yet': 'conj',
  };

  /// Итоговая часть речи: сперва уже известная [existing], затем словарь
  /// [dictPos], затем эвристика английских служебных слов; иначе '' (неизвестно).
  static String detect(
    String front, {
    String? existing,
    String? dictPos,
    String languageCode = 'en',
  }) {
    if (existing != null && existing.isNotEmpty) return existing;
    final d = fromDictionary(dictPos);
    if (d != null) return d;
    if (languageCode == 'en') {
      final e = _enFunction[front.trim().toLowerCase()];
      if (e != null) return e;
    }
    return '';
  }
}
