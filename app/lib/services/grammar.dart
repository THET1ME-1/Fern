/// Офлайн-грамматика карточки: спряжение глаголов (настоящее время) и формы
/// существительных. Правила покрывают регулярные модели + список частых
/// неправильных глаголов; для нестандартных слов формы приблизительны (об этом
/// честно сообщает подпись таблицы). Без сети и без внешних данных.
library;

import '../l10n/strings.dart';

/// Одна строка таблицы: подпись (лицо/число) и форма слова.
class GrammarRow {
  final String label;
  final String form;
  const GrammarRow(this.label, this.form);
}

/// Таблица грамматических форм с заголовком.
class GrammarTable {
  final String title;
  final List<GrammarRow> rows;

  /// Формы получены по правилам (могут быть неточны для исключений).
  final bool approximate;

  const GrammarTable(this.title, this.rows, {this.approximate = true});
}

class Grammar {
  Grammar._();

  /// Есть ли что показать для слова (быстрая проверка перед отрисовкой секции).
  static bool has(String word, String pos, String lang) =>
      forWord(word, pos, lang).isNotEmpty;

  /// Грамматические таблицы для [word] с частью речи [pos] на языке [lang].
  static List<GrammarTable> forWord(String word, String pos, String lang) {
    final w = word.trim().toLowerCase();
    final l = lang.split('-').first.toLowerCase();
    if (w.isEmpty || w.contains(' ')) return const []; // только одиночные слова
    switch (pos) {
      case 'verb':
        return _verb(w, l);
      case 'noun':
        return _noun(w, l);
      default:
        return const [];
    }
  }

  // =============================== Глаголы ===============================

  static List<GrammarTable> _verb(String w, String l) {
    final table = switch (l) {
      'es' => _esVerb(w),
      'fr' => _frVerb(w),
      'de' => _deVerb(w),
      'it' => _itVerb(w),
      'pt' => _ptVerb(w),
      'ru' => _ruVerb(w),
      _ => null,
    };
    return table == null ? const [] : [table];
  }

  static GrammarTable _fromForms(
    List<String> pronouns,
    List<String> forms, {
    bool approximate = true,
  }) {
    return GrammarTable(
      tr('grammar_present'),
      [for (var i = 0; i < pronouns.length; i++) GrammarRow(pronouns[i], forms[i])],
      approximate: approximate,
    );
  }

  // --- Испанский ---
  static const _esPron = ['yo', 'tú', 'él/ella', 'nosotros', 'vosotros', 'ellos'];
  static const Map<String, List<String>> _esIrr = {
    'ser': ['soy', 'eres', 'es', 'somos', 'sois', 'son'],
    'estar': ['estoy', 'estás', 'está', 'estamos', 'estáis', 'están'],
    'ir': ['voy', 'vas', 'va', 'vamos', 'vais', 'van'],
    'haber': ['he', 'has', 'ha', 'hemos', 'habéis', 'han'],
    'tener': ['tengo', 'tienes', 'tiene', 'tenemos', 'tenéis', 'tienen'],
    'hacer': ['hago', 'haces', 'hace', 'hacemos', 'hacéis', 'hacen'],
    'poder': ['puedo', 'puedes', 'puede', 'podemos', 'podéis', 'pueden'],
    'querer': ['quiero', 'quieres', 'quiere', 'queremos', 'queréis', 'quieren'],
    'decir': ['digo', 'dices', 'dice', 'decimos', 'decís', 'dicen'],
    'ver': ['veo', 'ves', 've', 'vemos', 'veis', 'ven'],
    'dar': ['doy', 'das', 'da', 'damos', 'dais', 'dan'],
    'saber': ['sé', 'sabes', 'sabe', 'sabemos', 'sabéis', 'saben'],
    'venir': ['vengo', 'vienes', 'viene', 'venimos', 'venís', 'vienen'],
    'poner': ['pongo', 'pones', 'pone', 'ponemos', 'ponéis', 'ponen'],
  };
  static GrammarTable? _esVerb(String w) {
    if (_esIrr.containsKey(w)) {
      return _fromForms(_esPron, _esIrr[w]!, approximate: false);
    }
    if (w.length < 3) return null;
    final stem = w.substring(0, w.length - 2);
    final end = w.substring(w.length - 2);
    final forms = switch (end) {
      'ar' => ['o', 'as', 'a', 'amos', 'áis', 'an'],
      'er' => ['o', 'es', 'e', 'emos', 'éis', 'en'],
      'ir' => ['o', 'es', 'e', 'imos', 'ís', 'en'],
      _ => null,
    };
    if (forms == null) return null;
    return _fromForms(_esPron, [for (final f in forms) '$stem$f']);
  }

