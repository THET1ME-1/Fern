import 'package:flutter_test/flutter_test.dart';

import 'package:fern/l10n/locale_controller.dart';
import 'package:fern/l10n/strings.dart';

import 'test_helpers.dart';

void main() {
  setUp(resetStorage);
  test('русские формы: 1 слово, 2 слова, 5 слов', () async {
    await LocaleController.instance.setCode('ru');
    expect(trn('n_words', 1), '1 слово');
    expect(trn('n_words', 2), '2 слова');
    expect(trn('n_words', 4), '4 слова');
    expect(trn('n_words', 5), '5 слов');
    expect(trn('n_words', 11), '11 слов', reason: '11 — исключение из правила');
    expect(trn('n_words', 21), '21 слово');
    expect(trn('n_words', 22), '22 слова');
    expect(trn('n_words', 112), '112 слов', reason: '12 — тоже исключение');
    expect(trn('n_words', 0), '0 слов');
  });

  test('пары считаются по тем же правилам', () async {
    await LocaleController.instance.setCode('ru');
    expect(trn('n_pairs', 1), '1 пару');
    expect(trn('n_pairs', 3), '3 пары');
    expect(trn('n_pairs', 7), '7 пар');
  });

  test('в языках без падежей — единственное и множественное', () async {
    await LocaleController.instance.setCode('en');
    expect(trn('n_words', 1), '1 word');
    expect(trn('n_words', 5), '5 words');

    await LocaleController.instance.setCode('de');
    expect(trn('n_words', 1), '1 Wort');
    expect(trn('n_words', 5), '5 Wörter');
  });
}
