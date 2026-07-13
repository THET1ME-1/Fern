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
///
/// Пока звук готовится (стрим YouTube — это секунды), вместо иконки крутится
/// индикатор; если не вышло ни клипом, ни роботом — говорим об этом прямо.
class SpeakerButton extends StatefulWidget {
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

  @override
  State<SpeakerButton> createState() => _SpeakerButtonState();
}

class _SpeakerButtonState extends State<SpeakerButton> {
  bool _busy = false;

  bool get _hasLive =>
      widget.sourceUrl != null &&
      widget.sourceUrl!.isNotEmpty &&
      widget.clipStartMs != null &&
      widget.clipEndMs != null;

  Future<void> _play() async {
    if (_busy) return;
    HapticFeedback.selectionClick();
    setState(() => _busy = true);

    var ok = false;
    var noVoice = false;
    if (_hasLive) {
      ok = await ClipAudioService.instance
          .playClip(widget.sourceUrl!, widget.clipStartMs!, widget.clipEndMs!);
    }
    if (!ok) {
      // На части телефонов для изучаемого языка голоса просто нет (tr/pt/ko) —
      // тогда честнее сказать об этом, чем «проигрывать» тишину.
      if (await TtsService.instance.isAvailable(widget.languageCode)) {
        ok = await TtsService.instance.speak(widget.text, widget.languageCode);
      } else {
        noVoice = true;
      }
    }

    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
            content: Text(tr(noVoice ? 'tts_unavailable' : 'play_failed'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tint = widget.color ?? scheme.onSurfaceVariant;
    return IconButton(
      icon: _busy
          ? SizedBox(
              width: widget.size,
              height: widget.size,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: tint),
            )
          : Icon(
              _hasLive
                  ? Icons.record_voice_over_rounded
                  : Icons.volume_up_rounded,
              size: widget.size,
            ),
      color: tint,
      tooltip: tr('listen'),
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(),
      padding: const EdgeInsets.all(6),
      onPressed: _busy ? null : _play,
    );
  }
}
