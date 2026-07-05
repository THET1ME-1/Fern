/// Офлайн-определение языка текста книги — чтобы анализ и подсветка сверялись
/// с правильным словарём (напр. русский перевод при изучении английского не
/// давал «всё не знаю»).
///
/// Двухступенчато: сначала по алфавиту (кириллица/латиница/CJK/…), затем внутри
/// латиницы — по частоте служебных слов нескольких популярных языков. Это
/// эвристика: цель — уверенно отличать русский от английского и т.п., а не
/// идеально классифицировать все 55 языков.
class LanguageDetect {
  const LanguageDetect._();

  /// Код языка (ISO 639-1) или null, если уверенности нет.
  static String? detect(String text) {
    final sample = text.length > 20000 ? text.substring(0, 20000) : text;
    if (sample.trim().isEmpty) return null;

    var latin = 0, cyr = 0, han = 0, kana = 0, hangul = 0;
    var arabic = 0, greek = 0, hebrew = 0, devanagari = 0, thai = 0;
    var hasUk = false; // украинские буквы і ї є ґ

    for (final r in sample.runes) {
      if (r >= 0x41 && r <= 0x5A || r >= 0x61 && r <= 0x7A) {
        latin++;
      } else if (r >= 0x00C0 && r <= 0x024F) {
        latin++; // латиница с диакритикой
      } else if (r >= 0x0400 && r <= 0x04FF) {
        cyr++;
        if (r == 0x0456 || r == 0x0457 || r == 0x0454 || r == 0x0491) {
          hasUk = true;
        }
      } else if (r >= 0x4E00 && r <= 0x9FFF) {
        han++;
      } else if (r >= 0x3040 && r <= 0x30FF) {
        kana++;
      } else if (r >= 0xAC00 && r <= 0xD7A3) {
        hangul++;
      } else if (r >= 0x0600 && r <= 0x06FF) {
        arabic++;
      } else if (r >= 0x0370 && r <= 0x03FF) {
        greek++;
      } else if (r >= 0x0590 && r <= 0x05FF) {
        hebrew++;
      } else if (r >= 0x0900 && r <= 0x097F) {
        devanagari++;
      } else if (r >= 0x0E00 && r <= 0x0E7F) {
        thai++;
      }
    }

    // Доминирующий алфавит.
    final scripts = <String, int>{
      'latin': latin,
      'cyr': cyr,
      'han': han,
      'kana': kana,
      'hangul': hangul,
      'arabic': arabic,
      'greek': greek,
      'hebrew': hebrew,
      'devanagari': devanagari,
      'thai': thai,
    };
    final top = scripts.entries.reduce((a, b) => a.value >= b.value ? a : b);
    if (top.value == 0) return null;

    switch (top.key) {
      case 'cyr':
        return hasUk ? 'uk' : 'ru';
      case 'kana':
        return 'ja';
      case 'han':
        return kana > 0 ? 'ja' : 'zh';
      case 'hangul':
        return 'ko';
      case 'arabic':
        return 'ar';
      case 'greek':
        return 'el';
      case 'hebrew':
        return 'he';
      case 'devanagari':
        return 'hi';
      case 'thai':
        return 'th';
      case 'latin':
        return _detectLatin(sample);
    }
    return null;
  }

  // Топ служебных слов латинописьменных языков (нижний регистр).
  static const Map<String, Set<String>> _stop = {
    'en': {
      'the', 'and', 'of', 'to', 'in', 'is', 'was', 'that', 'it', 'he', 'for',
      'with', 'as', 'his', 'on', 'be', 'at', 'you', 'this', 'had', 'not',
    },
    'es': {
      'el', 'la', 'de', 'que', 'y', 'los', 'las', 'un', 'una', 'en', 'con',
      'por', 'para', 'no', 'se', 'su', 'lo', 'como', 'más', 'pero',
    },
    'fr': {
      'le', 'la', 'les', 'de', 'des', 'et', 'un', 'une', 'que', 'qui', 'dans',
      'pour', 'pas', 'sur', 'il', 'elle', 'nous', 'vous', 'est', 'avec',
    },
    'de': {
      'der', 'die', 'das', 'und', 'ist', 'nicht', 'ein', 'eine', 'ich', 'zu',
      'den', 'mit', 'auf', 'für', 'war', 'sich', 'auch', 'sie', 'aber', 'dem',
    },
    'it': {
      'il', 'la', 'di', 'che', 'e', 'un', 'una', 'per', 'non', 'con', 'del',
      'le', 'si', 'lo', 'ma', 'come', 'sono', 'più', 'gli', 'nella',
    },
    'pt': {
      'o', 'a', 'de', 'que', 'e', 'do', 'da', 'em', 'um', 'uma', 'para', 'com',
      'não', 'os', 'as', 'se', 'por', 'mais', 'como', 'mas',
    },
    'nl': {
      'de', 'het', 'een', 'en', 'van', 'ik', 'te', 'dat', 'die', 'in', 'niet',
      'zijn', 'is', 'op', 'met', 'als', 'voor', 'maar', 'ook', 'aan',
    },
    'pl': {
      'i', 'w', 'nie', 'to', 'na', 'że', 'się', 'z', 'od', 'jest', 'do', 'co',
      'jak', 'ale', 'tak', 'po', 'ja', 'ten', 'go', 'tym',
    },
    'tr': {
      've', 'bir', 'bu', 'da', 'de', 'için', 'ile', 'ne', 'çok', 'daha', 'ama',
      'gibi', 'kadar', 'her', 'ben', 'sen', 'o', 'biz', 'değil', 'olan',
    },
  };

  static String _detectLatin(String sample) {
    final words = RegExp(r"[a-zà-ÿ]+", unicode: true)
        .allMatches(sample.toLowerCase())
        .map((m) => m.group(0)!)
        .toList();
    if (words.isEmpty) return 'en';
    // Считаем только по первым ~2000 слов — этого хватает и это быстро.
    final take = words.length > 2000 ? words.sublist(0, 2000) : words;
    var best = 'en';
    var bestScore = -1;
    _stop.forEach((lang, set) {
      var score = 0;
      for (final w in take) {
        if (set.contains(w)) score++;
      }
      if (score > bestScore) {
        bestScore = score;
        best = lang;
      }
    });
    return best;
  }
}
