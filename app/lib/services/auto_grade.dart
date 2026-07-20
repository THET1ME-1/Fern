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

/// Ставит оценку FSRS вместо самооценки «на глаз».
///
/// Человек плохо судит себя сам: вспомнил с трудом за восемь секунд — и жмёт
/// «хорошо», потому что ответ-то верный. Время ответа врёт куда реже: заминка
/// перед ответом и есть слабость следа памяти.
///
/// Пороги ЛИЧНЫЕ — доля от медианы собственных верных ответов ([medianMs]).
/// Абсолютные секунды сравнивать бессмысленно: у одного человека обычный темп
/// две секунды, у другого семь, и одна и та же пауза значит разное.
class AutoGrade {
  /// Медиана времени верного ответа этого человека.
  final int medianMs;

  const AutoGrade({required this.medianMs});

  /// Порог, пока личной истории не набралось. Четыре секунды — спокойное
  /// вспоминание знакомого слова.
  static const int fallbackMedianMs = 4000;

  /// Сколько верных ответов с замером нужно, чтобы медиана что-то значила.
  static const int _minSamples = 20;

  /// Быстрее этой доли медианы — ответ пришёл сразу, без перебора.
  static const double _fastRatio = 0.6;

  /// Медленнее этой доли — вспоминал, а не вспомнил.
  static const double _slowRatio = 1.6;

  /// Личный темп по истории повторов. Берём только верные ответы: время промаха
  /// — это ступор и разглядывание, к обычному темпу отношения не имеет.
  factory AutoGrade.fromEvents(Iterable<ReviewEvent> events) => AutoGrade.fromSamples([
        for (final e in events)
          if (e.recalled && e.answerMs != null && e.answerMs! > 0) e.answerMs!,
      ]);

  /// Медиана по готовому набору времён (уже отфильтрованному).
  ///
  /// Отдельно от [fromEvents], потому что темп надо считать по СВЕЖИМ ответам:
  /// человек за полгода разгоняется, и медиана по всей истории описывает того,
  /// кем он был, а не кто он сейчас. Сколько ответов брать — решает вызывающий.
  factory AutoGrade.fromSamples(Iterable<int> answerTimes) {
    final samples = answerTimes.toList()..sort();
    if (samples.length < _minSamples) {
      return const AutoGrade(medianMs: fallbackMedianMs);
    }
    return AutoGrade(medianMs: samples[samples.length ~/ 2]);
  }

  /// Оценка для «вспомнил» (флип, выбор варианта) по времени ответа.
  Rating recalled(int answerMs) {
    if (answerMs <= medianMs * _fastRatio) return Rating.easy;
    if (answerMs <= medianMs * _slowRatio) return Rating.good;
    return Rating.hard;
  }

  /// Оценка набранного ответа: описка снижает до «трудно» при любом темпе —
  /// рука знает слово хуже, чем кажется.
  Rating typed(TypedMatch match, int answerMs) => switch (match) {
        TypedMatch.wrong => Rating.again,
        TypedMatch.typo => Rating.hard,
        TypedMatch.exact => recalled(answerMs),
      };
}
