import 'package:flutter_test/flutter_test.dart';

import 'package:fern/models/word_card.dart';
import 'package:fern/study/study_models.dart';

void main() {
  group('buildCloze', () {
    test('вырезает слово из предложения-контекста', () {
      final card = WordCard(
        id: '1',
        deckId: 'd',
        front: 'cat',
        back: 'кот',
        sentence: 'The cat sat on the mat.',
      );
      final c = buildCloze(card);
      expect(c, isNotNull);
      expect(c!.answer, 'cat');
      expect(c.blanked.contains('_____'), isTrue);
      expect(c.blanked.contains('cat'), isFalse);
      // Восстановление даёт исходное предложение.
      expect(c.blanked.replaceFirst('_____', c.answer), 'The cat sat on the mat.');
    });

    test('берёт пример, если нет предложения', () {
      final card = WordCard(
        id: '2',
        deckId: 'd',
        front: 'dog',
        back: 'собака',
        example: 'A big dog runs.',
      );
      expect(buildCloze(card)?.answer, 'dog');
    });

    test('null, если контекста нет', () {
      final card = WordCard(id: '3', deckId: 'd', front: 'sun', back: 'солнце');
      expect(buildCloze(card), isNull);
    });

    test('null, если слова нет в предложении', () {
      final card = WordCard(
        id: '4',
        deckId: 'd',
        front: 'moon',
        back: 'луна',
        sentence: 'The sky is blue.',
      );
      expect(buildCloze(card), isNull);
    });
  });

  group('SessionBuilder.cloze', () {
    test('строит упражнения только для карт с контекстом', () {
      final cards = [
        WordCard(
            id: '1',
            deckId: 'd',
            front: 'cat',
            back: 'кот',
            sentence: 'The cat sat.'),
        WordCard(id: '2', deckId: 'd', front: 'dog', back: 'собака'), // нет контекста
      ];
      final q = SessionBuilder().build(StudyMode.cloze, cards, DateTime.now());
      expect(q.length, 1);
      expect(q.first.kind, ExerciseKind.cloze);
      expect(q.first.card.front, 'cat');
    });
  });
}
