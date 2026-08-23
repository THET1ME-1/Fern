import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

/// Проигрывание живого голоса из видео в повторах: тянет аудиодорожку YouTube
/// и играет ровно сегмент `[startMs, endMs]` (без скачивания файла — стрим +
/// клип). URL дорожки кэшируется на сессию; при протухании перезапрашивается.
///
/// Требует сети. Если не удалось (офлайн/URL умер) — вызывающий откатывается на
/// робота (TTS).
class ClipAudioService {
  ClipAudioService._();
  static final ClipAudioService instance = ClipAudioService._();

  final AudioPlayer _player = AudioPlayer();
  final YoutubeExplode _yt = YoutubeExplode();
  final Map<String, Uri> _urlCache = {};

  /// Потолки на каждый шаг. `play()` в just_audio завершается не в момент
  /// старта, а когда сегмент доиграл: сеть встала на буферизации — и ожидание
  /// не кончается, кнопка динамика застывает с крутилкой.
  static const Duration _manifestLimit = Duration(seconds: 15);
  static const Duration _openLimit = Duration(seconds: 20);

  /// Сколько ждать сам сегмент: его длительность плюс запас на буферизацию.
  @visibleForTesting
  static Duration playLimit(int startMs, int endMs) =>
      Duration(milliseconds: endMs - startMs) + const Duration(seconds: 10);

  /// Проигрывает сегмент видео. Возвращает true при успехе.
  Future<bool> playClip(String sourceUrl, int startMs, int endMs) async {
    final id = VideoId.parseVideoId(sourceUrl);
    if (id == null || endMs <= startMs) return false;
    try {
      final url = await _audioUrl(id);
      if (url == null) return false;
      await _player.setUrl(url.toString()).timeout(_openLimit);
      await _player.setClip(
        start: Duration(milliseconds: startMs),
        end: Duration(milliseconds: endMs),
      );
      // Небольшой хвост, чтобы слово не обрывалось на последнем слоге.
      try {
        await _player.play().timeout(playLimit(startMs, endMs));
      } on TimeoutException {
        // Застряли на буферизации: снимаем плеер с паузы ожидания, иначе он
        // продолжит тянуть поток в фоне.
        await stop();
      }
      return true;
    } catch (e) {
      _urlCache.remove(id); // возможно, ссылка протухла — сбросим кэш
      debugPrint('ClipAudioService.playClip failed: $e');
      return false;
    }
  }

  Future<Uri?> _audioUrl(String id) async {
    final cached = _urlCache[id];
    if (cached != null) return cached;
    final manifest =
        await _yt.videos.streamsClient.getManifest(id).timeout(_manifestLimit);
    if (manifest.audioOnly.isEmpty) return null;
    final url = manifest.audioOnly.withHighestBitrate().url;
    _urlCache[id] = url;
    return url;
  }

  Future<void> stop() async {
    try {
      await _player.stop();
    } catch (_) {}
  }
}
