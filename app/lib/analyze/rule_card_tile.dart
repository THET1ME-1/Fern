import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/strings.dart';
import '../services/construction_catalog.dart';
import '../theme/app_theme.dart';
import '../widgets/pressable.dart';

/// Найденное в тексте правило: название, уровень, объяснение и кнопка «Учить».
///
/// Показывается и в разборе, и на экране грамматики, поэтому знает только про
/// [Construction] и два колбэка — свои экраны решают, что делать дальше.
class RuleCardTile extends StatelessWidget {
  final Construction rule;

  /// Оборот из текста человека («have been waiting») — то, ради чего правило
  /// вообще показывают: оно найдено в его предложении, а не в учебнике.
  final String snippet;

  /// Правило уже взято карточкой.
  final bool learned;

  /// Взять правило в колоду грамматики. null — кнопки нет.
  final VoidCallback? onLearn;

  const RuleCardTile({
    super.key,
    required this.rule,
    this.snippet = '',
    this.learned = false,
    this.onLearn,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  rule.name,
                  style: TextStyle(
                    fontFamily: AppTheme.displayFont,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: scheme.onSurface,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _levelChip(scheme),
            ],
          ),
          if (snippet.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              snippet.trim(),
              style: TextStyle(
                fontFamily: AppTheme.wordFont,
                fontWeight: FontWeight.w600,
                fontSize: 15,
                color: scheme.primary,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            rule.hint(),
            style: TextStyle(
              fontFamily: AppTheme.bodyFont,
              fontSize: 14,
              height: 1.4,
              color: scheme.onSurfaceVariant,
            ),
          ),
          if (onLearn != null || learned) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: PressableScale(
                child: learned
                    ? _learnedChip(scheme)
                    : FilledButton.tonalIcon(
                        onPressed: () {
                          HapticFeedback.selectionClick();
                          onLearn?.call();
                        },
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: Text(tr('rule_learn')),
                      ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _levelChip(ColorScheme scheme) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: scheme.secondaryContainer,
          borderRadius: BorderRadius.circular(30),
        ),
        child: Text(
          rule.level,
          style: TextStyle(
            fontFamily: AppTheme.bodyFont,
            fontWeight: FontWeight.w700,
            fontSize: 11.5,
            letterSpacing: 0.6,
            color: scheme.onSecondaryContainer,
          ),
        ),
      );

  Widget _learnedChip(ColorScheme scheme) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle_rounded, size: 18, color: scheme.tertiary),
          const SizedBox(width: 6),
          Text(
            tr('rule_learned'),
            style: TextStyle(
              fontFamily: AppTheme.bodyFont,
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: scheme.tertiary,
            ),
          ),
        ],
      );
}

