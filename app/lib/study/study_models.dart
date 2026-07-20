import 'dart:math';

import '../models/fsrs.dart';
import '../models/word_card.dart';
import '../services/auto_grade.dart';
import '../services/interference.dart';
import '../services/lemmatizer.dart';
import '../services/word_links.dart';

/// Режимы обучения, запускаемые с экрана колоды. См. `docs/learning-system.md` §2.
enum StudyMode {
  learn,
  flashcards,
  test,
  match,
  write,
  spell,
  assemble,
  audio,
  hard,
  speed,
  cloze,
  associations,
  cram,
  revive,
}

/// Направление изучения колоды.
enum StudyDirection { forward, reverse, both }

StudyDirection studyDirectionFromIndex(int i) =>
    (i >= 0 && i < StudyDirection.values.length)
    ? StudyDirection.values[i]
    : StudyDirection.forward;

/// Тип одного упражнения (виджета) внутри сессии.
enum ExerciseKind {
  flip,
  choose,
  type,
  trueFalse,
  listen,
  cloze,
  spell,
  assemble,
  oddOne,
}

extension StudyModeInfo on StudyMode {
  /// Влияет ли режим на планировщик FSRS. Тест, игра «Подбор» и зубрёжка перед
  /// экзаменом — оценочные/временные, расписание не меняют. «Связи» проверяют
  /// не перевод, а смысловое соседство: знание другое, двигать им интервалы
  /// перевода нечестно.
  bool get affectsSchedule =>
      this != StudyMode.test &&
      this != StudyMode.match &&
      this != StudyMode.cram &&
      this != StudyMode.associations;
}

/// Почему карточка оказалась в этой сессии.
///
/// Планировщик Fern делает несколько неочевидных вещей — подтягивает слова из
/// читаемой книги, спрашивает соседей сорвавшегося слова. Без объяснения это
/// выглядит как случайность: «почему опять это слово?». Метка отвечает.
enum SelectionReason {
  /// Подошёл срок повтора — обычный случай, метку не показываем.
  due,

  /// Новое слово из колоды.
  newWord,

  /// Слово встретится на ближайших страницах открытой книги.
  book,

  /// Сосед по смыслу сорвался, и слово спрошено раньше срока.
  neighbourLapse,
}

/// Одно упражнение: карта + тип + направление (термин→перевод / перевод→термин).
class Exercise {
  final WordCard card;
  final ExerciseKind kind;

  /// reversed=false: показываем термин (front), ждём перевод (back).
  /// reversed=true: показываем перевод (back), ждём термин (front).
  final bool reversed;

  /// Почему карта здесь. Больше одной причины сразу не показываем — метка
  /// объясняет, а не отчитывается.
  final SelectionReason reason;

  Exercise(
    this.card,
    this.kind, {
    this.reversed = false,
    this.reason = SelectionReason.due,
  });

  String get prompt => reversed ? card.back : card.front;
  String get answer => reversed ? card.front : card.back;
}

/// Билдер очереди упражнений под конкретный режим.
class SessionBuilder {
  final Random _rng = Random();

  /// reversed для упражнения по направлению изучения колоды.
  bool _reversedFor(StudyDirection d) => switch (d) {
    StudyDirection.forward => false,
    StudyDirection.reverse => true,
    StudyDirection.both => _rng.nextBool(),
  };

