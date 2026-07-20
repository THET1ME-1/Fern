import 'package:flutter_test/flutter_test.dart';
import 'package:fern/models/word_card.dart';
import 'package:fern/services/reading_warmup.dart';

/// Разминка перед чтением: короткая сессия по словам, которые встретятся на
/// ближайших страницах.
///
/// Смысл в замыкании памяти на живом тексте: повторил слово за пять минут до
/// того, как встретил его в книге, — и оно закрепилось контекстом, а не
/// карточкой. Обычному SRS такое недоступно, у него нет книги.
void main() {
  WordCard card(String front, {double stability = 10, int elapsedDays = 1}) {
    final now = DateTime.now();
    return WordCard(
      id: front,
      deckId: 'd',
      front: front,
      back: 'перевод',
      review: ReviewState(
        stability: stability,
        difficulty: 5,
        state: FsrsState.review,
        due: now,
        lastReview: now.subtract(Duration(days: elapsedDays)),
      ),
    );
  }

  test('Берутся только слова с ближайших страниц', () {
    final picked = ReadingWarmup.pick(
      [card('fox'), card('table'), card('run')],
      {'fox', 'run'},
      'en',
    );
    expect(picked.map((c) => c.front), containsAll(['fox', 'run']));
    expect(picked.map((c) => c.front), isNot(contains('table')));
  });

  test('Впереди идут слова, которые вот-вот забудутся', () {
    // Одинаковый срок с прошлого повтора, разная прочность: слабое слово
    // вспоминается хуже, ему и место в начале разминки.
    final picked = ReadingWarmup.pick(
      [
        card('strong', stability: 200, elapsedDays: 5),
        card('weak', stability: 3, elapsedDays: 5),
      ],
      {'strong', 'weak'},
      'en',
    );
    expect(picked.first.front, 'weak');
  });

  test('Разминка остаётся короткой', () {
    final many = [for (var i = 0; i < 50; i++) card('word$i')];
    final picked = ReadingWarmup.pick(
      many,
      {for (var i = 0; i < 50; i++) 'word$i'},
      'en',
      limit: 12,
    );
    expect(picked.length, 12);
  });

  test('Словоформы засчитываются по основе', () {
    // В книге впереди «foxes», в словаре карточка «fox» — это одно слово.
    final picked = ReadingWarmup.pick([card('fox')], {'fox'}, 'en');
    expect(picked, hasLength(1));
  });

  test('Без открытой книги разминки нет', () {
    expect(ReadingWarmup.pick([card('fox')], {}, 'en'), isEmpty);
  });
}
