import 'package:flutter_test/flutter_test.dart';

import 'package:fern/models/deck.dart';
import 'package:fern/models/word_card.dart';
import 'package:fern/services/book_analysis.dart';
import 'package:fern/services/deck_repository.dart';
import 'package:fern/services/source_library.dart';

import 'test_helpers.dart';

void main() {
  final repo = DeckRepository.instance;

  group('BookAnalysis', () {
    setUp(() async {
      await resetStorage();
      await repo.init();
    });

    test('делит слова книги на помнит / учит / не знает + покрытие', () async {
      await repo.upsertDeck(Deck(
        id: 'd1',
        languageCode: 'en',
        name: 'EN',
        colorValue: 0xFF2E7D5B,
        shapeIndex: 0,
        createdAt: 1,
      ));
      // «the» — крепко в памяти (review, высокая стабильность, только что повторяли).
      await repo.upsertCard(WordCard(
        id: 'c_the',
        deckId: 'd1',
        front: 'the',
        back: 'определённый артикль',
        review: ReviewState(
          state: FsrsState.review,
          stability: 100,
          difficulty: 5,
          reps: 5,
          lastReview: DateTime.now(),
        ),
      ));
      // «cat» — новая карта (в словаре, но ещё не выучена).
      await repo.upsertCard(WordCard(
        id: 'c_cat',
        deckId: 'd1',
        front: 'Cat', // регистр не важен
        back: 'кот',
      ));

      final a = BookAnalysis.analyze('The cat and the dog. The cat runs.', 'en');

      // Всего слов (с повторами): the×3, cat×2, and, dog, runs = 8.
      expect(a.totalTokens, 8);
      // Уникальных: the, cat, and, dog, runs = 5.
      expect(a.uniqueTypes, 5);
      expect(a.knownTypes, 1); // the
      expect(a.learningTypes, 1); // cat
      expect(a.unknownTypes, 3); // and, dog, runs
      expect(a.inDictionaryTypes, 2);

      // Покрытие по токенам: (the×3 + cat×2)/8 = 0.625.
      expect(a.coverage, closeTo(0.625, 1e-9));
      // Уверенно помнит: the×3 / 8 = 0.375.
      expect(a.masteredCoverage, closeTo(0.375, 1e-9));

      // В списке «учить первыми» — только содержательные слова: союз «and»
      // считается незнакомым для статистики, но учить его карточкой незачем.
      final unknownWords = a.topUnknown.map((w) => w.word).toSet();
      expect(unknownWords, containsAll(<String>['dog', 'runs']));
      expect(unknownWords, isNot(contains('and')));
    });

    test('пустой текст даёт пустой анализ', () {
      final a = BookAnalysis.analyze('   \n  ...  123  ', 'en');
      expect(a.totalTokens, 0);
      expect(a.uniqueTypes, 0);
    });

    test('слова другого языка не считаются знакомыми', () async {
      await repo.upsertDeck(Deck(
        id: 'de',
        languageCode: 'de',
        name: 'DE',
        colorValue: 0xFF2E7D5B,
        shapeIndex: 0,
        createdAt: 1,
      ));
      await repo.upsertCard(
          WordCard(id: 'k', deckId: 'de', front: 'cat', back: 'Katze'));
      // Анализ для 'en' — карта немецкой колоды не должна засчитаться.
      final a = BookAnalysis.analyze('cat cat', 'en');
      expect(a.unknownTypes, 1);
      expect(a.inDictionaryTypes, 0);
    });
  });

  group('LibrarySource метаданные', () {
    test('round-trip сохраняет автора/описание/теги/жанры', () {
      final s = LibrarySource(
        id: 'src_1',
        kind: SourceKind.book,
        title: 'Мастер и Маргарита',
        languageCode: 'ru',
        createdAt: 123,
        format: 'txt',
        charCount: 4000,
        author: 'Булгаков',
        description: 'Роман о добре и зле',
        tags: const ['классика', 'любимое'],
        genres: const ['роман', 'мистика'],
      );
      final back = LibrarySource.fromJson(s.toJson());
      expect(back.author, 'Булгаков');
      expect(back.description, 'Роман о добре и зле');
      expect(back.tags, ['классика', 'любимое']);
      expect(back.genres, ['роман', 'мистика']);
    });

    test('пустые метаданные не пишутся в JSON', () {
      final s = LibrarySource(
        id: 'src_2',
        kind: SourceKind.book,
        title: 'Без метаданных',
        languageCode: 'en',
        createdAt: 1,
      );
      final json = s.toJson();
      expect(json.containsKey('author'), isFalse);
      expect(json.containsKey('desc'), isFalse);
      expect(json.containsKey('tags'), isFalse);
      expect(json.containsKey('genres'), isFalse);
    });
  });
}