  /// Возвращает очередь упражнений.
  ///
  /// [newAllowed] — сколько НОВЫХ карт разрешено ввести (остаток дневного
  /// лимита; 0 — новых не добавлять). [maxReviews] — потолок повторов (защита от
  /// «лавины» после перерыва). Повторы упорядочены по СРОЧНОСТИ (ближе к
  /// забыванию — раньше), новые вкраплены между ними, а не свалены в конец.
  List<Exercise> build(
    StudyMode mode,
    List<WordCard> cards,
    DateTime now, {
    int newAllowed = 12,
    int maxReviews = 100,
    int testCount = 12,
    StudyDirection direction = StudyDirection.forward,
    String language = 'en',
  }) {
    final due = cards.where((c) => !c.review.isNew && c.isDue(now)).toList();
    final fresh = cards.where((c) => c.review.isNew).toList();
    final hasChoicePool = cards.length >= 4;

    switch (mode) {
      case StudyMode.flashcards:
        return [
          for (final c in _selectSession(due, fresh, now, newAllowed, maxReviews))
            _ex(c, ExerciseKind.flip, reversed: _reversedFor(direction)),
        ];

      case StudyMode.write:
        return [
          for (final c in _selectSession(due, fresh, now, newAllowed, maxReviews))
            _ex(c, ExerciseKind.type, reversed: _reversedFor(direction)),
        ];

      case StudyMode.spell:
        // «Диктант»: слышим слово на изучаемом языке и вписываем его по буквам.
        return [
          for (final c in _selectSession(due, fresh, now, newAllowed, maxReviews))
            _ex(c, ExerciseKind.spell),
        ];

      case StudyMode.assemble:
        // «Собери фразу»: из перемешанных слов собрать предложение-контекст.
        final eligible = cards.where((c) => buildAssemble(c) != null).toList();
        final dueA =
            eligible.where((c) => !c.review.isNew && c.isDue(now)).toList();
        final freshA = eligible.where((c) => c.review.isNew).toList();
        return [
          for (final c
              in _selectSession(dueA, freshA, now, newAllowed, maxReviews))
            _ex(c, ExerciseKind.assemble),
        ];

      case StudyMode.speed:
        // Быстрая игра — небольшой набор, но по той же логике срочности.
        final sel = _selectSession(
            due, fresh, now, min(newAllowed, 5), min(maxReviews, 15));
        return [
          for (final c in sel.take(15))
            _ex(
              c,
              hasChoicePool ? ExerciseKind.choose : ExerciseKind.flip,
              reversed: _reversedFor(direction),
            ),
        ];

      case StudyMode.hard:
        final hard =
            cards
                .where((c) => c.review.lapses > 0 || c.review.difficulty >= 6)
                .toList()
              ..sort((a, b) {
                final byLapses = b.review.lapses.compareTo(a.review.lapses);
                if (byLapses != 0) return byLapses;
                return b.review.difficulty.compareTo(a.review.difficulty);
              });
        final sel = hard.take(max(1, maxReviews)).toList();
        return [
          for (final c in sel)
            _ex(c, ExerciseKind.flip, reversed: _reversedFor(direction)),
        ];

      case StudyMode.learn:
        // «Учить» — адаптивный режим со своим управлением направлением по фазе.
        return [
          for (final c in _selectSession(due, fresh, now, newAllowed, maxReviews))
            _learnExercise(c, hasChoicePool),
        ];

      case StudyMode.test:
        final pool = List<WordCard>.from(cards)..shuffle(_rng);
        final sel = pool.take(min(testCount, cards.length)).toList();
        return [
          for (final c in sel) _randomTestExercise(c, hasChoicePool, direction),
        ];

      case StudyMode.audio:
        // Слушаем слово на изучаемом языке и выбираем перевод.
        return [
          for (final c in _selectSession(due, fresh, now, newAllowed, maxReviews))
            _ex(c, ExerciseKind.listen),
        ];

      case StudyMode.cloze:
        // «Контекст»: слово пропущено в предложении из книги/видео.
        final eligible = cards.where((c) => buildCloze(c) != null).toList();
        final due2 =
            eligible.where((c) => !c.review.isNew && c.isDue(now)).toList();
        final fresh2 = eligible.where((c) => c.review.isNew).toList();
        return [
          for (final c
              in _selectSession(due2, fresh2, now, newAllowed, maxReviews))
            _ex(c, ExerciseKind.cloze),
        ];

      case StudyMode.cram:
        // «Перед экзаменом»: прогоняем ВСЕ карты (игнорируя срок), расписание
        // FSRS не трогаем — это временная зубрёжка.
        final all = List<WordCard>.from(cards)..shuffle(_rng);
        return [
          for (final c in all)
            Exercise(c, ExerciseKind.flip, reversed: _reversedFor(direction)),
        ];

      case StudyMode.associations:
        // «Связи»: два слова рядом по смыслу, третье чужое. Годятся только
        // карты, у которых связь вообще есть.
        final eligible =
            cards.where((c) => buildOddOne(c, cards, language) != null).toList();
        final dueL =
            eligible.where((c) => !c.review.isNew && c.isDue(now)).toList();
        final freshL = eligible.where((c) => c.review.isNew).toList();
        return [
          for (final c
              in _selectSession(dueL, freshL, now, newAllowed, maxReviews))
            _ex(c, ExerciseKind.oddOne),
        ];

      case StudyMode.revive:
        // «Под угрозой»: прогоняем ИМЕННО переданные карты (уже отобраны/
        // отсортированы по слабости памяти) флип-карточками, влияя на FSRS.
        return [for (final c in cards) Exercise(c, ExerciseKind.flip)];

      case StudyMode.match:
        // match — отдельный экран-игра.
        return const [];
    }
  }

