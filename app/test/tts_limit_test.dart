import 'package:flutter_test/flutter_test.dart';

import 'package:fern/services/tts_service.dart';

void main() {
  group('TtsService.speechLimit', () {
    test('короткому слову хватает минимума на запуск движка', () {
      expect(TtsService.speechLimit('book').inSeconds, 6);
    });

    test('длина абзаца поднимает потолок', () {
      final para = 'a' * 600;
      expect(TtsService.speechLimit(para).inSeconds, 66);
    });

    test('целая глава не поднимает потолок выше трёх минут', () {
      expect(TtsService.speechLimit('a' * 100000).inSeconds, 180);
    });
  });
}
