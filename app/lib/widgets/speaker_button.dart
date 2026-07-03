import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/strings.dart';
import '../services/tts_service.dart';

/// Небольшая кнопка-динамик: озвучивает слово на изучаемом языке.
class SpeakerButton extends StatelessWidget {
  final String text;
  final String languageCode;
  final double size;
  final Color? color;

  const SpeakerButton({
    super.key,
    required this.text,
    required this.languageCode,
    this.size = 20,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IconButton(
      icon: Icon(Icons.volume_up_rounded, size: size),
      color: color ?? scheme.onSurfaceVariant,
      tooltip: tr('listen'),
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(),
      padding: const EdgeInsets.all(6),
      onPressed: () {
        HapticFeedback.selectionClick();
        TtsService.instance.speak(text, languageCode);
      },
    );
  }
}
