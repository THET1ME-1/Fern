import 'dart:math';

import 'package:flutter/material.dart';

/// Лёгкий салют-конфетти без внешних пакетов: пачка частиц разлетается сверху,
/// падает под «гравитацией» и гаснет. Проигрывается один раз и зовёт [onDone].
///
/// Кладётся в [Stack] поверх контента (`IgnorePointer` — не перехватывает тапы).
class ConfettiOverlay extends StatefulWidget {
  final VoidCallback? onDone;
  final int count;
  const ConfettiOverlay({super.key, this.onDone, this.count = 90});

  @override
  State<ConfettiOverlay> createState() => _ConfettiOverlayState();
}

class _ConfettiOverlayState extends State<ConfettiOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final List<_Particle> _particles;

  static const List<Color> _palette = [
    Color(0xFF2E9E6B),
    Color(0xFFDDA13F),
    Color(0xFF5B8DEF),
    Color(0xFFB03F6F),
    Color(0xFF8A4FBF),
    Color(0xFF4FA0A8),
  ];

  @override
  void initState() {
    super.initState();
    final rng = Random();
    _particles = [
      for (var i = 0; i < widget.count; i++)
        _Particle(
          x: rng.nextDouble(),
          delay: rng.nextDouble() * 0.25,
          vx: (rng.nextDouble() - 0.5) * 0.5,
          size: 6 + rng.nextDouble() * 8,
          color: _palette[rng.nextInt(_palette.length)],
          spin: (rng.nextDouble() - 0.5) * 12,
          rot0: rng.nextDouble() * pi,
        ),
    ];
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..addStatusListener((s) {
        if (s == AnimationStatus.completed) widget.onDone?.call();
      });
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (_, _) => CustomPaint(
            size: Size.infinite,
            painter: _ConfettiPainter(_particles, _ctrl.value),
          ),
        ),
      ),
    );
  }
}

class _Particle {
  final double x; // старт по горизонтали (0..1)
  final double delay; // задержка старта (0..1)
  final double vx; // горизонтальный дрейф
  final double size;
  final Color color;
  final double spin; // скорость вращения
  final double rot0; // стартовый угол
  const _Particle({
    required this.x,
    required this.delay,
    required this.vx,
    required this.size,
    required this.color,
    required this.spin,
    required this.rot0,
  });
}

class _ConfettiPainter extends CustomPainter {
  final List<_Particle> particles;
  final double t;
  _ConfettiPainter(this.particles, this.t);

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in particles) {
      final local = ((t - p.delay) / (1 - p.delay)).clamp(0.0, 1.0);
      if (local <= 0) continue;
      // Вертикаль: ускоряющееся падение; старт чуть выше экрана.
      final y = (-0.1 + local * local * 1.25) * size.height;
      final x = (p.x + p.vx * local) * size.width;
      final opacity = local < 0.75 ? 1.0 : (1 - (local - 0.75) / 0.25);
      final paint = Paint()..color = p.color.withValues(alpha: opacity.clamp(0, 1));
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(p.rot0 + p.spin * local);
      canvas.drawRect(
        Rect.fromCenter(center: Offset.zero, width: p.size, height: p.size * 0.6),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter old) => old.t != t;
}
