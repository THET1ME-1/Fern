import '../models/review_event.dart';
import '../models/word_card.dart';
import '../study/study_models.dart';
import '../utils/text_distance.dart';

/// Насколько набранный ответ совпал с эталоном.
enum TypedMatch {
  /// Слово в слово (с точностью до регистра и пробелов).
  exact,

  /// Одна описка — слово человек знает, рука промахнулась.
  typo,

  /// Не тот ответ.
  wrong,
}

/// Оценка набранного ответа: точное попадание / описка / промах.
///
/// Прежний `answerMatches` отвечал только «да/нет», и описка засчитывалась как
/// полный успех. Для автооценки разница важна: описка — это «трудно», а не
/// «хорошо».
TypedMatch typedQuality(String input, String expected) {
  final a = normalizeAnswer(input);
  final b = normalizeAnswer(expected);
  if (a.isEmpty) return TypedMatch.wrong;
  if (a == b) return TypedMatch.exact;

  // В переводе часто несколько вариантов через запятую — годится любой.
  var typo = false;
  for (final part in b.split(RegExp(r'[,;/]'))) {
    final p = part.trim();
    if (p.isEmpty) continue;
    if (a == p) return TypedMatch.exact;
    if (p.length > 3 && levenshtein(a, p) <= 1) typo = true;
  }
  if (typo) return TypedMatch.typo;
  if (b.length > 3 && levenshtein(a, b) <= 1) return TypedMatch.typo;
  return TypedMatch.wrong;
}

/// Чем человек отдаёт ответ. Времена этих двух способов несопоставимы:
/// напечатать слово на телефоне — это секунды моторики поверх вспоминания.
enum AnswerPace { tap, typing }

/// Один замер из журнала: вид упражнения (индекс `ExerciseKind`) и время.
typedef AnswerSample = ({int kind, int ms});

/// К какому темпу относится упражнение — и относится ли вообще.
///
/// `null` значит «в личный темп не входит». Берём только те виды, которые
/// автооценка СУДИТ: медиана обязана описывать ровно ту популяцию времён, к
/// которой применяются пороги. «Выбери вариант» и «собери слово» оцениваются
/// верно/неверно, и подмешивать их темп — значит мерить одно линейкой другого.
AnswerPace? paceOf(ExerciseKind kind) => switch (kind) {
      ExerciseKind.flip => AnswerPace.tap,
      ExerciseKind.type || ExerciseKind.spell || ExerciseKind.cloze =>
        AnswerPace.typing,
      ExerciseKind.choose ||
      ExerciseKind.trueFalse ||
      ExerciseKind.listen ||
      ExerciseKind.assemble ||
      ExerciseKind.oddOne =>
        null,
    };

/// Ставит оценку FSRS вместо самооценки «на глаз».
///
/// Человек плохо судит себя сам: вспомнил с трудом за восемь секунд — и жмёт
/// «хорошо», потому что ответ-то верный. Время ответа врёт куда реже: заминка
/// перед ответом и есть слабость следа памяти.
///
/// Пороги ЛИЧНЫЕ — доля от медианы собственных верных ответов. Абсолютные
/// секунды сравнивать бессмысленно: у одного человека обычный темп две
/// секунды, у другого семь, и одна и та же пауза значит разное.
///
/// Медиан ДВЕ, по [AnswerPace]. С одной общей набор текста раз за разом
/// получал «трудно»: тапов в сессии больше, они быстрее, медиану делали они —
/// и напечатать слово быстрее неё было физически невозможно. Идеальные ответы
/// роняли карточку в пиявки.
class AutoGrade {
  /// Медиана времени верного ответа тапом (флип).
  final int tapMedianMs;

  /// Медиана времени верного набранного ответа.
  final int typingMedianMs;

  const AutoGrade({required this.tapMedianMs, required this.typingMedianMs});

  /// Пороги до того, как накопилась личная история.
  const AutoGrade.fallback()
      : tapMedianMs = fallbackTapMs,
        typingMedianMs = fallbackTypingMs;

  /// Пороги, пока личной истории не набралось.
  ///
  /// Четыре секунды — спокойное вспоминание знакомого слова. На набор к нему
  /// добавляется сам ввод: слово из семи букв на телефонной клавиатуре — это
  /// ещё несколько секунд, и мерить его четырьмя значит с первого же дня
  /// раздавать «трудно» за верные ответы.
  static const int fallbackTapMs = 4000;
  static const int fallbackTypingMs = 9000;

  /// Сколько верных ответов с замером нужно, чтобы медиана что-то значила.
  static const int _minSamples = 20;

  /// Быстрее этой доли медианы — ответ пришёл сразу, без перебора.
  static const double _fastRatio = 0.6;

  /// Медленнее этой доли — вспоминал, а не вспомнил.
  static const double _slowRatio = 1.6;

  /// Личный темп по истории повторов. Берём только верные ответы: время промаха
  /// — это ступор и разглядывание, к обычному темпу отношения не имеет.
  factory AutoGrade.fromEvents(Iterable<ReviewEvent> events) =>
      AutoGrade.fromSamples([
        for (final e in events)
          if (e.recalled &&
              e.answerMs != null &&
              e.answerMs! > 0 &&
              e.kind != null)
            (kind: e.kind!, ms: e.answerMs!),
      ]);

  /// Медианы по готовому набору замеров (уже отфильтрованному).
  ///
  /// Отдельно от [fromEvents], потому что темп надо считать по СВЕЖИМ ответам:
  /// человек за полгода разгоняется, и медиана по всей истории описывает того,
  /// кем он был, а не кто он сейчас. Сколько ответов брать — решает вызывающий.
  factory AutoGrade.fromSamples(Iterable<AnswerSample> samples) {
    final byPace = {AnswerPace.tap: <int>[], AnswerPace.typing: <int>[]};
    for (final s in samples) {
      if (s.kind < 0 || s.kind >= ExerciseKind.values.length) continue;
      final pace = paceOf(ExerciseKind.values[s.kind]);
      if (pace != null) byPace[pace]!.add(s.ms);
    }
    return AutoGrade(
      tapMedianMs: _median(byPace[AnswerPace.tap]!, fallbackTapMs),
      typingMedianMs: _median(byPace[AnswerPace.typing]!, fallbackTypingMs),
    );
  }

  /// Медиана, если замеров хватает; иначе — фиксированный порог. Своя медиана
  /// у каждого класса появляется независимо: печатают заметно реже, чем тапают.
  static int _median(List<int> samples, int fallback) {
    if (samples.length < _minSamples) return fallback;
    samples.sort();
    return samples[samples.length ~/ 2];
  }

  int medianFor(AnswerPace pace) =>
      pace == AnswerPace.typing ? typingMedianMs : tapMedianMs;

  /// Оценка для «вспомнил» по времени ответа.
  Rating recalled(int answerMs, {AnswerPace pace = AnswerPace.tap}) {
    final median = medianFor(pace);
    if (answerMs <= median * _fastRatio) return Rating.easy;
    if (answerMs <= median * _slowRatio) return Rating.good;
    return Rating.hard;
  }

  /// Оценка набранного ответа: описка снижает до «трудно» при любом темпе —
  /// рука знает слово хуже, чем кажется.
  Rating typed(TypedMatch match, int answerMs) => switch (match) {
        TypedMatch.wrong => Rating.again,
        TypedMatch.typo => Rating.hard,
        TypedMatch.exact => recalled(answerMs, pace: AnswerPace.typing),
      };
}
