import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../services/pos.dart';
import '../theme/app_theme.dart';

/// Тег части речи: «сущ.», «гл.», «нареч.».
///
/// Цвет закреплён за частью речи (`PosDetect.colors`) и работает во всём
/// приложении одинаково — в списке слов, в редакторе карточки и на вопросе
/// занятия, где метка снимает спор о значении: у `back` спрашивают спину, а не
/// «назад».
class PosBadge extends StatelessWidget {
  final String code;
  final double fontSize;

  const PosBadge({super.key, required this.code, this.fontSize = 11});

  @override
  Widget build(BuildContext context) {
    final color = Color(PosDetect.colorOf(code));
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: fontSize * 0.73,
        vertical: fontSize * 0.23,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        tr('pos_short_$code'),
        style: TextStyle(
          fontFamily: AppTheme.bodyFont,
          fontWeight: FontWeight.w700,
          fontSize: fontSize,
          color: color,
        ),
      ),
    );
  }
}
