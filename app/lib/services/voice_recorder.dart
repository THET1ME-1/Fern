import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// Запись собственного голоса для «повтори за диктором».
///
/// Оценки произношения здесь нет и не будет: честно посчитать её офлайн нечем,
/// а цветной балл «73%» без модели — это выдумка. Работает по-другому: человек
/// слышит эталон, слышит себя сразу следом и слышит разницу сам. Так ставят
/// произношение на занятиях с преподавателем.
class VoiceRecorder {
  VoiceRecorder._();

  static final VoiceRecorder instance = VoiceRecorder._();

  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();

  String? _lastPath;
  bool _recording = false;

  bool get isRecording => _recording;

  /// Есть ли записанная дорожка, которую можно послушать.
  bool get hasTake => _lastPath != null && File(_lastPath!).existsSync();

  bool get _supported => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// Спрашивает разрешение на микрофон.
  Future<bool> hasPermission() async {
    if (!_supported) return false;
    try {
      return await _recorder.hasPermission();
    } catch (e) {
      debugPrint('VoiceRecorder.hasPermission: $e');
      return false;
    }
  }

  /// Начинает запись. Возвращает false, если микрофон недоступен.
  Future<bool> start() async {
    if (!_supported || _recording) return false;
    if (!await hasPermission()) return false;
    try {
      final dir = await getTemporaryDirectory();
      // Файл один на всё приложение: дорожка нужна ровно до следующей записи,
      // копить их в кэше незачем.
      final path = '${dir.path}/fern_take.m4a';
      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc),
        path: path,
      );
      _lastPath = path;
      _recording = true;
      return true;
    } catch (e) {
      debugPrint('VoiceRecorder.start: $e');
      _recording = false;
      return false;
    }
  }

  /// Останавливает запись и возвращает путь к дорожке (или null).
  Future<String?> stop() async {
    if (!_recording) return null;
    _recording = false;
    try {
      final path = await _recorder.stop();
      _lastPath = path ?? _lastPath;
      return _lastPath;
    } catch (e) {
      debugPrint('VoiceRecorder.stop: $e');
      return null;
    }
  }

  /// Проигрывает записанное. Возвращает false, если играть нечего.
  Future<bool> playTake() async {
    final path = _lastPath;
    if (path == null || !File(path).existsSync()) return false;
    try {
      await _player.setFilePath(path);
      await _player.seek(Duration.zero);
      await _player.play();
      return true;
    } catch (e) {
      debugPrint('VoiceRecorder.playTake: $e');
      return false;
    }
  }

  Future<void> stopPlayback() async {
    try {
      await _player.stop();
    } catch (_) {/* уже остановлен */}
  }

  /// Убирает дорожку с диска (уход с экрана).
  Future<void> discard() async {
    await stopPlayback();
    final path = _lastPath;
    _lastPath = null;
    if (path == null) return;
    try {
      final file = File(path);
      if (file.existsSync()) await file.delete();
    } catch (e) {
      debugPrint('VoiceRecorder.discard: $e');
    }
  }

  Future<void> dispose() async {
    await discard();
    await _recorder.dispose();
    await _player.dispose();
  }
}

