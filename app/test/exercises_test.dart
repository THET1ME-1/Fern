import 'package:flutter_test/flutter_test.dart';

import 'package:fern/models/word_card.dart';
import 'package:fern/study/study_models.dart';

void main() {
  group('Собери фразу (buildAssemble)', () {
    test('строит осколки из предложения-контекста', () {
      final card = WordCard(
        id: 'c1',
        deckId: 'd1',
        front: 'cat',
        back: 'кот',
        example: 'The cat sleeps here.',
      );
      final asm = buildAssemble(card);
      expect(asm, isNotNull);
      expect(asm!.tokens, ['The', 'cat', 'sleeps', 'here.']);
    });

    test('одно слово или пусто — не годится', () {
      expect(
        buildAssemble(WordCard(id: 'c', deckId: 'd', front: 'x', back: 'ы',
            example: 'Word')),
        isNull,
      );
      expect(
        buildAssemble(WordCard(id: 'c', deckId: 'd', front: 'x', back: 'ы')),
        isNull,
      );
    });

    test('sentence приоритетнее example', () {
      final card = WordCard(
        id: 'c',
        deckId: 'd',
        front: 'perro',
        back: 'собака',
        example: 'ignored example',
        sentence: 'El perro corre',
      );
      expect(buildAssemble(card)!.sentence, 'El perro corre');
    });
  });

  group('Проверка порядка (assembleMatches)', () {
    test('верный порядок — без учёта регистра и пунктуации', () {
      expect(assembleMatches(['the', 'cat', 'sleeps'], 'The cat sleeps.'), true);
    });
    test('неверный порядок — не проходит', () {
      expect(assembleMatches(['cat', 'the', 'sleeps'], 'The cat sleeps.'), false);
    });
  });
}
