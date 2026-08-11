import 'package:flutter_test/flutter_test.dart';

import 'package:fern/services/constructions.dart';
import 'package:fern/services/deck_repository.dart';
import 'package:fern/services/text_analysis.dart';

import 'test_helpers.dart';

void main() {
  final repo = DeckRepository.instance;

  setUp(() async {
    await resetStorage();
    await repo.init();
  });

  List<String> codes(String text) {
    final a = TextParse.analyze(text, 'en');
    return [for (final h in Constructions.find(a, 'en')) h.code];
  }

  test('длинный шаблон побеждает короткий', () {
    final c = codes('I have been waiting for an hour.');
    expect(c, contains('present_perfect_cont'));
    expect(c, isNot(contains('present_perfect')));
  });

  test('пассив отличается от продолженного времени', () {
    expect(codes('The house was built in 1920.'), contains('passive_past'));
    expect(codes('He was building a house.'), contains('past_cont'));
  });

  test('перфект отличается от пассива по вспомогательному глаголу', () {
    expect(codes('She has written a letter.'), contains('present_perfect'));
    expect(codes('The letter has been written.'), contains('perfect_passive'));
  });

  test('третий тип условного узнаётся целиком', () {
    final c = codes('If I had known, I would have told you.');
    expect(c, contains('conditional_3'));
  });

  test('второй тип условного не путается с третьим', () {
    expect(codes('If I knew the answer, I would tell you.'),
        contains('conditional_2'));
  });

  test('будущее, модальные и going to', () {
    expect(codes('I will call you tomorrow.'), contains('future_will'));
    expect(codes('You should call her.'), contains('modal_verb'));
    expect(codes('We are going to move.'), contains('going_to'));
  });

  test('оборот указывает на настоящие позиции в тексте', () {
    const text = 'The window was broken yesterday.';
    final a = TextParse.analyze(text, 'en');
    final hits = Constructions.find(a, 'en');
    expect(hits, isNotEmpty);
    for (final h in hits) {
      expect(text.substring(h.start, h.end), h.snippet);
    }
    expect(hits.first.snippet, 'was broken');
  });

  test('чужой язык разбора не выдумывает', () {
    final a = TextParse.analyze('Ich habe ein Buch gelesen.', 'de');
    expect(Constructions.find(a, 'de'), isEmpty);
    expect(Constructions.supports('de'), isFalse);
  });
}

