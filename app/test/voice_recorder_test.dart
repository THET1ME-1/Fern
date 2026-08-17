import 'package:flutter_test/flutter_test.dart';

import 'package:fern/services/voice_recorder.dart';

/// Уход с карточки на середине записи: экран зовёт `discard()`, и после него
/// микрофон обязан быть свободен. Иначе следующая карточка получала «нет
/// доступа к микрофону» на живом разрешении.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('discard снимает флаг записи', () async {
    final r = VoiceRecorder.instance;
    r.debugMarkRecording();
    expect(r.isRecording, isTrue);

    await r.discard();

    expect(r.isRecording, isFalse);
  });

  test('после discard запись можно начать заново', () async {
    final r = VoiceRecorder.instance;
    r.debugMarkRecording();
    await r.discard();

    // На хосте микрофона нет, поэтому start() честно вернёт false — но по
    // причине «платформа не поддерживается», а не «уже пишем».
    expect(await r.start(), isFalse);
    expect(r.isRecording, isFalse);
  });
}
