import 'package:flutter_test/flutter_test.dart';
import 'package:fern/models/word_card.dart';
import 'package:fern/study/study_models.dart';

/// Разминка перед чтением даёт слова ближайших страниц — как правило, ещё не
/// назревшие: в том и смысл, повторить до встречи в тексте. Значит сессия
/// обязана прогнать именно их, а не отфильтровать по сроку и показать
/// «ничего не назрело».
void main() {
  final now = DateTime.now();

  WordCard notDue(String front) => WordCard(
        id: front,
        deckId: 'd',
        front: front,
        back: 'перевод',
        review: ReviewState(
          stability: 12,
          difficulty: 5,
          state: FsrsState.review,
          lastReview: now.subtract(const Duration(days: 1)),
          due: now.add(const Duration(days: 6)),
        ),
      );

  test('Разминка прогоняет неназревшие слова, а не отбрасывает их', () {
    final cards = [notDue('fox'), notDue('river'), notDue('stone')];
    final queue = SessionBuilder().build(StudyMode.revive, cards, now);
    expect(queue, hasLength(3));
    expect(queue.map((e) => e.card.front), containsAll(['fox', 'river']));
  });

  test('Режим «Учить» такие слова отбрасывает — поэтому он тут не годится', () {
    final queue = SessionBuilder().build(StudyMode.learn, [notDue('fox')], now);
    expect(queue, isEmpty);
  });
}
