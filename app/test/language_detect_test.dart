import 'package:flutter_test/flutter_test.dart';

import 'package:fern/services/language_detect.dart';

void main() {
  group('LanguageDetect', () {
    test('русский текст → ru', () {
      expect(
        LanguageDetect.detect(
            'Это был обычный день, и он шёл по улице не спеша, думая о том, что будет завтра.'),
        'ru',
      );
    });

    test('английский текст → en', () {
      expect(
        LanguageDetect.detect(
            'It was a bright cold day in April, and the clocks were striking thirteen.'),
        'en',
      );
    });

    test('немецкий текст → de', () {
      expect(
        LanguageDetect.detect(
            'Es war ein kalter Tag im April und die Uhren schlugen dreizehn. Das ist nicht gut.'),
        'de',
      );
    });

    test('японский (кана) → ja', () {
      expect(LanguageDetect.detect('これはテストです。ねこがすきです。'), 'ja');
    });

    test('пустой текст → null', () {
      expect(LanguageDetect.detect('   \n  '), isNull);
    });
  });
}