  /// Карты сессии: просроченные повторы по СРОЧНОСТИ (меньше извлекаемость —
  /// ближе к забыванию — раньше; потолок [maxReviews]) + новые (до [newAllowed]),
  /// РАВНОМЕРНО вкраплённые между повторами (новые слова встречаются на
  /// протяжении сессии, а не пачкой в конце на усталости).
  List<WordCard> _selectSession(
    List<WordCard> due,
    List<WordCard> fresh,
    DateTime now,
    int newAllowed,
    int maxReviews,
  ) {
    final reviews = List<WordCard>.from(due)
      ..sort((a, b) => _score(a, now).compareTo(_score(b, now)));
    final cappedReviews =
        maxReviews > 0 ? reviews.take(maxReviews).toList() : reviews;

    // Новые слова: вперёд идут те, что встретятся на ближайших страницах —
    // выучить вечером и наткнуться на них в книге стоит дороже, чем выучить
    // случайное слово из середины колоды.
    final freshSorted = _upcoming.isEmpty
        ? fresh
        : (List<WordCard>.from(fresh)
          ..sort((a, b) {
            final ua = _isUpcoming(a) ? 0 : 1;
            final ub = _isUpcoming(b) ? 0 : 1;
            return ua.compareTo(ub);
          }));
    // Путаемые слова в один заход не пускаем: пара вроде affect/effect,
    // введённая вместе, портит обе карточки разом.
    final busy = due
        .where((c) =>
            c.review.state == FsrsState.learning ||
            c.review.state == FsrsState.relearning)
        .toList();
    final news = newAllowed > 0
        ? Interference.pickNew(freshSorted, busy).take(newAllowed).toList()
        : <WordCard>[];
    final mixed = _interleave(cappedReviews, news);
    // Считаем ловушки ДО разведения — после него их в очереди уже не видно.
    _separatedPairs = Interference.countConflicts(mixed);
    return Interference.spread(mixed);
  }

  int _separatedPairs = 0;

  /// Сколько путаемых пар оказалось в собранной сессии и было разведено.
  int get separatedPairs => _separatedPairs;

  /// Упражнение с проставленной причиной отбора.
  Exercise _ex(WordCard c, ExerciseKind kind, {bool reversed = false}) =>
      Exercise(c, kind, reversed: reversed, reason: _reasonFor(c));

  /// Почему карта попала в сессию. Порядок важен: сначала то, что человек не
  /// может вывести сам (сосед, книга), и только потом обычные «новое»/«срок».
  SelectionReason _reasonFor(WordCard c) {
    if (c.review.nudgedByNeighbour) return SelectionReason.neighbourLapse;
    if (_isUpcoming(c)) return SelectionReason.book;
    if (c.review.isNew) return SelectionReason.newWord;
    return SelectionReason.due;
  }

  /// Слова из ближайших страниц читаемой книги (основы) и их язык.
  Set<String> _upcoming = const {};
  String _upcomingLang = 'en';

  /// Сообщает билдеру, что человеку вот-вот встретится в книге.
  /// Пустое множество возвращает обычное поведение.
  void setReadingHorizon(Set<String> stems, String languageCode) {
    _upcoming = stems;
    _upcomingLang = languageCode;
  }

  bool _isUpcoming(WordCard c) =>
      _upcoming.isNotEmpty &&
      _upcoming.contains(Lemmatizer.stem(c.front, _upcomingLang));

  /// Очередь повторов: срочность плюс небольшая фора словам из ближайших
  /// страниц. Фора именно небольшая — забывание важнее удобного совпадения.
  double _score(WordCard c, DateTime now) {
    final u = _urgency(c, now);
    return _isUpcoming(c) ? u * 0.8 : u;
  }

  /// Извлекаемость карты (0..1) сейчас — чем меньше, тем срочнее повтор.
  double _urgency(WordCard c, DateTime now) {
    final last = c.review.lastReview;
    final elapsed = last == null
        ? 0.0
        : max(0, now.difference(last).inSeconds / 86400.0).toDouble();
    return Fsrs.instance.retrievability(elapsed, c.review.stability);
  }

  /// Равномерно распределяет [news] среди [reviews] (порядок повторов сохранён).
  List<WordCard> _interleave(List<WordCard> reviews, List<WordCard> news) {
    if (news.isEmpty) return reviews;
    if (reviews.isEmpty) return news;
    final out = <WordCard>[];
    final gap = max(1, reviews.length ~/ news.length);
    var ri = 0, ni = 0, since = 0;
    while (ri < reviews.length || ni < news.length) {
      if (ni < news.length && (ri >= reviews.length || since >= gap)) {
        out.add(news[ni++]);
        since = 0;
      } else {
        out.add(reviews[ri++]);
        since++;
      }
    }
    return out;
  }

