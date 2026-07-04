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

  /// Проигрывает сегмент видео. Возвращает true при успехе.
  Future<bool> playClip(String sourceUrl, int startMs, int endMs) async {
    final id = VideoId.parseVideoId(sourceUrl);
    if (id == null || endMs <= startMs) return false;
    try {
      final url = await _audioUrl(id);
      if (url == null) return false;
      await _player.setUrl(url.toString());
      await _player.setClip(
        start: Duration(milliseconds: startMs),
        end: Duration(milliseconds: endMs),
      );
      // Небольшой хвост, чтобы слово не обрывалось на последнем слоге.
      await _player.play();
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
    final manifest = await _yt.videos.streamsClient.getManifest(id);
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
