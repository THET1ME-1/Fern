import 'dart:math' as math;

/// Кандидат в список «учить в первую очередь».
class WordCandidate {
  /// Слово в нижнем регистре.
  final String word;

  /// Сколько раз встретилось в тексте.
  final int count;

  /// Из них — сколько раз с заглавной буквы. Отличает имя собственное от
  /// обычного слова, которому просто случалось открывать предложение.
  final int capitalized;

  const WordCandidate({
    required this.word,
    required this.count,
    this.capitalized = 0,
  });
}

/// Что из текста стоит учить в первую очередь.
///
/// Раньше список строился по голой частоте, и первыми шли `the`, `of`, `to`,
/// `a` — слова, которые знает любой, кто вообще открыл английскую книгу. Здесь
/// отсеиваются служебные слова и имена собственные, а остальное ранжируется по
/// пользе: частота важна, но редкое длинное слово полезнее частого короткого.
class WordPriority {
  WordPriority._();

  /// Служебные слова: артикли, предлоги, союзы, местоимения, связки,
  /// вспомогательные глаголы. Их не учат карточками — они приходят сами с
  /// первым же учебником.
  static const Map<String, Set<String>> _functionWords = {
    'en': {
      'a', 'an', 'the', 'and', 'or', 'but', 'if', 'then', 'than',
      'so', 'because', 'as', 'while', 'that', 'this', 'these', 'those', 'there',
      'here', 'what', 'which', 'who', 'whom', 'whose', 'when', 'where', 'why',
      'how', 'i', 'you', 'he', 'she', 'it', 'we', 'they', 'me',
      'him', 'her', 'us', 'them', 'my', 'your', 'his', 'its', 'our',
      'their', 'mine', 'yours', 'hers', 'ours', 'theirs', 'myself', 'yourself', 'himself',
      'herself', 'itself', 'ourselves', 'themselves', 'be', 'am', 'is', 'are', 'was',
      'were', 'been', 'being', 'have', 'has', 'had', 'having', 'do', 'does',
      'did', 'doing', 'will', 'would', 'shall', 'should', 'can', 'could', 'may',
      'might', 'must', 'not', 'no', 'nor', 'yes', 'of', 'to', 'in',
      'on', 'at', 'by', 'for', 'with', 'about', 'against', 'between', 'into',
      'through', 'during', 'before', 'after', 'above', 'below', 'from', 'up', 'down',
      'out', 'off', 'over', 'under', 'again', 'further', 'once', 'all', 'any',
      'both', 'each', 'few', 'more', 'most', 'other', 'some', 'such', 'only',
      'own', 'same', 'too', 'very', 'just', 'now', 'also', 'even', 'still',
      'yet', 'ever', 'never', 'always', 'often', 'one', 'two', 'three', 'first',
      'last', 'said', 'says', 'say',
    },
    'ru': {
      'и', 'в', 'во', 'не', 'что', 'он', 'она', 'оно', 'они',
      'на', 'я', 'с', 'со', 'как', 'а', 'то', 'все', 'всё',
      'так', 'его', 'но', 'да', 'ты', 'к', 'у', 'же', 'вы',
      'за', 'бы', 'по', 'только', 'ее', 'её', 'мне', 'было', 'вот',
      'от', 'меня', 'еще', 'ещё', 'нет', 'о', 'из', 'ему', 'теперь',
      'когда', 'даже', 'ну', 'вдруг', 'ли', 'если', 'уже', 'или', 'ни',
      'быть', 'был', 'него', 'до', 'вас', 'нибудь', 'опять', 'уж', 'вам',
      'ведь', 'там', 'потом', 'себя', 'ничего', 'ей', 'может', 'тут', 'где',
      'есть', 'надо', 'ней', 'для', 'мы', 'тебя', 'их', 'чем', 'была',
      'сам', 'чтоб', 'без', 'будто', 'человек', 'чего', 'раз', 'тоже', 'себе',
      'под', 'жизнь', 'будет', 'ж', 'кто', 'этот', 'того', 'потому', 'этого',
      'какой', 'совсем', 'ним', 'здесь', 'этом', 'один', 'почти', 'мой', 'тем',
      'чтобы', 'нее', 'неё', 'были', 'куда', 'зачем', 'всех', 'никогда', 'можно',
      'при', 'наконец', 'два', 'об', 'другой', 'хоть', 'после', 'над', 'больше',
      'тот', 'через', 'эти', 'нас', 'про', 'всего', 'них', 'какая', 'много',
      'разве', 'сказал', 'три', 'эту', 'моя', 'впрочем', 'хорошо', 'свою', 'этой',
      'перед', 'иногда', 'лучше', 'чуть', 'том', 'нельзя', 'такой', 'им', 'более',
      'всегда', 'конечно', 'всю', 'между',
    },
    'uk': {
      'і', 'й', 'в', 'у', 'не', 'що', 'він', 'вона', 'вони',
      'на', 'я', 'з', 'як', 'а', 'то', 'все', 'так', 'його',
      'але', 'та', 'ти', 'до', 'же', 'ви', 'за', 'би', 'по',
      'тільки', 'її', 'мені', 'було', 'от', 'мене', 'ще', 'ні', 'о',
      'із', 'йому', 'тепер', 'коли', 'навіть', 'ну', 'чи', 'якщо', 'вже',
      'або', 'бути', 'був', 'нього', 'вас', 'знову', 'вам', 'адже', 'там',
      'потім', 'себе', 'нічого', 'їй', 'може', 'тут', 'де', 'є', 'треба',
      'для', 'ми', 'тебе', 'їх', 'ніж', 'була', 'сам', 'без', 'чого',
      'раз', 'теж', 'собі', 'під', 'буде', 'хто', 'цей', 'того', 'тому',
      'цього', 'який', 'зовсім', 'цьому', 'один', 'майже', 'мій', 'тим', 'щоб',
      'були', 'куди', 'навіщо', 'всіх', 'ніколи', 'можна', 'при', 'нарешті', 'два',
      'про', 'інший', 'хоч', 'після', 'над', 'більше', 'той', 'через', 'ці',
      'нас', 'всього', 'них', 'яка', 'багато',
    },
    'de': {
      'der', 'die', 'das', 'den', 'dem', 'des', 'ein', 'eine', 'einen',
      'einem', 'einer', 'eines', 'und', 'oder', 'aber', 'wenn', 'dann', 'als',
      'weil', 'dass', 'ob', 'wie', 'wo', 'wer', 'was', 'warum', 'ich',
      'du', 'er', 'sie', 'es', 'wir', 'ihr', 'mich', 'dich', 'sich',
      'uns', 'mein', 'dein', 'sein', 'unser', 'euer', 'ihre', 'bin', 'bist',
      'ist', 'sind', 'seid', 'war', 'waren', 'habe', 'hast', 'hat', 'haben',
      'hatte', 'hatten', 'werde', 'wird', 'werden', 'wurde', 'wurden', 'kann', 'kannst',
      'können', 'muss', 'müssen', 'soll', 'sollen', 'will', 'wollen', 'nicht', 'kein',
      'keine', 'ja', 'nein', 'von', 'zu', 'in', 'im', 'an', 'am',
      'auf', 'bei', 'mit', 'nach', 'aus', 'über', 'unter', 'vor', 'für',
      'ohne', 'um', 'durch', 'gegen', 'noch', 'schon', 'nur', 'auch', 'sehr',
      'mehr', 'immer', 'nie', 'hier', 'dort', 'jetzt', 'so', 'man',
    },
    'fr': {
      'le', 'la', 'les', 'un', 'une', 'des', 'du', 'de', 'et',
      'ou', 'mais', 'si', 'que', 'qui', 'quoi', 'dont', 'où', 'comment',
      'pourquoi', 'je', 'tu', 'il', 'elle', 'nous', 'vous', 'ils', 'elles',
      'me', 'te', 'se', 'lui', 'leur', 'mon', 'ton', 'son', 'notre',
      'votre', 'ce', 'cet', 'cette', 'ces', 'suis', 'es', 'est', 'sommes',
      'êtes', 'sont', 'était', 'étaient', 'être', 'ai', 'as', 'avons', 'avez',
      'ont', 'avait', 'avoir', 'fait', 'faire', 'pas', 'ne', 'non', 'oui',
      'à', 'au', 'aux', 'en', 'dans', 'sur', 'sous', 'pour', 'par',
      'avec', 'sans', 'chez', 'vers', 'entre', 'plus', 'moins', 'très', 'bien',
      'aussi', 'encore', 'déjà', 'toujours', 'jamais', 'ici', 'là', 'y', 'tout',
      'tous', 'toute',
    },
    'es': {
      'el', 'la', 'los', 'las', 'un', 'una', 'unos', 'unas', 'de',
      'del', 'y', 'o', 'pero', 'si', 'que', 'quien', 'como', 'donde',
      'cuando', 'porque', 'yo', 'tú', 'él', 'ella', 'nosotros', 'vosotros', 'ellos',
      'me', 'te', 'se', 'nos', 'le', 'les', 'lo', 'mi', 'tu',
      'su', 'nuestro', 'este', 'esta', 'estos', 'ese', 'esa', 'soy', 'eres',
      'es', 'somos', 'son', 'era', 'eran', 'ser', 'estar', 'está', 'están',
      'he', 'has', 'ha', 'hemos', 'han', 'había', 'haber', 'no', 'sí',
      'a', 'al', 'en', 'con', 'sin', 'por', 'para', 'sobre', 'entre',
      'hasta', 'desde', 'más', 'menos', 'muy', 'también', 'ya', 'siempre', 'nunca',
      'aquí', 'allí', 'todo', 'todos', 'nada', 'algo',
    },
    'it': {
      'il', 'lo', 'la', 'i', 'gli', 'le', 'un', 'uno', 'una',
      'di', 'del', 'della', 'e', 'o', 'ma', 'se', 'che', 'chi',
      'come', 'dove', 'quando', 'perché', 'io', 'tu', 'lui', 'lei', 'noi',
      'voi', 'loro', 'mi', 'ti', 'si', 'ci', 'vi', 'mio', 'tuo',
      'suo', 'nostro', 'questo', 'questa', 'quello', 'sono', 'sei', 'è', 'siamo',
      'siete', 'era', 'erano', 'essere', 'ho', 'hai', 'ha', 'abbiamo', 'avete',
      'hanno', 'aveva', 'avere', 'non', 'sì', 'a', 'al', 'in', 'nel',
      'con', 'senza', 'per', 'su', 'tra', 'fra', 'da', 'più', 'meno',
      'molto', 'anche', 'già', 'sempre', 'mai', 'qui', 'lì', 'tutto', 'tutti',
      'niente',
    },
    'pt': {
      'o', 'a', 'os', 'as', 'um', 'uma', 'uns', 'umas', 'de',
      'do', 'da', 'dos', 'das', 'e', 'ou', 'mas', 'se', 'que',
      'quem', 'como', 'onde', 'quando', 'porque', 'eu', 'tu', 'ele', 'ela',
      'nós', 'vós', 'eles', 'me', 'te', 'nos', 'lhe', 'lhes', 'meu',
      'teu', 'seu', 'nosso', 'este', 'esta', 'esse', 'essa', 'aquele', 'sou',
      'és', 'é', 'somos', 'são', 'era', 'eram', 'ser', 'estar', 'está',
      'estão', 'tenho', 'tem', 'temos', 'têm', 'tinha', 'ter', 'não', 'sim',
      'ao', 'em', 'no', 'na', 'com', 'sem', 'por', 'para', 'sobre',
      'entre', 'até', 'desde', 'mais', 'menos', 'muito', 'também', 'já', 'sempre',
      'nunca', 'aqui', 'ali', 'tudo', 'todos', 'nada',
    },
  };

