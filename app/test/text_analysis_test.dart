import 'package:flutter_test/flutter_test.dart';

import 'package:fern/models/deck.dart';
import 'package:fern/models/word_card.dart';
import 'package:fern/services/deck_repository.dart';
import 'package:fern/services/text_analysis.dart';

import 'test_helpers.dart';

void main() {
  final repo = DeckRepository.instance;

  Future<void> seedDeck() async {
    await repo.upsertDeck(Deck(
      id: 'd1',
      languageCode: 'en',
      name: 'EN',
      colorValue: 0xFF2E7D5B,
      shapeIndex: 0,
      createdAt: 1,
    ));
  }

  group('разбивка на предложения', () {
    test('не режет сокращения и инициалы', () {
      final s = TextParse.sentences(
        'Mr. Smith met Dr. J. R. Brown at 3.5 p.m. They talked. Then he left!',
      );
      expect(s.length, 3);
      expect(s.first.text, startsWith('Mr. Smith'));
      expect(s[1].text, 'They talked.');
      expect(s[2].text, 'Then he left!');
    });

    test('перевод строки завершает предложение', () {
      final s = TextParse.sentences('Привет\nКак дела?');
      expect(s.length, 2);
      expect(s.first.text, 'Привет');
    });

    test('границы указывают на исходный текст', () {
      const text = 'One. Two.';
      for (final s in TextParse.sentences(text)) {
        expect(text.substring(s.start, s.end).trim(), s.text);
      }
    });
  });

  group('TextParse.analyze', () {
    setUp(() async {
      await resetStorage();
      await repo.init();
      await seedDeck();
    });

    test('позиции токенов совпадают с исходным текстом', () async {
      const text = "Don't stop me now, please.";
      final a = TextParse.analyze(text, 'en');
      expect(a.tokens, isNotEmpty);
      for (final t in a.tokens) {
        expect(text.substring(t.start, t.end), t.surface);
      }
      expect(a.tokens.first.surface, "Don't");
    });

    test('слово опознаётся по основе, статус зависит от памяти', () async {
      await repo.upsertCard(WordCard(
        id: 'c_fox',
        deckId: 'd1',
        front: 'fox',
        back: 'лиса',
        review: ReviewState(
          state: FsrsState.review,
          stability: 200,
          difficulty: 5,
          reps: 4,
          lastReview: DateTime.now(),
        ),
      ));
      await repo.upsertCard(WordCard(
        id: 'c_run',
        deckId: 'd1',
        front: 'run',
        back: 'бежать',
        review: ReviewState(
          state: FsrsState.review,
          stability: 1,
          difficulty: 8,
          reps: 2,
          lastReview: DateTime.now().subtract(const Duration(days: 20)),
        ),
      ));

      final a = TextParse.analyze('Foxes running quickly', 'en');
      final foxes = a.tokens.firstWhere((t) => t.surface == 'Foxes');
      final running = a.tokens.firstWhere((t) => t.surface == 'running');
      final quickly = a.tokens.firstWhere((t) => t.surface == 'quickly');

      expect(foxes.status, WordStatus.known);
      expect(foxes.cardId, 'c_fox');
      expect(running.status, WordStatus.learning);
      expect(running.cardId, 'c_run');
      expect(quickly.status, WordStatus.unknown);
      expect(quickly.cardId, isNull);
    });

    test('числа не считаются словами и не портят покрытие', () async {
      await repo.upsertCard(WordCard(
        id: 'c_cat',
        deckId: 'd1',
        front: 'cat',
        back: 'кот',
        review: ReviewState(
          state: FsrsState.review,
          stability: 100,
          difficulty: 5,
          reps: 3,
          lastReview: DateTime.now(),
        ),
      ));
      final a = TextParse.analyze('cat 42 cat', 'en');
      final number = a.tokens.firstWhere((t) => t.surface == '42');
      expect(number.status, WordStatus.ignored);
      expect(a.totalWords, 2);
      expect(a.coverage, 1.0);
    });

    test('незнакомые слова собраны без повторов, в порядке появления', () {
      final a = TextParse.analyze('alpha beta Alpha gamma', 'en');
      expect(a.unknownWords, ['alpha', 'beta', 'gamma']);
    });

    test('каждый токен знает своё предложение', () {
      final a = TextParse.analyze('First one. Second one.', 'en');
      expect(a.sentences.length, 2);
      expect(a.tokens.first.sentence, 0);
      expect(a.tokens.last.sentence, 1);
    });
  });
}