  /// Упражнение для режима «Учить» — тип по фазе владения картой.
  Exercise _learnExercise(WordCard c, bool hasChoicePool) {
    switch (c.review.phase) {
      case LearnPhase.unseen:
      case LearnPhase.recognize:
        return _ex(c, hasChoicePool ? ExerciseKind.choose : ExerciseKind.flip);
      case LearnPhase.produce:
        return _ex(
          c,
          hasChoicePool ? ExerciseKind.choose : ExerciseKind.flip,
          reversed: true,
        );
      case LearnPhase.recall:
        return _ex(c, ExerciseKind.type);
      case LearnPhase.mastered:
        return _ex(c, ExerciseKind.flip);
    }
  }

  Exercise _randomTestExercise(
    WordCard c,
    bool hasChoicePool,
    StudyDirection direction,
  ) {
    final kinds = <ExerciseKind>[
      if (hasChoicePool) ExerciseKind.choose,
      if (hasChoicePool) ExerciseKind.trueFalse,
      ExerciseKind.type,
    ];
    final kind = kinds[_rng.nextInt(kinds.length)];
    return Exercise(c, kind, reversed: _reversedFor(direction));
  }

  /// Отвлекающие варианты (ответы других карт) для выбора/верно-неверно.
  ///
  /// Не случайные, а ПОХОЖИЕ: приоритет — та же часть речи и близкая длина.
  /// Случайный «кот / вторник / бежать» отгадывается исключением абсурда;
  /// похожие варианты заставляют реально различать значения.
  List<String> distractors(Exercise ex, List<WordCard> pool, {int n = 3}) {
    final correct = ex.answer.trim().toLowerCase();
    final targetPos = ex.card.pos;
    final targetLen = ex.answer.trim().length;

    // Кандидаты (уникальные по значению, без правильного ответа).
    final seen = <String>{};
    final cands = <(WordCard, String)>[];
    for (final c in pool) {
      if (identical(c, ex.card)) continue;
      final v = (ex.reversed ? c.front : c.back).trim();
      if (v.isEmpty) continue;
      final key = v.toLowerCase();
      if (key == correct || !seen.add(key)) continue;
      cands.add((c, v));
    }
    // Немного случайности (перемешиваем до стабильной сортировки), затем — по
    // похожести. Так варианты меняются, но остаются правдоподобными.
    cands.shuffle(_rng);
    cands.sort((a, b) => _distractorScore(b.$1, b.$2, targetPos, targetLen)
        .compareTo(_distractorScore(a.$1, a.$2, targetPos, targetLen)));
    return [for (final e in cands.take(n)) e.$2];
  }

  /// Похожесть кандидата на правильный ответ: та же часть речи важнее близости
  /// длины.
  double _distractorScore(
      WordCard c, String value, String targetPos, int targetLen) {
    var s = 0.0;
    if (targetPos.isNotEmpty && c.pos == targetPos) s += 2.0;
    final lenDiff = (value.trim().length - targetLen).abs();
    s += 1.0 / (1 + lenDiff * 0.15); // ближе по длине — больше
    return s;
  }

  /// Случайный «неправильный» перевод для TrueFalse (или null, если нет пары).
  String? wrongAnswer(Exercise ex, List<WordCard> pool) {
    final d = distractors(ex, pool, n: 1);
    return d.isEmpty ? null : d.first;
  }
}

/// Предложение-«пропуск»: контекст из книги/видео с вырезанным словом.
class Cloze {
  /// Предложение с пропуском (____) вместо изучаемого слова.
  final String blanked;

  /// Слово, которое было вырезано (как оно стоит в тексте) — правильный ответ.
  final String answer;

  const Cloze(this.blanked, this.answer);
}

final RegExp _clozeToken = RegExp(r'\S+');
final RegExp _clozeEdge = RegExp(
  r'^[^\p{L}\p{N}]+|[^\p{L}\p{N}]+$',
  unicode: true,
);
const String _clozeGap = '_____'; // пропуск фиксированной длины

/// Строит клоуз-упражнение из карточки: берём её предложение-контекст
/// ([WordCard.sentence] или [WordCard.example]) и вырезаем изучаемое слово.
/// null — если контекста нет или слово в нём не найдено (карта не подходит).
Cloze? buildCloze(WordCard card) {
  final text = card.sentence.trim().isNotEmpty
      ? card.sentence.trim()
      : card.example.trim();
  if (text.isEmpty) return null;
  final front = card.front.trim().toLowerCase();
  if (front.isEmpty) return null;

  for (final m in _clozeToken.allMatches(text)) {
    final raw = m.group(0)!;
    final clean = raw.replaceAll(_clozeEdge, '');
    if (clean.isEmpty) continue;
    if (clean.toLowerCase() == front) {
      // Меняем только «чистую» часть токена, сохраняя пунктуацию вокруг.
      final blankToken = raw.replaceFirst(clean, _clozeGap);
      final blanked = text.replaceRange(m.start, m.end, blankToken);
      return Cloze(blanked, clean);
    }
  }
  return null;
}

