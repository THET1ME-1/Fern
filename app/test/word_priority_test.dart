import 'package:flutter_test/flutter_test.dart';

import 'package:fern/services/word_priority.dart';

/// Список «учить в первую очередь» строился по голой частоте, и первыми в нём
/// стояли `the`, `of`, `to`, `a`. Их знает любой, кто вообще открыл английскую
/// книгу, — место в списке они занимали зря.
void main() {
  group('служебные слова не предлагаются', () {
    test('английские артикли, предлоги и связки отсеиваются', () {
      for (final w in [
        'the', 'of', 'to', 'a', 'an', 'is', 'was', 'are', 'be', 'have',
        'had', 'not', 'at', 'as', 'for', 'his', 'will', 'would', 'do', 'me',
        'if', 'out', 'and', 'but', 'or', 'that', 'this', 'with',
      ]) {
        expect(WordPriority.isFunctionWord(w, 'en'), isTrue,
            reason: '«$w» — служебное, учить его незачем');
      }
    });

    test('содержательные слова остаются', () {
      for (final w in [
        'foundation', 'empire', 'psychohistory', 'feudalism', 'viewpoint',
        'encyclopedia', 'galactic', 'trader', 'reluctant',
      ]) {
        expect(WordPriority.isFunctionWord(w, 'en'), isFalse,
            reason: '«$w» стоит выучить');
      }
    });

    test('русские предлоги и местоимения тоже отсеиваются', () {
      for (final w in ['и', 'в', 'не', 'на', 'что', 'он', 'она', 'как', 'но']) {
        expect(WordPriority.isFunctionWord(w, 'ru'), isTrue);
      }
      expect(WordPriority.isFunctionWord('основание', 'ru'), isFalse);
    });

    test('незнакомый язык: очень короткие слова считаются служебными', () {
      // Стоп-листа для суахили нет, но однобуквенное слово учить нечего.
      expect(WordPriority.isFunctionWord('na', 'sw'), isTrue);
      expect(WordPriority.isFunctionWord('kusoma', 'sw'), isFalse);
    });
  });

  group('порядок предложения', () {
    test('редкое длинное слово обгоняет частое короткое', () {
      // 800 раз «said» против 40 раз «psychohistory»: учить стоит второе.
      final said = WordPriority.score('said', 800);
      final psycho = WordPriority.score('psychohistory', 40);
      expect(psycho, greaterThan(said));
    });

    test('при равной длине побеждает более частое', () {
      expect(
        WordPriority.score('empire', 300),
        greaterThan(WordPriority.score('trader', 30)),
      );
    });

    test('единичная опечатка не выигрывает у настоящего слова', () {
      // Слово, встреченное один раз, почти всегда мусор распознавания.
      expect(
        WordPriority.score('foundation', 120),
        greaterThan(WordPriority.score('foundationnn', 1)),
      );
    });
  });

  group('имена собственные', () {
    test('слово, всегда написанное с большой буквы, — имя', () {
      expect(WordPriority.looksProper(capitalized: 235, total: 235), isTrue);
      expect(WordPriority.looksProper(capitalized: 230, total: 235), isTrue);
    });

    test('обычное слово в начале предложений именем не считается', () {
      expect(WordPriority.looksProper(capitalized: 40, total: 300), isFalse);
    });
  });

  group('итоговый отбор', () {
    test('служебные уходят, содержательные ранжируются, длинные попадают', () {
      final picked = WordPriority.pick(
        const [
          WordCandidate(word: 'the', count: 4371, capitalized: 12),
          WordCandidate(word: 'of', count: 2121, capitalized: 3),
          WordCandidate(word: 'a', count: 1516, capitalized: 5),
          WordCandidate(word: 'said', count: 361, capitalized: 0),
          WordCandidate(word: 'hardin', count: 235, capitalized: 235),
          WordCandidate(word: 'foundation', count: 200, capitalized: 20),
          WordCandidate(word: 'psychohistory', count: 41, capitalized: 2),
          WordCandidate(word: 'encyclopedia', count: 33, capitalized: 4),
          WordCandidate(word: 'noise', count: 1, capitalized: 0),
        ],
        'en',
        limit: 10,
      );
      final words = picked.map((w) => w.word).toList();

      expect(words, isNot(contains('the')));
      expect(words, isNot(contains('of')));
      expect(words, isNot(contains('a')));
      expect(words, isNot(contains('hardin')),
          reason: 'имя собственное учить незачем');
      expect(words, contains('foundation'));
      expect(words, contains('psychohistory'));
      expect(words.first, isNot('said'),
          reason: 'частое, но простое слово не должно открывать список');
    });

    test('пустой вход не роняет отбор', () {
      expect(WordPriority.pick(const [], 'en', limit: 10), isEmpty);
    });
  });
}
