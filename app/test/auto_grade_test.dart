import 'package:flutter_test/flutter_test.dart';

import 'package:fern/models/review_event.dart';
import 'package:fern/models/word_card.dart';
import 'package:fern/services/auto_grade.dart';

ReviewEvent _ev(int ms, {int grade = 3}) => ReviewEvent(
      cardId: 'c',
      ts: 0,
      grade: grade,
      elapsedDays: 1,
      stateBefore: 2,
      answerMs: ms,
    );

void main() {
  group('пороги', () {
    const g = AutoGrade(medianMs: 4000);

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
      const slow = AutoGrade(medianMs: 9000);
      expect(g.recalled(7000), Rating.hard,
          reason: 'для быстрого человека 7 с — долго');
      expect(slow.recalled(7000), Rating.good,
          reason: 'для медленного 7 с — обычный темп');
    });
  });

  group('набранный ответ', () {
    const g = AutoGrade(medianMs: 4000);

    test('точное попадание быстро — «легко»', () {
      expect(g.typed(TypedMatch.exact, 1500), Rating.easy);
    });

    test('опечатка — «трудно» даже при быстром вводе', () {
      expect(g.typed(TypedMatch.typo, 1200), Rating.hard);
    });

    test('промах — «не помню»', () {
      expect(g.typed(TypedMatch.wrong, 1200), Rating.again);
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
  });

  group('личная медиана из истории', () {
    test('считается по верным ответам с известным временем', () {
      final events = [
        for (var i = 0; i < 40; i++) _ev(3000),
        for (var i = 0; i < 40; i++) _ev(5000),
        // Промахи в темп не входят: там время — это ступор, а не норма.
        for (var i = 0; i < 40; i++) _ev(30000, grade: 1),
      ];
      expect(AutoGrade.fromEvents(events).medianMs, inInclusiveRange(3000, 5000));
    });

    test('пока данных мало — фиксированный порог, а не случайная медиана', () {
      final events = [_ev(900), _ev(1100)];
      expect(AutoGrade.fromEvents(events).medianMs, AutoGrade.fallbackMedianMs);
      expect(AutoGrade.fromEvents(const []).medianMs, AutoGrade.fallbackMedianMs);
    });

    test('события без замера времени пропускаются', () {
      final events = [
        for (var i = 0; i < 40; i++)
          const ReviewEvent(
              cardId: 'c', ts: 0, grade: 3, elapsedDays: 1, stateBefore: 2),
      ];
      expect(AutoGrade.fromEvents(events).medianMs, AutoGrade.fallbackMedianMs);
    });
  });

  group('темп считается по свежим ответам', () {
    test('старые ответы не тянут медиану за собой', () {
      // Человек разогнался: раньше отвечал за 8 с, теперь за 2 с.
      final old = [for (var i = 0; i < 200; i++) 8000];
      final recent = [for (var i = 0; i < 40; i++) 2000];
      expect(AutoGrade.fromSamples([...old, ...recent]).medianMs, 8000,
          reason: 'вся история целиком помнит давно ушедший темп');
      expect(AutoGrade.fromSamples(recent).medianMs, 2000);
    });
  });
}
