import 'package:flutter_test/flutter_test.dart';

import 'package:fern/services/clip_audio_service.dart';
import 'package:fern/services/tts_service.dart';

void main() {
  group('потолки ожидания звука', () {
    test('сегмент видео ждём его длительность плюс запас на буферизацию', () {
      // Слово в субтитрах — секунда-полторы; ждать его дольше десяти секунд
      // незачем, дальше это зависшая крутилка на кнопке динамика.
      expect(ClipAudioService.playLimit(10000, 11500).inMilliseconds, 11500);
    });

    test('длинный сегмент поднимает потолок вместе с собой', () {
      expect(ClipAudioService.playLimit(0, 60000).inSeconds, 70);
    });

    test('озвучка слова и озвучка абзаца ждут по-разному', () {
      final word = TtsService.speechLimit('book');
      final para = TtsService.speechLimit('a' * 900);
      expect(word.inSeconds, lessThan(para.inSeconds));
    });
  });
}