  // --- Французский ---
  static const _frPron = ['je', 'tu', 'il/elle', 'nous', 'vous', 'ils/elles'];
  static const Map<String, List<String>> _frIrr = {
    'être': ['suis', 'es', 'est', 'sommes', 'êtes', 'sont'],
    'avoir': ['ai', 'as', 'a', 'avons', 'avez', 'ont'],
    'aller': ['vais', 'vas', 'va', 'allons', 'allez', 'vont'],
    'faire': ['fais', 'fais', 'fait', 'faisons', 'faites', 'font'],
    'pouvoir': ['peux', 'peux', 'peut', 'pouvons', 'pouvez', 'peuvent'],
    'vouloir': ['veux', 'veux', 'veut', 'voulons', 'voulez', 'veulent'],
    'dire': ['dis', 'dis', 'dit', 'disons', 'dites', 'disent'],
    'voir': ['vois', 'vois', 'voit', 'voyons', 'voyez', 'voient'],
    'prendre': ['prends', 'prends', 'prend', 'prenons', 'prenez', 'prennent'],
    'venir': ['viens', 'viens', 'vient', 'venons', 'venez', 'viennent'],
    'savoir': ['sais', 'sais', 'sait', 'savons', 'savez', 'savent'],
    'devoir': ['dois', 'dois', 'doit', 'devons', 'devez', 'doivent'],
  };
  static const _frVowel = 'aeiouyàâäéèêîïôûh';
  static GrammarTable? _frVerb(String w) {
    if (_frIrr.containsKey(w)) {
      return _fromForms(_frElide(_frIrr[w]!), _frIrr[w]!,
          approximate: false);
    }
    if (w.length < 3) return null;
    final stem = w.substring(0, w.length - 2);
    final end = w.substring(w.length - 2);
    List<String>? forms;
    if (end == 'er') {
      forms = ['e', 'es', 'e', 'ons', 'ez', 'ent'].map((s) => '$stem$s').toList();
    } else if (end == 'ir') {
      forms = ['is', 'is', 'it', 'issons', 'issez', 'issent']
          .map((s) => '$stem$s')
          .toList();
    } else if (end == 're') {
      final s2 = w.substring(0, w.length - 2);
      forms = ['s', 's', '', 'ons', 'ez', 'ent'].map((s) => '$s2$s').toList();
    }
    if (forms == null) return null;
    return _fromForms(_frElide(forms), forms);
  }

  /// «je» → «j’» перед гласной (j’aime), иначе «je».
  static List<String> _frElide(List<String> forms) {
    final pron = List<String>.from(_frPron);
    if (forms.isNotEmpty &&
        forms.first.isNotEmpty &&
        _frVowel.contains(forms.first[0])) {
      pron[0] = 'j’';
    }
    return pron;
  }

