import 'package:flutter_test/flutter_test.dart';

import 'package:fern/models/deck.dart';
import 'package:fern/models/word_card.dart';
import 'package:fern/services/deck_repository.dart';
import 'package:fern/services/reply_hints.dart';
import 'package:fern/services/text_analysis.dart';

import 'test_helpers.dart';

void main() {
  final repo = DeckRepository.instance;

  Future<void> card(String id, String front, String back,
      {double stability = 50}) async {
    await repo.upsertCard(WordCard(
      id: id,
      deckId: 'd1',
      front: front,
      back: back,
      review: ReviewState(
        state: FsrsState.review,
        stability: stability,
        difficulty: 5,
        reps: 3,
        lastReview: DateTime.now(),
      ),
    ));
  }

  setUp(() async {
    await resetStorage();
    await repo.init();
    await repo.upsertDeck(Deck(
      id: 'd1',
      languageCode: 'en',
      name: 'EN',
      colorValue: 0xFF2E7D5B,
      shapeIndex: 0,
      createdAt: 1,
    ));
  });

  test('свои слова отделяются от новых', () async {
    await card('c1', 'house', 'дом');
    final hints = ReplyAnalysis.of(
      TextParse.analyze('The house is enormous', 'en'),
      'en',
    );
    expect(hints.used, contains('house'));
    expect(hints.fresh, contains('enormous'));
    expect(hints.fresh, isNot(contains('house')));
  });

  test('к простому слову предлагается выученный синоним', () async {
    await card('c1', 'big', 'большой', stability: 10);
    await card('c2', 'huge', 'большой, огромный', stability: 90);
    final hints = ReplyAnalysis.of(
      TextParse.analyze('a big dog', 'en'),
      'en',
    );
    expect(hints.upgrades, hasLength(1));
    expect(hints.upgrades.first.used, 'big');
    expect(hints.upgrades.first.better.front, 'huge');
  });

  test('замена не предлагается сама на себя и на однокоренное', () async {
    await card('c1', 'run', 'бежать');
    await card('c2', 'running', 'бежать');
    final hints = ReplyAnalysis.of(TextParse.analyze('I run', 'en'), 'en');
    expect(hints.upgrades, isEmpty);
  });

  test('карточка правила заменой не предлагается', () async {
    await card('c1', 'big', 'большой');
    await repo.upsertCard(WordCard(
      id: 'r1',
      deckId: 'd1',
      front: 'Present Perfect',
      back: 'большой',
      rule: 'present_perfect',
    ));
    final hints = ReplyAnalysis.of(TextParse.analyze('a big dog', 'en'), 'en');
    expect(hints.upgrades, isEmpty);
  });
}