/// Упражнение «третий лишний»: два слова связаны, третье — чужое.
class OddOne {
  /// Варианты в том порядке, в каком их показывают.
  final List<WordCard> options;

  /// Индекс лишнего слова в [options].
  final int oddIndex;

  /// Чем связаны два «своих» слова — это и объясняем после ответа.
  final LinkKind kind;

  const OddOne(this.options, this.oddIndex, this.kind);

  WordCard get odd => options[oddIndex];
}

/// Строит «третьего лишнего» вокруг [card]: берём её связь (вычисленную или
/// проставленную руками) и добавляем слово, ни с чем здесь не связанное.
/// null — если у карточки нет связей или в колоде не нашлось чужого слова.
OddOne? buildOddOne(WordCard card, List<WordCard> pool, String lang) {
  final links = WordLinks.all(card, pool, lang);
  if (links.isEmpty) return null;
  final link = links.first;

  // Чужое слово: не сама карта, не её пара и ни с одной из них не связано.
  final related = {
    card.id,
    link.card.id,
    ...links.map((l) => l.card.id),
    ...WordLinks.all(link.card, pool, lang).map((l) => l.card.id),
  };
  final strangers = pool.where((c) => !related.contains(c.id)).toList();
  if (strangers.isEmpty) return null;

  // Разброс по слову-карте, а не случайный: одна и та же карточка в рамках
  // сессии не должна выдавать разный набор при пересборке.
  final seed = card.id.hashCode;
  final stranger = strangers[seed.abs() % strangers.length];

  final options = [card, link.card, stranger]..shuffle(Random(seed));
  return OddOne(options, options.indexOf(stranger), link.kind);
}

/// Упражнение «собери фразу»: целевое предложение и его слова-осколки.
class Assemble {
  /// Целевое предложение (на изучаемом языке) — эталон.
  final String sentence;

  /// Слова предложения по порядку (в UI показываются перемешанными).
  final List<String> tokens;

  const Assemble(this.sentence, this.tokens);
}

final RegExp _assembleWs = RegExp(r'\s+');
final RegExp _assemblePunct = RegExp(r'''[^\p{L}\p{N}\s]''', unicode: true);

/// Строит «собери фразу» из предложения-контекста карточки
/// ([WordCard.sentence] или [WordCard.example]). Годится, если в предложении
/// 2–12 слов; иначе null (одно слово нечего собирать, а длинное — муторно).
Assemble? buildAssemble(WordCard card) {
  final text = card.sentence.trim().isNotEmpty
      ? card.sentence.trim()
      : card.example.trim();
  if (text.isEmpty) return null;
  final words = text.split(_assembleWs).where((w) => w.trim().isNotEmpty).toList();
  if (words.length < 2 || words.length > 12) return null;
  return Assemble(text, words);
}

/// Нормализует фразу для сравнения: убирает пунктуацию, регистр и лишние
/// пробелы (порядок слов при этом сохраняется — именно его и проверяем).
String normalizePhrase(String s) => s
    .replaceAll(_assemblePunct, ' ')
    .toLowerCase()
    .replaceAll(_assembleWs, ' ')
    .trim();

/// Верно ли собрана фраза [tokens] относительно эталонного [sentence]
/// (сравнение без учёта пунктуации/регистра).
bool assembleMatches(List<String> tokens, String sentence) =>
    normalizePhrase(tokens.join(' ')) == normalizePhrase(sentence);

/// Нормализация ответа для проверки ввода: регистр, пробелы, артикли-хвосты.
String normalizeAnswer(String s) {
  var t = s.trim().toLowerCase();
  t = t.replaceAll(RegExp(r'\s+'), ' ');
  return t;
}

/// Толерантная проверка: точное совпадение после нормализации ИЛИ расстояние
/// Левенштейна ≤1 (одна опечатка) для слов длиннее 3 символов.
///
/// Разбор на «точно / описка / промах» живёт в [typedQuality] — здесь только
/// ответ «засчитано ли». Одна общая функция на оба вопроса: иначе автооценка
/// могла бы посчитать ответ опиской там, где сессия засчитала его как промах.
bool answerMatches(String input, String expected) =>
    typedQuality(input, expected) != TypedMatch.wrong;
