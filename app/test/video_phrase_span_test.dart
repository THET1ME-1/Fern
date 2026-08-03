import 'package:flutter_test/flutter_test.dart';

import 'package:fern/video/subtitle.dart';

/// Границы выделенной фразы внутри реплики.
///
/// В разборе видео слово можно зажать и протянуть — как в читалке книг. Кнопка
/// озвучки в пузыре должна играть ровно выделенный кусок, а не всю реплику,
/// поэтому фразе нужны свои начало и конец.
void main() {
  SubLine line() => SubLine(
        start: const Duration(seconds: 10),
        end: const Duration(seconds: 14),
        text: 'I gave up on the idea',
        words: const [
          SubWord('I', Duration(seconds: 10)),
          SubWord('gave', Duration(milliseconds: 10500)),
          SubWord('up', Duration(seconds: 11)),
          SubWord('on', Duration(milliseconds: 11500)),
          SubWord('the', Duration(seconds: 12)),
          SubWord('idea', Duration(milliseconds: 12500)),
        ],
      );

  test('фраза играет от первого слова до конца последнего', () {
    final span = line().phraseSpan('gave up on');
    expect(span, isNotNull);
    expect(span!.$1, const Duration(milliseconds: 10500));
    // Конец «on» — это начало следующего слова, «the».
    expect(span.$2, const Duration(seconds: 12));
  });

  test('фраза до конца реплики упирается в её конец', () {
    final span = line().phraseSpan('the idea');
    expect(span!.$2, const Duration(seconds: 14),
        reason: 'после последнего слова следующего нет');
  });

  test('одно слово тоже даёт границы', () {
    final span = line().phraseSpan('up');
    expect(span!.$1, const Duration(seconds: 11));
    expect(span.$2, const Duration(milliseconds: 11500));
  });

  test('пунктуация и регистр не мешают', () {
    final span = line().phraseSpan('  Gave up,  ');
    expect(span!.$1, const Duration(milliseconds: 10500));
    expect(span.$2, const Duration(milliseconds: 11500));
  });

  test('слов вне реплики нет — границ тоже', () {
    expect(line().phraseSpan('совсем другое'), isNull);
    expect(line().phraseSpan('   '), isNull);
  });

  test('реплика без пословной разметки границ не даёт', () {
    const bare = SubLine(
      start: Duration(seconds: 1),
      end: Duration(seconds: 3),
      text: 'no timings here',
    );
    expect(bare.phraseSpan('no timings'), isNull,
        reason: 'играть по словам нечем — пузырь возьмёт всю реплику');
  });
}