  // --- Немецкий ---
  static const _dePron = ['ich', 'du', 'er/sie/es', 'wir', 'ihr', 'sie'];
  static const Map<String, List<String>> _deIrr = {
    'sein': ['bin', 'bist', 'ist', 'sind', 'seid', 'sind'],
    'haben': ['habe', 'hast', 'hat', 'haben', 'habt', 'haben'],
    'werden': ['werde', 'wirst', 'wird', 'werden', 'werdet', 'werden'],
    'können': ['kann', 'kannst', 'kann', 'können', 'könnt', 'können'],
    'müssen': ['muss', 'musst', 'muss', 'müssen', 'müsst', 'müssen'],
    'wollen': ['will', 'willst', 'will', 'wollen', 'wollt', 'wollen'],
    'wissen': ['weiß', 'weißt', 'weiß', 'wissen', 'wisst', 'wissen'],
    'fahren': ['fahre', 'fährst', 'fährt', 'fahren', 'fahrt', 'fahren'],
    'geben': ['gebe', 'gibst', 'gibt', 'geben', 'gebt', 'geben'],
    'nehmen': ['nehme', 'nimmst', 'nimmt', 'nehmen', 'nehmt', 'nehmen'],
  };
  static GrammarTable? _deVerb(String w) {
    if (_deIrr.containsKey(w)) {
      return _fromForms(_dePron, _deIrr[w]!, approximate: false);
    }
    if (!w.endsWith('en') || w.length < 4) return null;
    final stem = w.substring(0, w.length - 2);
    // -t/-d в основе → вставная -e- (arbeitest); шипящие → 2 л. -t (heißt).
    final needsE = stem.endsWith('t') || stem.endsWith('d');
    final sib = RegExp(r'[sßxz]$').hasMatch(stem);
    final du = sib ? '${stem}t' : (needsE ? '${stem}est' : '${stem}st');
    final er = needsE ? '${stem}et' : '${stem}t';
    final ihr = needsE ? '${stem}et' : '${stem}t';
    return _fromForms(_dePron, ['${stem}e', du, er, w, ihr, w]);
  }

  // --- Итальянский ---
  static const _itPron = ['io', 'tu', 'lui/lei', 'noi', 'voi', 'loro'];
  static const Map<String, List<String>> _itIrr = {
    'essere': ['sono', 'sei', 'è', 'siamo', 'siete', 'sono'],
    'avere': ['ho', 'hai', 'ha', 'abbiamo', 'avete', 'hanno'],
    'fare': ['faccio', 'fai', 'fa', 'facciamo', 'fate', 'fanno'],
    'andare': ['vado', 'vai', 'va', 'andiamo', 'andate', 'vanno'],
    'potere': ['posso', 'puoi', 'può', 'possiamo', 'potete', 'possono'],
    'volere': ['voglio', 'vuoi', 'vuole', 'vogliamo', 'volete', 'vogliono'],
    'dire': ['dico', 'dici', 'dice', 'diciamo', 'dite', 'dicono'],
    'venire': ['vengo', 'vieni', 'viene', 'veniamo', 'venite', 'vengono'],
    'stare': ['sto', 'stai', 'sta', 'stiamo', 'state', 'stanno'],
    'dare': ['do', 'dai', 'dà', 'diamo', 'date', 'danno'],
  };
  static GrammarTable? _itVerb(String w) {
    if (_itIrr.containsKey(w)) {
      return _fromForms(_itPron, _itIrr[w]!, approximate: false);
    }
    if (w.length < 4) return null;
    final stem = w.substring(0, w.length - 3);
    final end = w.substring(w.length - 3);
    final forms = switch (end) {
      'are' => ['o', 'i', 'a', 'iamo', 'ate', 'ano'],
      'ere' => ['o', 'i', 'e', 'iamo', 'ete', 'ono'],
      'ire' => ['o', 'i', 'e', 'iamo', 'ite', 'ono'],
      _ => null,
    };
    if (forms == null) return null;
    return _fromForms(_itPron, [for (final f in forms) '$stem$f']);
  }

  // --- Португальский ---
  static const _ptPron = ['eu', 'tu', 'ele/ela', 'nós', 'vós', 'eles/elas'];
  static const Map<String, List<String>> _ptIrr = {
    'ser': ['sou', 'és', 'é', 'somos', 'sois', 'são'],
    'estar': ['estou', 'estás', 'está', 'estamos', 'estais', 'estão'],
    'ir': ['vou', 'vais', 'vai', 'vamos', 'ides', 'vão'],
    'ter': ['tenho', 'tens', 'tem', 'temos', 'tendes', 'têm'],
    'fazer': ['faço', 'fazes', 'faz', 'fazemos', 'fazeis', 'fazem'],
    'poder': ['posso', 'podes', 'pode', 'podemos', 'podeis', 'podem'],
    'dizer': ['digo', 'dizes', 'diz', 'dizemos', 'dizeis', 'dizem'],
    'ver': ['vejo', 'vês', 'vê', 'vemos', 'vedes', 'veem'],
    'dar': ['dou', 'dás', 'dá', 'damos', 'dais', 'dão'],
    'vir': ['venho', 'vens', 'vem', 'vimos', 'vindes', 'vêm'],
  };
  static GrammarTable? _ptVerb(String w) {
    if (_ptIrr.containsKey(w)) {
      return _fromForms(_ptPron, _ptIrr[w]!, approximate: false);
    }
    if (w.length < 3) return null;
    final stem = w.substring(0, w.length - 2);
    final end = w.substring(w.length - 2);
    final forms = switch (end) {
      'ar' => ['o', 'as', 'a', 'amos', 'ais', 'am'],
      'er' => ['o', 'es', 'e', 'emos', 'eis', 'em'],
      'ir' => ['o', 'es', 'e', 'imos', 'is', 'em'],
      _ => null,
    };
    if (forms == null) return null;
    return _fromForms(_ptPron, [for (final f in forms) '$stem$f']);
  }

