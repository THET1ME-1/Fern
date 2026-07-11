import 'package:flutter_test/flutter_test.dart';

import 'package:fern/services/grammar.dart';

List<String> _forms(String w, String pos, String lang) {
  final t = Grammar.forWord(w, pos, lang);
  return t.isEmpty ? const [] : [for (final r in t.first.rows) r.form];
}

void main() {
  test('испанский: регулярный и неправильный глагол', () {
    expect(_forms('hablar', 'verb', 'es'),
        ['hablo', 'hablas', 'habla', 'hablamos', 'habláis', 'hablan']);
    expect(_forms('ser', 'verb', 'es').first, 'soy');
  });

  test('французский: элизия je → j’ перед гласной', () {
    final t = Grammar.forWord('aimer', 'verb', 'fr').first;
    expect(t.rows.first.label, 'j’');
    expect(t.rows.first.form, 'aime');
  });

  test('немецкий: слабый глагол', () {
    expect(_forms('machen', 'verb', 'de'),
        ['mache', 'machst', 'macht', 'machen', 'macht', 'machen']);
    expect(_forms('sein', 'verb', 'de').first, 'bin');
  });

  test('русский: 1-е и 2-е спряжение', () {
    expect(_forms('читать', 'verb', 'ru').first, 'читаю');
    expect(_forms('говорить', 'verb', 'ru').first, 'говорю');
  });

  test('множественное число существительных', () {
    expect(_forms('gato', 'noun', 'es'), ['gato', 'gatos']);
    expect(_forms('luz', 'noun', 'es').last, 'luces');
    expect(_forms('gatto', 'noun', 'it').last, 'gatti');
  });

  test('не глагол/сущ. и фразы — пусто', () {
    expect(Grammar.forWord('rápido', 'adj', 'es'), isEmpty);
    expect(Grammar.forWord('buenos días', 'noun', 'es'), isEmpty);
    expect(Grammar.forWord('hello', 'verb', 'en'), isEmpty); // англ. не поддержан
  });
}
