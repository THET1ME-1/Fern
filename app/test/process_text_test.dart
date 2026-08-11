import 'package:flutter_test/flutter_test.dart';

import 'package:fern/services/process_text.dart';

void main() {
  test('короткое выделение ведёт в перевод, длинное — в разбор', () {
    expect(ProcessText.looksLikeWord('serendipity'), isTrue);
    expect(ProcessText.looksLikeWord('give up'), isTrue);
    expect(ProcessText.looksLikeWord('  spaced   out  '), isTrue);
    expect(
      ProcessText.looksLikeWord('I have been waiting for an hour.'),
      isFalse,
    );
  });

  test('слова считаются без пустых кусков', () {
    expect(ProcessText.wordCount('  one   two \n three '), 3);
    expect(ProcessText.wordCount('   '), 0);
  });
}
