/// Лёгкая лемматизация для СВЕРКИ словоформ (не для показа): приводим слово к
/// основе, чтобы «running»/«runs» засчитывались как «run», а «foxes» как «fox».
///
/// Это не полноценный морфоанализ, а компактный набор правил. Главное свойство —
/// ДЕТЕРМИНИЗМ: и слово из книги, и «перёд» карточки проходят через одну и ту же
/// [stem], поэтому совпадают по одному ключу. Уверенно поддержаны английский и
/// (скромно) русский — остальные языки возвращаются как есть (без ложных
/// срабатываний). Направление правил «безопасное»: скорее не засчитаем форму,
/// чем ошибочно пометим чужое слово знакомым.
class Lemmatizer {
  const Lemmatizer._();

  /// Основа слова [word] для языка [lang] (код вроде 'en', 'ru').
  static String stem(String word, String lang) {
    final w = word.toLowerCase();
    switch (lang) {
      case 'en':
        return _en(w);
      case 'ru':
      case 'uk':
        return _ru(w);
      default:
        return w;
    }
  }

  // ------------------------------- Английский -------------------------------

  static String _en(String w) {
    if (w.length <= 3) return w;
    var s = w;

    // Притяжательное 's / ’s.
    if (s.endsWith("'s") || s.endsWith('’s')) {
      s = s.substring(0, s.length - 2);
    }

    // Множественное / 3-е лицо.
    if (s.endsWith('ies') && s.length > 4) {
      s = '${s.substring(0, s.length - 3)}y'; // flies→fly, studies→study
    } else if (s.endsWith('es') &&
        s.length > 4 &&
        _endsBeforeEs(s)) {
      s = s.substring(0, s.length - 2); // boxes→box, wishes→wish, goes→go
    } else if (s.endsWith('s') && !s.endsWith('ss') && s.length > 3) {
      s = s.substring(0, s.length - 1); // cats→cat, runs→run (class→class)
    }

    // Глагольные -ing / -ed (после снятия множественного).
    if (s.endsWith('ing') && s.length > 5) {
      s = s.substring(0, s.length - 3); // running→runn, reading→read
      s = _undouble(s);
    } else if (s.endsWith('ed') && s.length > 4) {
      s = s.substring(0, s.length - 2); // walked→walk, jumped→jump
      s = _undouble(s);
    }

    return s;
  }

  // Буква перед "es", при которой окончание точно множественное: s,x,z,ch,sh,o.
  static bool _endsBeforeEs(String s) {
    final base = s.substring(0, s.length - 2);
    if (base.isEmpty) return false;
    if (base.endsWith('ch') || base.endsWith('sh')) return true;
    final c = base[base.length - 1];
    return c == 's' || c == 'x' || c == 'z' || c == 'o';
  }

  // Снимает удвоенную согласную на конце (runn→run, stopp→stop).
  static String _undouble(String s) {
    if (s.length >= 3) {
      final a = s[s.length - 1];
      final b = s[s.length - 2];
      if (a == b && !_isVowel(a)) return s.substring(0, s.length - 1);
    }
    return s;
  }

  static bool _isVowel(String c) => 'aeiou'.contains(c);

  // ------------------------------- Русский -------------------------------

  // Частые окончания (от длинных к коротким) — снимаем самое длинное.
  static const List<String> _ruEndings = [
    'ами', 'ями', 'ого', 'его', 'ому', 'ему', 'ыми', 'ими', 'ах', 'ях',
    'ов', 'ев', 'ей', 'ой', 'ий', 'ый', 'ая', 'яя', 'ое', 'ее', 'ые', 'ие',
    'ам', 'ям', 'ум', 'ю', 'я', 'а', 'е', 'о', 'у', 'ы', 'и', 'й', 'ь',
  ];

  static String _ru(String w) {
    if (w.length <= 3) return w;
    for (final e in _ruEndings) {
      if (w.endsWith(e) && w.length - e.length >= 3) {
        return w.substring(0, w.length - e.length);
      }
    }
    return w;
  }
}
