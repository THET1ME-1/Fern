import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/fern_shapes.dart';
import 'goal_ring.dart';
import 'morph_shapes.dart';

/// Кольцо покрытия книги: сколько текста человек уже понимает.
///
/// Силуэт за кольцом набирает вершины вместе с процентом — круг на половине
/// текста, двенадцатигранник у комфортных 95%. Число само по себе ничего не
/// говорит о том, далеко ли до свободного чтения, а форма показывает путь.
class CoverageRing extends StatelessWidget {
  /// Доля понятного текста, 0..1.
  final double known;

  final double size;
  final double strokeWidth;
  final Color color;
  final Color trackColor;
  final Widget? child;

  const CoverageRing({
    super.key,
    required this.known,
    required this.color,
    required this.trackColor,
    this.size = 72,
    this.strokeWidth = 8,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          MorphShape(
            key: const ValueKey('coverage-bloom'),
            from: FernShapes.coverageLow,
            to: FernShapes.coverageHigh,
            progress: FernShapes.coverageMorph(known),
            size: size,
            duration: const Duration(milliseconds: 720),
            curve: AppTheme.emphasizedDecelerate,
            fill: color.withValues(alpha: 0.16),
          ),
          GoalRing(
            progress: known,
            size: size,
            strokeWidth: strokeWidth,
            color: color,
            trackColor: trackColor,
            // Праздник формы занят дневной целью: здесь силуэт говорит о
            // покрытии, и второй жест на том же экране сбивал бы смысл.
            celebrate: false,
            child: child,
          ),
        ],
      ),
    );
  }
}
