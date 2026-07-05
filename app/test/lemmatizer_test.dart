import 'package:flutter_test/flutter_test.dart';

import 'package:fern/models/deck.dart';
import 'package:fern/models/word_card.dart';
import 'package:fern/services/book_analysis.dart';
import 'package:fern/services/deck_repository.dart';
import 'package:fern/services/lemmatizer.dart';

import 'test_helpers.dart';

void main() {
  group('Lemmatizer (en)', () {
    void same(String a, String b) =>
        expect(Lemmatizer.stem(a, 'en'), Lemmatizer.stem(b, 'en'),
            reason: '$a ≟ $b');

    test('множественное и глагольные формы сводятся к основе', () {
      same('foxes', 'fox');
      same('cats', 'cat');
      same('studies', 'study');
      same('running', 'run');
      same('walked', 'walk');
      same('jumps', 'jump');
    });

    test('не ломает слова на -ss', () {
      expect(Lemmatizer.stem('class', 'en'), 'class');
    });
  });

  group('Lemmatizer (ru)', () {
    test('падежные формы сводятся к основе', () {
      expect(Lemmatizer.stem('слова', 'ru'), Lemmatizer.stem('слово', 'ru'));
      expect(Lemmatizer.stem('коты', 'ru'), Lemmatizer.stem('кот', 'ru'));
    });
  });

  group('Анализ с лемматизацией', () {
    final repo = DeckRepository.instance;
    setUp(() async {
      await resetStorage();
      await repo.init();
    });

    test('карточка «fox» засчитывает словоформу «foxes» в книге', () async {
      await repo.upsertDeck(Deck(
        id: 'd1',
        languageCode: 'en',
        name: 'EN',
        colorValue: 1,
        shapeIndex: 0,
        createdAt: 1,
      ));
      await repo.upsertCard(
          WordCard(id: 'c1', deckId: 'd1', front: 'fox', back: 'лиса'));

      final a = BookAnalysis.analyze('Foxes and more foxes.', 'en');
      // «foxes» больше не «не знаю» — оно сведено к карточке «fox».
      final unknown = a.topUnknown.map((w) => w.word).toSet();
      expect(unknown.contains('foxes'), isFalse);
      expect(a.inDictionaryTypes, greaterThanOrEqualTo(1));
    });
  });
}
