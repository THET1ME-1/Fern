import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Кольцо прогресса дневной цели в духе Material 3: дуга с круглым концом
/// плавно заполняется от 0 до [progress] при появлении/изменении.
///
/// В центре — произвольный [child] (обычно число повторов за сегодня).
class GoalRing extends StatelessWidget {
  final double progress; // 0..1
  final double size;
  final double strokeWidth;
  final Color color;
  final Color trackColor;
  final Widget? child;

  const GoalRing({
    super.key,
    required this.progress,
    required this.color,
    required this.trackColor,
    this.size = 72,
    this.strokeWidth = 8,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: progress.clamp(0, 1)),
      duration: const Duration(milliseconds: 900),
      curve: AppTheme.emphasizedDecelerate,
      builder: (_, value, _) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _RingPainter(
            progress: value,
            color: color,
            trackColor: trackColor,
            strokeWidth: strokeWidth,
          ),
          child: Center(child: child),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  final Color color;
  final Color trackColor;
  final double strokeWidth;

  _RingPainter({
    required this.progress,
    required this.color,
    required this.trackColor,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (size.shortestSide - strokeWidth) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = trackColor;
    canvas.drawCircle(center, radius, track);

    if (progress <= 0) return;
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = color;
    const start = -math.pi / 2; // от 12 часов
    canvas.drawArc(rect, start, 2 * math.pi * progress, false, arc);
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.progress != progress ||
      old.color != color ||
      old.trackColor != trackColor ||
      old.strokeWidth != strokeWidth;
}
