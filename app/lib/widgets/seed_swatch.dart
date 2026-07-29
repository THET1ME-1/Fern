import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/fern_shapes.dart';
import 'morph_shapes.dart';

/// Кружок-превью цветовой схемы: 4 квадранта из тонов, сгенерированных из
/// seed-цвета (как в пикере Material You), вместо скучной одноцветной точки.
class SeedSwatch extends StatelessWidget {
  final Color seed;
  final bool selected;
  final double size;
  final VoidCallback? onTap;
  const SeedSwatch({
    super.key,
    required this.seed,
    this.selected = false,
    this.size = 44,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Схема из seed (светлая — пастельные, читаемые тона на любом фоне, как в
    // системном пикере). Совпадает с тем, как тему строит AppTheme.
    final s = ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.light);
    final scheme = Theme.of(context).colorScheme;
    final quads = <Color>[
      s.primaryContainer, // ↖ светлый
      s.primary, //          ↗ насыщенный
      s.tertiaryContainer, //↙ светлый, другой оттенок
      s.tertiary, //         ↘ насыщенный, другой оттенок
    ];
    // Выбранная схема распускается из круга: тот же жест, что у цели и
    // навигации, только здесь он отмечает выбор.
    final morph = morphBetween(FernShapes.swatchIdle, FernShapes.swatchPicked);
    return GestureDetector(
      onTap: onTap,
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: selected ? 1.0 : 0.0),
        duration: const Duration(milliseconds: 420),
        curve: AppTheme.emphasized,
        builder: (context, t, _) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: MorphPainter(
            morph: morph,
            t: t,
            fill: null,
            border: Color.lerp(scheme.outlineVariant, scheme.onSurface, t),
            borderWidth: 1 + 2 * t,
          ),
          child: ClipPath(
            clipper: MorphClipper(morph, t),
            child: CustomPaint(
            painter: _QuadrantPainter(quads),
            child: selected
                ? Center(
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.38),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.check_rounded,
                          color: Colors.white, size: size * 0.34),
                    ),
                  )
                : null,
          ),
          ),
        ),
        ),
      ),
    );
  }
}

/// Заливает круг четырьмя квадрантами: TL, TR, BL, BR.
class _QuadrantPainter extends CustomPainter {
  final List<Color> colors;
  _QuadrantPainter(this.colors);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final p = Paint()..style = PaintingStyle.fill;
    p.color = colors[0];
    canvas.drawRect(Rect.fromLTWH(0, 0, w / 2, h / 2), p);
    p.color = colors[1];
    canvas.drawRect(Rect.fromLTWH(w / 2, 0, w / 2, h / 2), p);
    p.color = colors[2];
    canvas.drawRect(Rect.fromLTWH(0, h / 2, w / 2, h / 2), p);
    p.color = colors[3];
    canvas.drawRect(Rect.fromLTWH(w / 2, h / 2, w / 2, h / 2), p);
  }

  @override
  bool shouldRepaint(covariant _QuadrantPainter old) =>
      old.colors[0] != colors[0] ||
      old.colors[1] != colors[1] ||
      old.colors[2] != colors[2] ||
      old.colors[3] != colors[3];
}
