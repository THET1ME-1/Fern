import 'package:flutter_test/flutter_test.dart';

import 'package:fern/models/review_event.dart';
import 'package:fern/models/word_card.dart';
import 'package:fern/services/auto_grade.dart';
import 'package:fern/study/study_models.dart';

ReviewEvent _ev(int ms,
        {int grade = 3, ExerciseKind kind = ExerciseKind.flip}) =>
    ReviewEvent(
      cardId: 'c',
      ts: 0,
      grade: grade,
      elapsedDays: 1,
      stateBefore: 2,
      answerMs: ms,
      kind: kind.index,
    );

/// Замеры одного вида упражнения — как их отдаёт журнал.
List<AnswerSample> _samples(int n, int ms, ExerciseKind kind) =>
    [for (var i = 0; i < n; i++) (kind: kind.index, ms: ms)];

void main() {
  group('пороги', () {
    const g = AutoGrade(tapMedianMs: 4000, typingMedianMs: 4000);

    test('быстрый ответ — «легко»', () {
      expect(g.recalled(1500), Rating.easy);
    });

    test('ответ около личной медианы — «хорошо»', () {
      expect(g.recalled(4000), Rating.good);
      expect(g.recalled(5500), Rating.good);
    });

    test('долгое вспоминание — «трудно»', () {
      expect(g.recalled(12000), Rating.hard);
    });

    test('пороги личные: одно и то же время у разных людей судится по-разному',
        () {
      const slow = AutoGrade(tapMedianMs: 9000, typingMedianMs: 9000);
      expect(g.recalled(7000), Rating.hard,
          reason: 'для быстрого человека 7 с — долго');
      expect(slow.recalled(7000), Rating.good,
          reason: 'для медленного 7 с — обычный темп');
    });
  });

  group('набор и тап судятся по разным меркам', () {
    // Человек тапает по вариантам за 2 с, а печатает то же слово за 7 с —
    // на сам набор уходят секунды, знание тут ни при чём.
    const g = AutoGrade(tapMedianMs: 2000, typingMedianMs: 7000);

    test('набранное слово в обычном для набора темпе — «хорошо»', () {
      expect(g.typed(TypedMatch.exact, 7000), Rating.good,
          reason: 'по мерке тапов 7 с — это «трудно», и карточка зря '
              'деградировала бы в пиявку');
    });

    test('набранное слово заметно быстрее своей медианы — «легко»', () {
      expect(g.typed(TypedMatch.exact, 3500), Rating.easy);
    });

    test('флип судится по темпу тапов', () {
      expect(g.recalled(7000), Rating.hard);
      expect(g.recalled(7000, pace: AnswerPace.typing), Rating.good);
    });
  });

  group('личный темп по журналу', () {
    test('печать не меряется медианой тапов', () {
      // Типичная сессия: тапов много и они быстрые, печати мало.
      final g = AutoGrade.fromSamples([
        ..._samples(60, 2000, ExerciseKind.flip),
        ..._samples(25, 7000, ExerciseKind.type),
      ]);
      expect(g.tapMedianMs, 2000);
      expect(g.typingMedianMs, 7000);
      expect(g.typed(TypedMatch.exact, 7000), Rating.good);
    });

    test('своя медиана появляется только у набравшего класса', () {
      // Тапов достаточно, набора — всего пара раз.
      final g = AutoGrade.fromSamples([
        ..._samples(40, 2000, ExerciseKind.flip),
        ..._samples(2, 12000, ExerciseKind.type),
      ]);
      expect(g.tapMedianMs, 2000);
      expect(g.typingMedianMs, AutoGrade.fallbackTypingMs,
          reason: 'две случайных печати — не темп');
    });

    test('виды, которые судит автооценка, считаются вместе', () {
      final g = AutoGrade.fromSamples([
        ..._samples(10, 6000, ExerciseKind.type),
        ..._samples(15, 6000, ExerciseKind.spell),
      ]);
      expect(g.typingMedianMs, 6000);
    });

    test('клоуз в темп набора не входит', () {
      // Клоуз набирают с клавиатуры, но оценку он ставит сам («верно/неверно»),
      // а время меряет до тапа «Продолжить» — вместе с чтением ответа.
      final g = AutoGrade.fromSamples(_samples(40, 30000, ExerciseKind.cloze));
      expect(g.typingMedianMs, AutoGrade.fallbackTypingMs,
          reason: 'иначе полминуты на чтение объяснения станут нормой набора, '
              'и пятнадцать секунд на слово получат «легко»');
    });

    test('виды без автооценки в темп не входят', () {
      // «Выбери вариант» и «собери слово» оцениваются верно/неверно, и темп
      // у них свой: тап по готовому варианту быстрее флипа, сборка — дольше.
      final g = AutoGrade.fromSamples([
        ..._samples(40, 500, ExerciseKind.choose),
        ..._samples(40, 20000, ExerciseKind.assemble),
      ]);
      expect(g.tapMedianMs, AutoGrade.fallbackTapMs);
      expect(g.typingMedianMs, AutoGrade.fallbackTypingMs);
    });

    test('промахи в темп не входят: там ступор, а не норма', () {
      final events = [
        for (var i = 0; i < 40; i++) _ev(3000),
        for (var i = 0; i < 40; i++) _ev(30000, grade: 1),
      ];
      expect(AutoGrade.fromEvents(events).tapMedianMs, 3000);
    });

    test('события без замера времени пропускаются', () {
      final events = [
        for (var i = 0; i < 40; i++)
          const ReviewEvent(
              cardId: 'c', ts: 0, grade: 3, elapsedDays: 1, stateBefore: 2),
      ];
      expect(AutoGrade.fromEvents(events).tapMedianMs, AutoGrade.fallbackTapMs);
    });

    test('события старых версий без вида упражнения пропускаются', () {
      // До миграции вид не писался — чем отвечали, неизвестно, и брать такое
      // время в любую из двух выборок значит вернуть ту же кашу.
      final events = [
        for (var i = 0; i < 40; i++)
          const ReviewEvent(
              cardId: 'c',
              ts: 0,
              grade: 3,
              elapsedDays: 1,
              stateBefore: 2,
              answerMs: 3000),
      ];
      final g = AutoGrade.fromEvents(events);
      expect(g.tapMedianMs, AutoGrade.fallbackTapMs);
      expect(g.typingMedianMs, AutoGrade.fallbackTypingMs);
    });

    test('порог по умолчанию для набора выше, чем для тапа', () {
      expect(AutoGrade.fallbackTypingMs,
          greaterThan(AutoGrade.fallbackTapMs));
    });
  });

  group('качество набранного ответа', () {
    test('совпадение, опечатка и промах различаются', () {
      expect(typedQuality('дом', 'дом'), TypedMatch.exact);
      expect(typedQuality('Дом ', 'дом'), TypedMatch.exact);
      expect(typedQuality('домн', 'дом'), TypedMatch.wrong,
          reason: 'короткие слова опечаток не прощают');
      expect(typedQuality('велосипет', 'велосипед'), TypedMatch.typo);
      expect(typedQuality('кот', 'велосипед'), TypedMatch.wrong);
    });

    test('вариант перевода через запятую — точное попадание', () {
      expect(typedQuality('машина', 'автомобиль, машина'), TypedMatch.exact);
    });

    test('опечатка — «трудно» даже при быстром вводе', () {
      const g = AutoGrade(tapMedianMs: 4000, typingMedianMs: 7000);
      expect(g.typed(TypedMatch.typo, 1200), Rating.hard);
      expect(g.typed(TypedMatch.wrong, 1200), Rating.again);
    });
  });

  group('темп считается по свежим ответам', () {
    test('старые ответы не тянут медиану за собой', () {
      // Человек разогнался: раньше отвечал за 8 с, теперь за 2 с.
      final old = _samples(200, 8000, ExerciseKind.flip);
      final recent = _samples(40, 2000, ExerciseKind.flip);
      expect(AutoGrade.fromSamples([...old, ...recent]).tapMedianMs, 8000,
          reason: 'вся история целиком помнит давно ушедший темп');
      expect(AutoGrade.fromSamples(recent).tapMedianMs, 2000);
    });
  });
}
