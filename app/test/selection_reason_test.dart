import 'package:flutter_test/flutter_test.dart';

import 'package:fern/models/fsrs.dart';
import 'package:fern/models/word_card.dart';
import 'package:fern/services/lemmatizer.dart';
import 'package:fern/services/link_propagation.dart';
import 'package:fern/study/study_models.dart';

final _now = DateTime(2026, 7, 20, 12);

WordCard _fresh(String id, String front) =>
    WordCard(id: id, deckId: 'd1', front: front, back: 'п$id');

/// Просроченный повтор: последний раз смотрели давно, срок уже прошёл.
WordCard _overdue(String id, String front, {double stability = 10}) => WordCard(
      id: id,
      deckId: 'd1',
      front: front,
      back: 'п$id',
      review: ReviewState(
        stability: stability,
        difficulty: 5,
        state: FsrsState.review,
        reps: 4,
        lastReview: _now.subtract(Duration(days: stability.round() * 2)),
        due: _now.subtract(const Duration(days: 1)),
      ),
    );

Exercise _find(List<Exercise> q, String id) =>
    q.firstWhere((e) => e.card.id == id);

void main() {
  group('Причина попадания в очередь', () {
    test('новое слово помечено как новое, просроченный повтор — как срок', () {
      final queue = SessionBuilder().build(
        StudyMode.flashcards,
        [_overdue('r1', 'table'), _fresh('n1', 'window')],
        _now,
      );

      expect(_find(queue, 'r1').reason, SelectionReason.due);
      expect(_find(queue, 'n1').reason, SelectionReason.newWord);
    });

    test('слово с ближайших страниц книги помечено книгой', () {
      final builder = SessionBuilder()
        ..setReadingHorizon({Lemmatizer.stem('window', 'en')}, 'en');
      final queue = builder.build(
        StudyMode.flashcards,
        [_fresh('n1', 'window'), _fresh('n2', 'carpet')],
        _now,
      );

      expect(_find(queue, 'n1').reason, SelectionReason.book);
      expect(_find(queue, 'n2').reason, SelectionReason.newWord,
          reason: 'слова вне горизонта чтения книгой не помечаются');
    });

    test('карту, подтянутую из-за срыва соседа, помечает сосед', () {
      final bright = _overdue('c1', 'bright', stability: 20);
      final brightness = _overdue('c2', 'brightness', stability: 20);
      LinkPropagation.afterLapse(bright, [bright, brightness], 'en', now: _now);

      final queue = SessionBuilder()
          .build(StudyMode.flashcards, [bright, brightness], _now);

      expect(_find(queue, 'c2').reason, SelectionReason.neighbourLapse);
      expect(_find(queue, 'c1').reason, SelectionReason.due,
          reason: 'сорвавшаяся карта пришла по собственному сроку');
    });

    test('метка снимается после повтора карты', () {
      final bright = _overdue('c1', 'bright', stability: 20);
      final brightness = _overdue('c2', 'brightness', stability: 20);
      LinkPropagation.afterLapse(bright, [bright, brightness], 'en', now: _now);
      expect(brightness.review.nudgedByNeighbour, true);

      brightness.review =
          Fsrs.instance.review(brightness.review, Rating.good, _now);

      expect(brightness.review.nudgedByNeighbour, false,
          reason: 'карту спросили — повод больше не действует');
    });
  });
}
