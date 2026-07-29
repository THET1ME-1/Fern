import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/fern_shapes.dart';
import 'morph_shapes.dart';

/// Прогресс занятия.
///
/// Короткая сессия показывается засечками: видно, что осталось три карточки,
/// а не «где-то семьдесят процентов». Длинная — полосой, которая догоняет
/// значение пружиной, а не переставляется кадром.
class SessionProgress extends StatelessWidget {
  final int done;
  final int total;

  /// Дальше этого числа карточек засечки мельчают, и включается полоса.
  static const int segmentLimit = 12;

  const SessionProgress({super.key, required this.done, required this.total});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (total <= 0) return const SizedBox(height: 6);
    if (total <= segmentLimit) {
      return _Segments(done: done, total: total, scheme: scheme);
    }
    return TweenAnimationBuilder<double>(
      tween: Tween(end: (done / total).clamp(0.0, 1.0)),
      duration: const Duration(milliseconds: 620),
      curve: AppTheme.emphasizedDecelerate,
      builder: (_, value, _) => LinearProgressIndicator(
        value: value,
        minHeight: 6,
        backgroundColor: scheme.surfaceContainerHighest,
      ),
    );
  }
}

class _Segments extends StatelessWidget {
  final int done;
  final int total;
  final ColorScheme scheme;

  const _Segments({
    required this.done,
    required this.total,
    required this.scheme,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 12,
      child: Row(
        children: [
          for (var i = 0; i < total; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            Expanded(
              child: Center(
                // Силуэт не растягиваем: вытянутая «печенька» читается линзой.
                // Засечка остаётся квадратной, а ряд работает счётчиком.
                child: MorphShape(
                  key: ValueKey('seg-$i'),
                  from: FernShapes.segmentTodo,
                  to: FernShapes.segmentDone,
                  progress: i < done ? 1 : 0,
                  size: 12,
                  duration: const Duration(milliseconds: 420),
                  curve: Curves.easeOutBack,
                  fill: i < done
                      ? scheme.primary
                      : scheme.surfaceContainerHighest,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
