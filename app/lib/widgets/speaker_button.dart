import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/strings.dart';
import '../services/clip_audio_service.dart';
import '../services/tts_service.dart';

/// Небольшая кнопка-динамик: озвучивает слово на изучаемом языке.
///
/// Если у карточки есть видео-источник и границы фрагмента ([sourceUrl] +
/// [clipStartMs]/[clipEndMs]) — играет **живой голос из видео**; иначе (или при
/// неудаче стрима) откатывается на робота (TTS).
class SpeakerButton extends StatelessWidget {
  final String text;
  final String languageCode;
  final double size;
  final Color? color;

  /// Данные для живого голоса (из разбора видео). Необязательны.
  final String? sourceUrl;
  final int? clipStartMs;
  final int? clipEndMs;

  const SpeakerButton({
    super.key,
    required this.text,
    required this.languageCode,
    this.size = 20,
    this.color,
    this.sourceUrl,
    this.clipStartMs,
    this.clipEndMs,
  });

  bool get _hasLive =>
      sourceUrl != null &&
      sourceUrl!.isNotEmpty &&
      clipStartMs != null &&
      clipEndMs != null;

  Future<void> _play() async {
    HapticFeedback.selectionClick();
    if (_hasLive) {
      final ok = await ClipAudioService.instance
          .playClip(sourceUrl!, clipStartMs!, clipEndMs!);
      if (ok) return;
    }
    await TtsService.instance.speak(text, languageCode);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IconButton(
      icon: Icon(
        _hasLive ? Icons.record_voice_over_rounded : Icons.volume_up_rounded,
        size: size,
      ),
      color: color ?? scheme.onSurfaceVariant,
      tooltip: tr('listen'),
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(),
      padding: const EdgeInsets.all(6),
      onPressed: _play,
    );
  }
}