  /// Служебное ли слово: его в карточки не берём.
  ///
  /// Для языка без списка работает запасное правило — очень короткие слова
  /// почти всегда служебные, а учить их всё равно не из чего.
  static bool isFunctionWord(String word, String languageCode) {
    final w = word.toLowerCase();
    final list = _functionWords[languageCode];
    if (list != null) return list.contains(w);
    return w.length <= 2;
  }

  /// Похоже ли на имя собственное: почти всегда пишется с заглавной.
  ///
  /// Порог не сто процентов: имя может попасть в цитату капсом или в начало
  /// строки со сбитой вёрсткой, а обычному слову случается открывать предложение.
  static bool looksProper({required int capitalized, required int total}) {
    if (total < 3) return false;
    return capitalized / total >= 0.9;
  }

  /// Насколько слово стоит того, чтобы занять место в списке.
  ///
  /// Частота идёт логарифмом: между словом на 4000 вхождений и словом на 400
  /// разница есть, но не десятикратная — читателю всё равно встретятся оба.
  /// Длина работает множителем: длинное слово почти всегда содержательное и
  /// редко угадывается по контексту.
  static double score(String word, int count) {
    if (count <= 0) return 0;
    // Единичное вхождение — чаще всего опечатка или мусор распознавания.
    final rarityPenalty = count == 1 ? 0.35 : 1.0;
    final freq = math.log(count + 1) / math.ln2;
    final len = word.characters;
    final lengthWeight = switch (len) {
      <= 3 => 0.25,
      4 => 0.6,
      5 || 6 => 1.0,
      7 || 8 || 9 => 1.45,
      _ => 1.8,
    };
    return freq * lengthWeight * rarityPenalty;
  }

