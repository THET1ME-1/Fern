import 'package:flutter_test/flutter_test.dart';

import 'package:fern/models/word_card.dart';
import 'package:fern/services/deck_repository.dart';
import 'package:fern/services/grammar_deck.dart';
import 'package:fern/study/study_models.dart';

import 'test_helpers.dart';

void main() {
  final repo = DeckRepository.instance;

  group('колода правил', () {
    setUp(() async {
      await resetStorage();
      await repo.init();
    });

    test('правило заводится один раз на код', () async {
      final first = await GrammarDeck.add(
        languageCode: 'en',
        code: 'present_perfect',
        name: 'Present Perfect',
        hint: 'Прошлое со следом в настоящем.',
        example: 'She has written a letter.',
      );
      final second = await GrammarDeck.add(
        languageCode: 'en',
        code: 'present_perfect',
        name: 'Present Perfect',
        hint: 'Другое объяснение',
        example: 'I have lost my keys.',
      );
      expect(second.id, first.id);
      expect(GrammarDeck.rules('en').length, 1);
      expect(GrammarDeck.find('present_perfect', 'en')?.example,
          'She has written a letter.');
    });

    test('карточка правила отличается от карточки слова', () async {
      final card = await GrammarDeck.add(
        languageCode: 'en',
        code: 'passive_past',
        name: 'Passive (past)',
        hint: 'was/were плюс третья форма.',
        example: 'The house was built in 1920.',
      );
      expect(card.isRule, isTrue);
      expect(WordCard(id: 'x', deckId: 'd', front: 'cat', back: 'кот').isRule,
          isFalse);
    });

    test('правило переживает запись на диск', () async {
      await GrammarDeck.add(
        languageCode: 'en',
        code: 'used_to',
        name: 'Used to',
        hint: 'Привычка в прошлом.',
        example: 'I used to live here.',
      );
      repo.resetForTest();
      await repo.init();
      expect(GrammarDeck.find('used_to', 'en')?.rule, 'used_to');
    });
  });

  group('выбор конструкции', () {
    WordCard rule(String code, String name, {String sentence = 'A sentence.'}) =>
        WordCard(
          id: 'r_$code',
          deckId: 'd',
          front: name,
          back: 'объяснение',
          sentence: sentence,
          rule: code,
        );

    test('верный вариант на месте, отвлекающие настоящие', () {
      final choice = buildRuleChoice(
        rule('present_perfect', 'Present Perfect'),
        ['Past Perfect', 'Passive (past)', 'Used to', 'Present Perfect'],
      );
      expect(choice, isNotNull);
      expect(choice!.options.length, 4);
      expect(choice.answer, 'Present Perfect');
      expect(choice.options.toSet().length, 4, reason: 'без повторов');
    });

    test('набор вариантов не скачет между пересборками', () {
      final card = rule('passive_past', 'Passive (past)');
      final a = buildRuleChoice(card, ['Past Perfect', 'Used to', 'Future']);
      final b = buildRuleChoice(card, ['Past Perfect', 'Used to', 'Future']);
      expect(a!.options, b!.options);
    });

    test('без примера и без соседей упражнения нет', () {
      expect(buildRuleChoice(rule('x', 'X', sentence: ''), ['Y']), isNull);
      expect(buildRuleChoice(rule('x', 'X'), const []), isNull);
      expect(
        buildRuleChoice(
          WordCard(id: 'c', deckId: 'd', front: 'cat', back: 'кот',
              sentence: 'A cat sits.'),
          ['Present Perfect'],
        ),
        isNull,
        reason: 'обычное слово конструкцией не спрашивают',
      );
    });

    test('режим «Правила» собирает сессию из карточек правил', () {
      final cards = [
        rule('present_perfect', 'Present Perfect'),
        rule('passive_past', 'Passive (past)'),
        WordCard(id: 'w1', deckId: 'd', front: 'cat', back: 'кот'),
      ];
      final queue = SessionBuilder().build(
        StudyMode.grammar,
        cards,
        DateTime.now(),
        ruleNames: ['Present Perfect', 'Passive (past)', 'Used to'],
      );
      expect(queue.length, 2);
      expect(queue.every((e) => e.kind == ExerciseKind.ruleChoose), isTrue);
      expect(queue.every((e) => e.card.isRule), isTrue);
    });

    test('правила влияют на расписание', () {
      expect(StudyMode.grammar.affectsSchedule, isTrue);
    });
  });
}

