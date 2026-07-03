import 'dart:math';

import '../models/word_card.dart';

/// Режимы обучения, запускаемые с экрана колоды. См. `docs/learning-system.md` §2.
enum StudyMode { learn, flashcards, test, match, write, audio, hard, speed }

/// Направление изучения колоды.
enum StudyDirection { forward, reverse, both }

StudyDirection studyDirectionFromIndex(int i) =>
    (i >= 0 && i < StudyDirection.values.length)
    ? StudyDirection.values[i]
    : StudyDirection.forward;

/// Тип одного упражнения (виджета) внутри сессии.
enum ExerciseKind { flip, choose, type, trueFalse, listen }

extension StudyModeInfo on StudyMode {
  /// Влияет ли режим на планировщик FSRS. Тест и игра «Подбор» —
  /// оценочные/игровые, расписание не меняют.
  bool get affectsSchedule => this != StudyMode.test && this != StudyMode.match;
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

  /// Возвращает очередь упражнений. [cards] — карты колоды, [goal] — дневная
  /// цель (лимит новых), [now] — текущий момент, [direction] — направление.
  List<Exercise> build(
    StudyMode mode,
    List<WordCard> cards,
    DateTime now, {
    int goal = 20,
    int testCount = 12,
    StudyDirection direction = StudyDirection.forward,
  }) {
    final due = cards.where((c) => !c.review.isNew && c.isDue(now)).toList();
    final fresh = cards.where((c) => c.review.isNew).toList();
    final hasChoicePool = cards.length >= 4;

    switch (mode) {
      case StudyMode.flashcards:
        final sel = _selectDueAndNew(due, fresh, goal);
        return [
          for (final c in sel)
            Exercise(c, ExerciseKind.flip, reversed: _reversedFor(direction)),
        ];

      case StudyMode.write:
        final sel = _selectDueAndNew(due, fresh, goal);
        return _shuffled([
          for (final c in sel)
            Exercise(c, ExerciseKind.type, reversed: _reversedFor(direction)),
        ]);

      case StudyMode.speed:
        final sel = _selectDueAndNew(due, fresh, min(goal, 15));
        return _shuffled([
          for (final c in sel)
            Exercise(
              c,
              hasChoicePool ? ExerciseKind.choose : ExerciseKind.flip,
              reversed: _reversedFor(direction),
            ),
        ]);

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
        final sel = hard.take(goal).toList();
        return [
          for (final c in sel)
            Exercise(c, ExerciseKind.flip, reversed: _reversedFor(direction)),
        ];

      case StudyMode.learn:
        // «Учить» — адаптивный режим со своим управлением направлением по фазе.
        final sel = _selectDueAndNew(due, fresh, goal);
        return _shuffled([
          for (final c in sel) _learnExercise(c, hasChoicePool),
        ]);

      case StudyMode.test:
        final pool = List<WordCard>.from(cards)..shuffle(_rng);
        final sel = pool.take(min(testCount, cards.length)).toList();
        return [
          for (final c in sel) _randomTestExercise(c, hasChoicePool, direction),
        ];

      case StudyMode.audio:
        // Слушаем слово на изучаемом языке и выбираем перевод.
        final sel = _selectDueAndNew(due, fresh, goal);
        return _shuffled([
          for (final c in sel) Exercise(c, ExerciseKind.listen),
        ]);

      case StudyMode.match:
        // match — отдельный экран-игра.
        return const [];
    }
  }

  /// Выбор карт: сперва просроченные повторы, затем новые до лимита [goal].
  List<WordCard> _selectDueAndNew(
    List<WordCard> due,
    List<WordCard> fresh,
    int goal,
  ) {
    final list = <WordCard>[...due];
    if (list.length < goal) {
      list.addAll(fresh.take(goal - list.length));
    }
    return list;
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

  List<Exercise> _shuffled(List<Exercise> list) {
    final copy = List<Exercise>.from(list)..shuffle(_rng);
    return copy;
  }

  /// Три отвлекающих варианта (ответы других карт) для MultipleChoice/TrueFalse.
  List<String> distractors(Exercise ex, List<WordCard> pool, {int n = 3}) {
    final correct = ex.answer.trim().toLowerCase();
    final options = <String>{};
    final shuffled = List<WordCard>.from(pool)..shuffle(_rng);
    for (final c in shuffled) {
      final v = ex.reversed ? c.front : c.back;
      if (v.trim().isEmpty) continue;
      if (v.trim().toLowerCase() == correct) continue;
      options.add(v);
      if (options.length >= n) break;
    }
    return options.toList();
  }

  /// Случайный «неправильный» перевод для TrueFalse (или null, если нет пары).
  String? wrongAnswer(Exercise ex, List<WordCard> pool) {
    final d = distractors(ex, pool, n: 1);
    return d.isEmpty ? null : d.first;
  }
}

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
