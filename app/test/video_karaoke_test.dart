import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fern/video/karaoke.dart';
import 'package:fern/video/subtitle.dart';

/// Караоке в разборе видео: какая реплика звучит, какое слово внутри неё и как
/// считается позиция между тиками плеера.
///
/// Экран видео в тестах не поднять (там вебвью плеера), поэтому вся логика
/// вынесена в модель и в [PlaybackClock] — проверяется здесь.
void main() {
  /// Дорожка, как её отдаёт распознаватель речи YouTube: реплики наезжают,
  /// конец каждой совпадает с началом той, что через одну.
  List<SubLine> rolling(List<String> texts, {int step = 2000}) {
    final lines = <SubLine>[];
    for (var i = 0; i < texts.length; i++) {
      final start = Duration(milliseconds: i * step);
      final end = Duration(milliseconds: (i + 2) * step);
      final words = <SubWord>[];
      final parts = texts[i].split(' ');
      for (var j = 0; j < parts.length; j++) {
        words.add(SubWord(
          parts[j],
          start + Duration(milliseconds: (step ~/ parts.length) * j),
        ));
      }
      lines.add(SubLine(start: start, end: end, text: texts[i], words: words));
    }
    return lines;
  }

  group('активная реплика', () {
    final lines = rolling([
      'We are no strangers to',
      'love you know the rules and so do',
      'I feel commitments from what I am',
      'thinking of you would not get this',
      'from any other guy',
    ]);

    test('до первой реплики активной нет', () {
      expect(SubLine.activeAt(lines, const Duration(milliseconds: -1)), -1);
    });

    test('на наезжающих репликах берётся последняя начавшаяся', () {
      // 2,5 с: звучит вторая (начало 2 с), хотя первая по своему концу (4 с)
      // ещё «идёт». Раньше поиск по отрезку отдавал первую.
      expect(SubLine.activeAt(lines, const Duration(milliseconds: 2500)), 1);
      expect(SubLine.activeAt(lines, const Duration(milliseconds: 4000)), 2);
    });

    test('ни одна реплика не пропускается и порядок только вперёд', () {
      final seen = <int>[];
      var active = -1;
      for (var ms = 0; ms <= 12000; ms += 100) {
        final found = SubLine.activeAt(lines, Duration(milliseconds: ms));
        if (found != active) {
          expect(found, greaterThan(active), reason: 'подсветка не едет назад');
          active = found;
          seen.add(found);
        }
      }
      expect(seen, [0, 1, 2, 3, 4], reason: 'каждая реплика ровно один раз');
    });

    test('после конца дорожки держится последняя', () {
      expect(SubLine.activeAt(lines, const Duration(minutes: 5)), 4);
    });
  });

  group('слово внутри реплики', () {
    const line = SubLine(
      start: Duration(seconds: 10),
      end: Duration(seconds: 14),
      text: 'So, I have a fringe. So, this is it',
      words: [
        SubWord('So,', Duration(seconds: 10)),
        SubWord('I', Duration(milliseconds: 10400)),
        SubWord('have a', Duration(milliseconds: 10700)),
        SubWord('fringe.', Duration(milliseconds: 11200)),
        SubWord('So,', Duration(milliseconds: 11900)),
        SubWord('this is it', Duration(milliseconds: 12400)),
      ],
    );

    test('звучит последнее начавшееся слово', () {
      expect(line.wordAt(const Duration(seconds: 9)), -1);
      expect(line.wordAt(const Duration(milliseconds: 10500)), 1);
      expect(line.wordAt(const Duration(milliseconds: 13000)), 5);
    });

    test('границы слов ищутся по порядку, а не по всему тексту', () {
      final ranges = line.wordCharRanges();
      expect(ranges.length, line.words.length);
      // Первое «So,» — в начале, второе — своё, а не то же самое.
      expect(ranges[0], (0, 3));
      expect(ranges[4]!.$1, greaterThan(ranges[3]!.$2));
      expect(line.text.substring(ranges[4]!.$1, ranges[4]!.$2), 'So,');
      // Кусок разметки может нести два слова сразу.
      expect(line.text.substring(ranges[2]!.$1, ranges[2]!.$2), 'have a');
      expect(line.text.substring(ranges[5]!.$1, ranges[5]!.$2), 'this is it');
    });

    test('слово не из текста границ не даёт', () {
      const odd = SubLine(
        start: Duration.zero,
        end: Duration(seconds: 2),
        text: 'hello there',
        words: [SubWord('hello', Duration.zero), SubWord('world', Duration(seconds: 1))],
      );
      expect(odd.wordCharRanges(), [(0, 5), null]);
    });

    test('реплика без разметки: ни слова, ни границ', () {
      const bare = SubLine(
        start: Duration.zero,
        end: Duration(seconds: 2),
        text: '[music]',
      );
      expect(bare.wordAt(const Duration(seconds: 1)), -1);
      expect(bare.wordCharRanges(), isEmpty);
    });
  });

  group('часы воспроизведения', () {
    test('на паузе стоят, на игре идут', () {
      final clock = PlaybackClock();
      clock.seek(const Duration(seconds: 5), Duration.zero);
      expect(clock.positionAt(const Duration(seconds: 3)), const Duration(seconds: 5));

      clock.setPlaying(true, const Duration(seconds: 3));
      expect(clock.positionAt(const Duration(seconds: 4)), const Duration(seconds: 6));

      clock.setPlaying(false, const Duration(seconds: 4));
      expect(clock.positionAt(const Duration(seconds: 9)), const Duration(seconds: 6));
    });

    test('скорость 0,5 замедляет и часы', () {
      final clock = PlaybackClock();
      clock.setPlaying(true, Duration.zero);
      clock.setRate(0.5, Duration.zero);
      expect(clock.positionAt(const Duration(seconds: 4)), const Duration(seconds: 2));
    });

    test('мелкое расхождение подтягивается плавно, а не рывком', () {
      final clock = PlaybackClock();
      clock.setPlaying(true, Duration.zero);
      // Плеер отстал на 100 мс — это дрожь getCurrentTime, не перемотка.
      final jumped = clock.sync(
        const Duration(milliseconds: 900),
        const Duration(milliseconds: 1000),
      );
      expect(jumped, isFalse);
      final pos = clock.positionAt(const Duration(milliseconds: 1000));
      expect(pos, lessThan(const Duration(milliseconds: 1000)));
      expect(pos, greaterThan(const Duration(milliseconds: 970)),
          reason: 'назад тянемся осторожно, иначе плашка откатывается');
    });

    test('перемотка — сразу, без плавного схождения', () {
      final clock = PlaybackClock();
      clock.setPlaying(true, Duration.zero);
      final jumped = clock.sync(
        const Duration(minutes: 12),
        const Duration(milliseconds: 1000),
      );
      expect(jumped, isTrue);
      expect(clock.positionAt(const Duration(milliseconds: 1000)),
          const Duration(minutes: 12));
    });

    test('порог перемотки считается в обе стороны', () {
      final clock = PlaybackClock();
      clock.setPlaying(true, Duration.zero);
      expect(
        clock.sync(const Duration(milliseconds: 400), const Duration(seconds: 1)),
        isTrue,
        reason: 'откат на 600 мс — это перемотка назад',
      );
    });
  });

  group('плашка-бегунок', () {
    const line = SubLine(
      start: Duration.zero,
      end: Duration(seconds: 4),
      text: 'I need to do my hair',
      words: [
        SubWord('I', Duration.zero),
        SubWord('need', Duration(milliseconds: 400)),
        SubWord('to', Duration(milliseconds: 900)),
        SubWord('do', Duration(milliseconds: 1300)),
        SubWord('my', Duration(milliseconds: 1700)),
        SubWord('hair', Duration(milliseconds: 2100)),
      ],
    );

    Future<RenderParagraph> pump(WidgetTester tester, {(int, int)? spoken}) async {
      final travel = AnimationController(
        vsync: const TestVSync(),
        duration: const Duration(milliseconds: 220),
      );
      addTearDown(travel.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            child: KaraokeLine(
              line: line,
              style: const TextStyle(fontSize: 18),
              active: true,
              spoken: spoken,
              previous: null,
              travel: travel,
              pillColor: const Color(0xFF005236),
              spokenColor: const Color(0xFFAAF2CB),
              known: const {},
              sessionAdded: const {},
              highlightVersion: 0,
              knownColor: const Color(0xFFA5CDDE),
              addedColor: const Color(0xFFA5CDDE),
              onWord: (_) {},
              onPhrase: (_) {},
            ),
          ),
        ),
      ));
      return tester.renderObject<RenderParagraph>(find.byType(RichText));
    }

    testWidgets('плашка встаёт на слово и едет вправо по реплике',
        (tester) async {
      final ranges = line.wordCharRanges();
      final render = await pump(tester, spoken: ranges[5]);
      expect(tester.takeException(), isNull);

      final my = pillRect(render, to: ranges[4]!, travel: 1)!;
      final hair = pillRect(render, to: ranges[5]!, travel: 1)!;
      expect(hair.rect.left, greaterThan(my.rect.left),
          reason: 'слова идут слева направо');
      expect(hair.rect.top, my.rect.top, reason: 'одна строка — одна высота');
      expect(hair.rect.width, greaterThan(my.rect.width),
          reason: '«hair» шире, чем «my»');
    });

    testWidgets('на середине переезда плашка между словами', (tester) async {
      final ranges = line.wordCharRanges();
      final render = await pump(tester, spoken: ranges[5]);
      final from = pillRect(render, to: ranges[4]!, travel: 1)!.rect;
      final to = pillRect(render, to: ranges[5]!, travel: 1)!.rect;
      final mid = pillRect(render, from: ranges[4], to: ranges[5]!, travel: 0.5)!;
      expect(mid.rect.left, greaterThan(from.left));
      expect(mid.rect.left, lessThan(to.left));
      expect(mid.opacity, 1);
    });

    testWidgets('первое слово реплики проявляется на месте', (tester) async {
      final ranges = line.wordCharRanges();
      final render = await pump(tester, spoken: ranges[0]);
      final at = pillRect(render, to: ranges[0]!, travel: 0.4)!;
      expect(at.opacity, lessThan(1), reason: 'проявление, а не переезд');
      expect(at.rect, pillRect(render, to: ranges[0]!, travel: 1)!.rect);
    });
  });
}
