import 'dart:math';

import '../models/fsrs.dart';
import '../models/word_card.dart';

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
  cram,
}

/// Направление изучения колоды.
enum StudyDirection { forward, reverse, both }

StudyDirection studyDirectionFromIndex(int i) =>
    (i >= 0 && i < StudyDirection.values.length)
    ? StudyDirection.values[i]
    : StudyDirection.forward;

/// Тип одного упражнения (виджета) внутри сессии.
enum ExerciseKind { flip, choose, type, trueFalse, listen, cloze, spell, assemble }

extension StudyModeInfo on StudyMode {
  /// Влияет ли режим на планировщик FSRS. Тест, игра «Подбор» и зубрёжка перед
  /// экзаменом — оценочные/временные, расписание не меняют.
  bool get affectsSchedule =>
      this != StudyMode.test &&
      this != StudyMode.match &&
      this != StudyMode.cram;
}

/// Одно упражнение: карта + тип + направление (термин→перевод / перевод→термин).
class Exercise {
  final WordCard card;
  final ExerciseKind kind;

  /// reversed=false: показываем термин (front), ждём перевод (back).
  /// reversed=true: показываем перевод (back), ждём термин (front).
  final bool reversed;

  Exercise(this.card, this.kind, {this.reversed = false});

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
  }) {
    final due = cards.where((c) => !c.review.isNew && c.isDue(now)).toList();
    final fresh = cards.where((c) => c.review.isNew).toList();
    final hasChoicePool = cards.length >= 4;

    switch (mode) {
      case StudyMode.flashcards:
        return [
          for (final c in _selectSession(due, fresh, now, newAllowed, maxReviews))
            Exercise(c, ExerciseKind.flip, reversed: _reversedFor(direction)),
        ];

      case StudyMode.write:
        return [
          for (final c in _selectSession(due, fresh, now, newAllowed, maxReviews))
            Exercise(c, ExerciseKind.type, reversed: _reversedFor(direction)),
        ];

      case StudyMode.spell:
        // «Диктант»: слышим слово на изучаемом языке и вписываем его по буквам.
        return [
          for (final c in _selectSession(due, fresh, now, newAllowed, maxReviews))
            Exercise(c, ExerciseKind.spell),
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
            Exercise(c, ExerciseKind.assemble),
        ];

      case StudyMode.speed:
        // Быстрая игра — небольшой набор, но по той же логике срочности.
        final sel = _selectSession(
            due, fresh, now, min(newAllowed, 5), min(maxReviews, 15));
        return [
          for (final c in sel.take(15))
            Exercise(
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
            Exercise(c, ExerciseKind.flip, reversed: _reversedFor(direction)),
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
            Exercise(c, ExerciseKind.listen),
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
            Exercise(c, ExerciseKind.cloze),
        ];

      case StudyMode.cram:
        // «Перед экзаменом»: прогоняем ВСЕ карты (игнорируя срок), расписание
        // FSRS не трогаем — это временная зубрёжка.
        final all = List<WordCard>.from(cards)..shuffle(_rng);
        return [
          for (final c in all)
            Exercise(c, ExerciseKind.flip, reversed: _reversedFor(direction)),
        ];

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
      ..sort((a, b) => _urgency(a, now).compareTo(_urgency(b, now)));
    final cappedReviews =
        maxReviews > 0 ? reviews.take(maxReviews).toList() : reviews;
    final news = newAllowed > 0 ? fresh.take(newAllowed).toList() : <WordCard>[];
    return _interleave(cappedReviews, news);
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
        return Exercise(
          c,
          hasChoicePool ? ExerciseKind.choose : ExerciseKind.flip,
        );
      case LearnPhase.produce:
        return Exercise(
          c,
          hasChoicePool ? ExerciseKind.choose : ExerciseKind.flip,
          reversed: true,
        );
      case LearnPhase.recall:
        return Exercise(c, ExerciseKind.type);
      case LearnPhase.mastered:
        return Exercise(c, ExerciseKind.flip);
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
bool answerMatches(String input, String expected) {
  final a = normalizeAnswer(input);
  final b = normalizeAnswer(expected);
  if (a.isEmpty) return false;
  if (a == b) return true;
  // Иногда в переводе несколько вариантов через запятую/точку с запятой.
  for (final part in b.split(RegExp(r'[,;/]'))) {
    final p = part.trim();
    if (p.isNotEmpty && (a == p || (p.length > 3 && _levenshtein(a, p) <= 1))) {
      return true;
    }
  }
  return b.length > 3 && _levenshtein(a, b) <= 1;
}

int _levenshtein(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;
  var prev = List<int>.generate(b.length + 1, (i) => i);
  var cur = List<int>.filled(b.length + 1, 0);
  for (var i = 0; i < a.length; i++) {
    cur[0] = i + 1;
    for (var j = 0; j < b.length; j++) {
      final cost = a[i] == b[j] ? 0 : 1;
      cur[j + 1] = [
        cur[j] + 1,
        prev[j + 1] + 1,
        prev[j] + cost,
      ].reduce((x, y) => x < y ? x : y);
    }
    final tmp = prev;
    prev = cur;
    cur = tmp;
  }
  return prev[b.length];
}
