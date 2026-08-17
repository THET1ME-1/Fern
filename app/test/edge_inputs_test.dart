// Крайние входы для чистых сервисов: пусто, пробелы, эмодзи, одни знаки
// препинания, символ вне BMP, очень длинное слово, ссылка, кусок разметки.
//
// Всё это приходит из чужого текста — книги, субтитров, буфера обмена, — и ни
// один разбор не имеет права падать на таком.
import 'package:flutter_test/flutter_test.dart';

import 'package:fern/models/fsrs.dart';
import 'package:fern/models/word_card.dart';
import 'package:fern/services/book_analysis.dart';
import 'package:fern/services/constructions.dart';
import 'package:fern/services/interference.dart';
import 'package:fern/services/language_detect.dart';
import 'package:fern/services/lemmatizer.dart';
import 'package:fern/services/pos.dart';
import 'package:fern/services/text_analysis.dart';
import 'package:fern/services/vocab_export.dart';
import 'package:fern/services/word_links.dart';
import 'package:fern/services/word_priority.dart';
import 'package:fern/study/study_models.dart';
import 'package:fern/utils/text_distance.dart';

final _found = <String>[];

void probe(String what, void Function() body) {
  try {
    body();
  } catch (e) {
    _found.add('$what → $e');
  }
}

const inputs = <String>[
  '',
  ' ',
  '\n\n\n',
  '...',
  '—',
  '😀😀',
  'a',
  'ы',
  '𝄞𝄞𝄞',
  'слово',
  'The',
  'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  '123 456',
  'https://example.com/x?y=1',
  '<b>tag</b>',
];

WordCard card(String front, String back, {String sentence = ''}) => WordCard(
      id: front,
      deckId: 'd',
      front: front,
      back: back,
      sentence: sentence,
    );

void main() {
  tearDown(() {
    expect(_found, isEmpty, reason: _found.join('\n'));
    _found.clear();
  });

  test('текстовые сервисы на крайних входах', () {
    for (final s in inputs) {
      probe('BookAnalysis.tokenize($s)', () => BookAnalysis.tokenize(s));
      probe('TextParse.analyzePlain($s)',
          () => TextParse.analyzePlain(s, 'en'));
      probe('LanguageDetect.detect($s)', () => LanguageDetect.detect(s));
      probe('Lemmatizer.stem($s,ru)', () => Lemmatizer.stem(s, 'ru'));
      probe('Lemmatizer.stem($s,en)', () => Lemmatizer.stem(s, 'en'));
      probe('PosDetect.strip($s)', () => PosDetect.strip(s));
      probe('WordPriority.score($s)', () => WordPriority.score(s, 1));
      probe('WordPriority.isFunctionWord($s)',
          () => WordPriority.isFunctionWord(s, 'en'));
      probe('Constructions.find($s)',
          () => Constructions.find(TextParse.analyzePlain(s, 'en'), 'en'));
      probe('levenshtein($s)', () => levenshtein(s, 'слово'));
    }
  });

  test('карточные сервисы на пустых наборах', () {
    final empty = <WordCard>[];
    final one = [card('word', 'слово')];
    probe('buildCloze без предложения', () => buildCloze(card('a', 'б')));
    probe('buildAssemble без предложения', () => buildAssemble(card('a', 'б')));
    probe('buildOddOne пустой пул', () => buildOddOne(one.first, empty, 'en'));
    probe('buildTwins пустой пул', () => buildTwins(one.first, empty));
    probe('WordLinks.auto пустой пул',
        () => WordLinks.auto(one.first, empty, 'en'));
    probe('Interference.spread пусто', () => Interference.spread(empty));
    probe('Interference.countConflicts пусто',
        () => Interference.countConflicts(empty));
    probe('VocabExport.build пусто',
        () => VocabExport.build(VocabFormat.csv, empty));
    probe('VocabExport.build странное',
        () => VocabExport.build(VocabFormat.csv, [card('=SUM(1)', '"кавычки"')]));
  });

  test('FSRS на крайних состояниях', () {
    final f = Fsrs.instance;
    probe('retrievability(0,0)', () => f.retrievability(0, 0));
    probe('retrievability(-1,0)', () => f.retrievability(-1, 0));
    probe('retrievability(10,-5)', () => f.retrievability(10, -5));
    probe('retrievability(1e9,1e-9)', () => f.retrievability(1e9, 1e-9));
    for (final r in Rating.values) {
      probe('review новая $r', () {
        final c = card('a', 'б');
        f.review(c.review, r, DateTime.now());
      });
      probe('review нулевая прочность $r', () {
        final st = ReviewState(
          stability: 0,
          difficulty: 0,
          state: FsrsState.review,
          reps: 1,
          lastReview: DateTime.now().subtract(const Duration(days: 3)),
          due: DateTime.now(),
        );
        f.review(st, r, DateTime.now());
      });
      probe('review огромная прочность $r', () {
        final st = ReviewState(
          stability: 1e9,
          difficulty: 10,
          state: FsrsState.review,
          reps: 500,
          lastReview: DateTime.now().subtract(const Duration(days: 4000)),
          due: DateTime.now(),
        );
        f.review(st, r, DateTime.now());
      });
    }
  });
}