  // --- Русский (приблизительно) ---
  static const _ruPron = ['я', 'ты', 'он/она', 'мы', 'вы', 'они'];
  static const Map<String, List<String>> _ruIrr = {
    'быть': ['есть', 'есть', 'есть', 'есть', 'есть', 'есть'],
    'хотеть': ['хочу', 'хочешь', 'хочет', 'хотим', 'хотите', 'хотят'],
    'есть': ['ем', 'ешь', 'ест', 'едим', 'едите', 'едят'],
    'идти': ['иду', 'идёшь', 'идёт', 'идём', 'идёте', 'идут'],
    'дать': ['дам', 'дашь', 'даст', 'дадим', 'дадите', 'дадут'],
  };
  static GrammarTable? _ruVerb(String w) {
    if (_ruIrr.containsKey(w)) {
      return _fromForms(_ruPron, _ruIrr[w]!, approximate: false);
    }
    if (w.length < 4) return null;
    // 2-е спряжение: -ить (говорить → говорю, говоришь…).
    if (w.endsWith('ить')) {
      final st = w.substring(0, w.length - 3);
      return _fromForms(_ruPron,
          ['$stю', '$stишь', '$stит', '$stим', '$stите', '$stят']);
    }
    // 1-е спряжение: -ать/-ять (читать → читаю…).
    if (w.endsWith('ать') || w.endsWith('ять')) {
      final st = w.substring(0, w.length - 2);
      return _fromForms(_ruPron, [
        '$stю',
        '$stешь',
        '$stет',
        '$stем',
        '$stете',
        '$stют'
      ]);
    }
    return null;
  }

  // =============================== Существительные ===============================

  /// Множественное число для романских языков (регулярные модели).
  static List<GrammarTable> _noun(String w, String l) {
    final plural = switch (l) {
      'es' => _esPlural(w),
      'pt' => _esPlural(w), // близкая модель
      'it' => _itPlural(w),
      'fr' => _frPlural(w),
      _ => null,
    };
    if (plural == null) return const [];
    return [
      GrammarTable(tr('grammar_forms'), [
        GrammarRow(tr('grammar_singular'), w),
        GrammarRow(tr('grammar_plural'), plural),
      ]),
    ];
  }

  static String? _esPlural(String w) {
    if (w.isEmpty) return null;
    final last = w[w.length - 1];
    if ('aeiouáéíóú'.contains(last)) return '${w}s';
    if (last == 'z') return '${w.substring(0, w.length - 1)}ces';
    return '${w}es';
  }

  static String? _itPlural(String w) {
    if (w.length < 2) return null;
    final last = w[w.length - 1];
    if (last == 'o' || last == 'e') return '${w.substring(0, w.length - 1)}i';
    if (last == 'a') return '${w.substring(0, w.length - 1)}e';
    return null; // неизменяемые/исключения не трогаем
  }

  static String? _frPlural(String w) {
    if (w.isEmpty) return null;
    if (w.endsWith('s') || w.endsWith('x') || w.endsWith('z')) return w;
    if (w.endsWith('eau') || w.endsWith('eu')) return '${w}x';
    if (w.endsWith('al')) return '${w.substring(0, w.length - 2)}aux';
    return '${w}s';
  }
}