  /// Отбирает и упорядочивает слова для списка «учить в первую очередь».
  ///
  /// Первыми идут самые полезные по [score]. Отдельно в список подмешиваются
  /// самые длинные слова текста: даже редкое `psychohistory` для читателя
  /// важнее ещё одного глагола средней частоты.
  static List<WordCandidate> pick(
    List<WordCandidate> candidates,
    String languageCode, {
    int limit = 60,
  }) {
    final worthy = [
      for (final c in candidates)
        if (!isFunctionWord(c.word, languageCode) &&
            c.word.characters > 2 &&
            !looksProper(capitalized: c.capitalized, total: c.count))
          c,
    ];
    if (worthy.isEmpty) return const [];

    worthy.sort((a, b) {
      final byScore = score(b.word, b.count).compareTo(score(a.word, a.count));
      if (byScore != 0) return byScore;
      return b.count.compareTo(a.count);
    });

    // Четверть мест отдаётся самым длинным словам, если они не прошли по
    // общему счёту: список должен предлагать и настоящий вызов, а не только
    // крепких середняков.
    final hardQuota = math.max(1, limit ~/ 4);
    final head = worthy.take(limit).toList();
    final chosen = {for (final c in head) c.word};
    final longTail = worthy
        .where((c) => !chosen.contains(c.word) && c.word.characters >= 8)
        .toList()
      ..sort((a, b) {
        final byLen = b.word.characters.compareTo(a.word.characters);
        return byLen != 0 ? byLen : b.count.compareTo(a.count);
      });

    if (longTail.isEmpty || head.length < limit) {
      return head.take(limit).toList();
    }
    final keep = head.take(limit - math.min(hardQuota, longTail.length));
    return [...keep, ...longTail.take(hardQuota)];
  }
}

extension on String {
  /// Длина в символах, а не в кодовых единицах: для кириллицы и диакритики
  /// `length` считает то же самое, но для суррогатных пар — нет.
  int get characters => runes.length;
}
