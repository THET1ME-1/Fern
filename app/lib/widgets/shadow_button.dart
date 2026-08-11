import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/strings.dart';
import '../services/tts_service.dart';
import '../services/voice_recorder.dart';
import 'pressable.dart';

/// «Повтори за диктором»: слушаешь эталон, записываешь себя, слушаешь обе
/// дорожки подряд.
///
/// Балла за произношение нет намеренно: офлайн его нечем посчитать, а
/// нарисованный процент врал бы. Разницу человек слышит сам — на этом стоит
/// вся техника shadowing.
class ShadowButton extends StatefulWidget {
  /// Что произносим (слово или предложение).
  final String text;

  /// Язык изучения — на нём говорит синтезатор.
  final String languageCode;

  const ShadowButton({
    super.key,
    required this.text,
    required this.languageCode,
  });

  @override
  State<ShadowButton> createState() => _ShadowButtonState();
}

class _ShadowButtonState extends State<ShadowButton> {
  final VoiceRecorder _recorder = VoiceRecorder.instance;
  bool _recording = false;
  bool _hasTake = false;

  @override
  void dispose() {
    // Дорожка живёт ровно до ухода с карточки.
    _recorder.discard();
    super.dispose();
  }

  Future<void> _toggleRecord() async {
    HapticFeedback.selectionClick();
    if (_recording) {
      await _recorder.stop();
      if (!mounted) return;
      setState(() {
        _recording = false;
        _hasTake = _recorder.hasTake;
      });
      return;
    }
    final started = await _recorder.start();
    if (!mounted) return;
    if (!started) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(tr('mic_denied'))));
      return;
    }
    setState(() => _recording = true);
  }

  /// Эталон и своя дорожка подряд: сравнивать по памяти через полминуты
  /// бесполезно, разница слышна только вплотную.
  Future<void> _compare() async {
    HapticFeedback.selectionClick();
    await TtsService.instance.speak(widget.text, widget.languageCode);
    await Future<void>.delayed(const Duration(milliseconds: 250));
    await _recorder.playTake();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        PressableScale(
          child: FilledButton.tonalIcon(
            onPressed: _toggleRecord,
            style: FilledButton.styleFrom(
              backgroundColor:
                  _recording ? scheme.tertiaryContainer : null,
            ),
            icon: Icon(
              _recording ? Icons.stop_rounded : Icons.mic_rounded,
              size: 20,
            ),
            label: Text(_recording ? tr('shadow_stop') : tr('shadow_record')),
          ),
        ),
        if (_hasTake && !_recording) ...[
          const SizedBox(width: 10),
          PressableScale(
            child: FilledButton.tonalIcon(
              onPressed: _compare,
              icon: const Icon(Icons.compare_arrows_rounded, size: 20),
              label: Text(tr('shadow_compare')),
            ),
          ),
        ],
      ],
    );
  }
}

