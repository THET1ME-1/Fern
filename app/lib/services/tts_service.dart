import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Озвучка слов (Text-to-Speech). Тонкая обёртка над [FlutterTts]:
/// сопоставляет код изучаемого языка с локалью движка и мягко проглатывает
/// ошибки (если движок/язык недоступен — просто молчим, без падений).
class TtsService {
  TtsService._();
  static final TtsService instance = TtsService._();

  final FlutterTts _tts = FlutterTts();
  bool _init = false;

  /// Код изучаемого языка → локаль TTS.
  static const Map<String, String> _localeFor = {
    'en': 'en-US',
    'es': 'es-ES',
    'de': 'de-DE',
    'fr': 'fr-FR',
    'it': 'it-IT',
    'pt': 'pt-PT',
    'tr': 'tr-TR',
    'zh': 'zh-CN',
    'ja': 'ja-JP',
    'ko': 'ko-KR',
    'ar': 'ar-SA',
    'ru': 'ru-RU',
  };

  Future<void> _ensureInit() async {
    if (_init) return;
    _init = true;
    try {
      await _tts.setSpeechRate(0.45); // чуть медленнее — разборчивее для учёбы
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);
      await _tts.awaitSpeakCompletion(true);
    } catch (_) {
      /* движок недоступен — озвучка просто не сработает */
    }
  }

  /// Произносит [text] на языке [languageCode] (код изучаемого языка).
  Future<void> speak(String text, String languageCode) async {
    final t = text.trim();
    if (t.isEmpty) return;
    await _ensureInit();
    final locale = _localeFor[languageCode] ?? languageCode;
    try {
      await _tts.stop();
      await _tts.setLanguage(locale);
      await _tts.speak(t);
    } catch (e) {
      debugPrint('TTS speak failed: $e');
    }
  }

  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }

  /// Доступна ли озвучка для языка (для показа/скрытия кнопки динамика).
  Future<bool> isAvailable(String languageCode) async {
    await _ensureInit();
    final locale = _localeFor[languageCode] ?? languageCode;
    try {
      final res = await _tts.isLanguageAvailable(locale);
      return res == true;
    } catch (_) {
      return false;
    }
  }
}
