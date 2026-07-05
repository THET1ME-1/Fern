import 'package:flutter_test/flutter_test.dart';

import 'package:fern/services/pos.dart';
import 'package:fern/services/pos_dictionary.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() => PosDictionary.instance.ensureLoaded('en'));

  test('словарь загружается и даёт ТОЧНЫЕ части речи', () {
    expect(PosDictionary.instance.isReady, true);
    // Слова, которые старая эвристика путала (‑ary/‑ive/‑ish → прил).
    expect(PosDictionary.instance.lookup('library', 'en'), 'noun');
    expect(PosDictionary.instance.lookup('dictionary', 'en'), 'noun');
    expect(PosDictionary.instance.lookup('salary', 'en'), 'noun');
    expect(PosDictionary.instance.lookup('motive', 'en'), 'noun');
    expect(PosDictionary.instance.lookup('rubbish', 'en'), 'noun');
    // И правильные прил./глаг./нареч.
    expect(PosDictionary.instance.lookup('beautiful', 'en'), 'adj');
    expect(PosDictionary.instance.lookup('run', 'en'), 'verb');
    expect(PosDictionary.instance.lookup('quickly', 'en'), 'adv');
    // Нет в словаре / другой язык.
    expect(PosDictionary.instance.lookup('zzzznotaword', 'en'), isNull);
    expect(PosDictionary.instance.lookup('library', 'es'), isNull);
  });

  test('detect опирается на словарь: library → noun (а не adj)', () {
    expect(PosDetect.detect('library', languageCode: 'en'), 'noun');
    expect(PosDetect.detect('salary', languageCode: 'en'), 'noun');
    expect(PosDetect.detect('motive', languageCode: 'en'), 'noun');
    expect(PosDetect.detect('native', languageCode: 'en'), 'adj');
  });

  test('detect по лемме: форма слова сводится к основе из словаря', () {
    // Множественное число: cats → cat (noun).
    expect(PosDetect.detect('cats', languageCode: 'en'), 'noun');
  });
}
