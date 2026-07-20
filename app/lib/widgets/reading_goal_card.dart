import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../services/reading_goal.dart';
import '../theme/app_theme.dart';

/// Путь к свободному чтению книги.
///
/// Это витрина Fern Pro, и стоит она на цифрах собственной книги человека:
/// сколько слов текста он уже знает, сколько осталось до порога, за которым
/// словарь почти не нужен, и сколько это дней при его темпе. Перечень
/// поддерживаемых форматов файлов такого не продаёт.
class ReadingGoalCard extends StatelessWidget {
  const ReadingGoalCard({
    super.key,
    required this.goal,
    required this.pro,
    this.newPerDay = 12,
    this.onOpenPro,
    this.onStudy,
  });

  final ReadingGoal goal;

  /// Куплено ли Pro: от этого зависит только нижняя кнопка. Цифры видны всем —
  /// на них и держится желание купить.
  final bool pro;

  final int newPerDay;
  final VoidCallback? onOpenPro;
  final VoidCallback? onStudy;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.flag_rounded, size: 20, color: scheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  tr('goal_title'),
                  style: TextStyle(
                    fontFamily: AppTheme.displayFont,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: scheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (goal.reached)
            Text(
              tr('goal_reached'),
              style: TextStyle(fontSize: 15, color: scheme.onSurfaceVariant),
            )
          else ...[
            Text(
              trf('goal_know_share', {'n': (goal.coverage * 100).round()}),
              style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 10),
            Text(
              tr('goal_left'),
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
            Text(
              trn('n_words', goal.wordsToLearn),
              style: TextStyle(
                fontFamily: AppTheme.displayFont,
                fontWeight: FontWeight.w700,
                fontSize: 30,
                height: 1.1,
                color: scheme.primary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              trf('goal_pace', {
                'n': newPerDay,
                'days': trn('n_days', goal.days),
              }),
              style: TextStyle(fontSize: 14, color: scheme.onSurface),
            ),
            const SizedBox(height: 4),
            Text(
              trf('goal_target_hint', {'n': (goal.target * 100).round()}),
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 14),
            _Progress(goal: goal, scheme: scheme),
            const SizedBox(height: 16),
            if (pro)
              FilledButton.icon(
                onPressed: onStudy,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  shape: const StadiumBorder(),
                ),
                icon: const Icon(Icons.school_rounded, size: 20),
                label: Text(tr('goal_study')),
              )
            else
              FilledButton.icon(
                onPressed: onOpenPro,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  shape: const StadiumBorder(),
                ),
                icon: const Icon(Icons.auto_awesome_rounded, size: 20),
                label: Text(tr('goal_open_pro')),
              ),
          ],
        ],
      ),
    );
  }
}

/// Полоса от нынешнего покрытия к цели: видно, сколько пути позади.
class _Progress extends StatelessWidget {
  const _Progress({required this.goal, required this.scheme});

  final ReadingGoal goal;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final done = goal.target == 0 ? 0.0 : (goal.coverage / goal.target).clamp(0.0, 1.0);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: done),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOutCubic,
      builder: (_, value, _) => ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: LinearProgressIndicator(
          value: value,
          minHeight: 10,
          backgroundColor: scheme.surfaceContainerHighest,
          color: scheme.primary,
        ),
      ),
    );
  }
}
