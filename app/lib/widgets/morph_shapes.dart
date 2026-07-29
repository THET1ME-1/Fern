import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:material_new_shapes/material_new_shapes.dart' as ms;

import '../theme/app_theme.dart';
import '../theme/fern_shapes.dart';

/// Перетекание между силуэтами M3. Перенесено из Wickly, где отработано на
/// плитках привычек, пустых экранах и ожидании.
///
/// Пакет импортируется с префиксом: его `Cubic` сталкивается с `Cubic` из
/// `flutter/animation`, и без префикса файл не собирается.

/// Вписывает готовый путь [raw] в прямоугольник [size] по центру.
///
/// Пакет отдаёт путь в своих координатах, а виджету нужен ровно его размер.
/// По умолчанию пропорции сохраняются. [stretch] растягивает силуэт по обеим
/// осям — это нужно засечкам прогресса: в полосе высотой десять пикселей
/// фигура иначе схлопывается в точку по центру сегмента.
Path fitPathToSize(Path raw, Size size, {bool stretch = false}) {
  final b = raw.getBounds();
  if (b.width == 0 || b.height == 0) return raw;
  final sx = stretch
      ? size.width / b.width
      : math.min(size.width / b.width, size.height / b.height);
  final sy = stretch ? size.height / b.height : sx;
  final dx = (size.width - b.width * sx) / 2 - b.left * sx;
  final dy = (size.height - b.height * sy) / 2 - b.top * sy;
  final storage = Float64List.fromList(<double>[
    sx, 0, 0, 0, //
    0, sy, 0, 0, //
    0, 0, 1, 0, //
    dx, dy, 0, 1, //
  ]);
  return raw.transform(storage);
}

/// Морфы между парами форм живут в кэше.
///
/// `Morph` при создании ищет соответствие вершин — считать это заново на
/// каждый кадр расточительно, а пар в приложении десяток.
final Map<(int, int), ms.Morph> _morphs = {};

ms.Morph morphBetween(ms.RoundedPolygon from, ms.RoundedPolygon to) {
  final key = (identityHashCode(from), identityHashCode(to));
  return _morphs[key] ??= ms.Morph(from, to);
}

/// Форма, перетекающая из [from] в [to] вслед за [progress].
///
/// Заливку и обводку рисует сам виджет, [child] обрезается по форме.
/// Смена [progress] анимируется сама: ставьте 0 или 1 и не заводите контроллер.
class MorphShape extends StatelessWidget {
  final ms.RoundedPolygon from;
  final ms.RoundedPolygon to;

  /// 0 — форма [from], 1 — форма [to].
  final double progress;

  final Duration duration;
  final Curve curve;

  final Color? fill;
  final Color? border;
  final double borderWidth;

  /// Сторона квадрата. Без него форма занимает то, что дадут ограничения.
  final double? size;

  /// Растягивать силуэт по обеим осям вместо вписывания по меньшей стороне.
  final bool stretch;

  final Widget? child;

  const MorphShape({
    super.key,
    required this.from,
    required this.to,
    required this.progress,
    this.duration = const Duration(milliseconds: 320),
    this.curve = AppTheme.emphasized,
    this.fill,
    this.border,
    this.borderWidth = 2,
    this.size,
    this.stretch = false,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: progress.clamp(0.0, 1.0)),
      duration: duration,
      curve: curve,
      builder: (context, t, child) {
        final morph = morphBetween(from, to);
        return SizedBox(
          width: size,
          height: size,
          child: CustomPaint(
            // Без ребёнка CustomPaint схлопывается в нулевой размер, и форма
            // просто не рисуется. Когда сторона не задана — занимаем всё, что
            // дадут ограничения (так живут засечки прогресса).
            size: size == null ? Size.infinite : Size.square(size!),
            painter: MorphPainter(
              morph: morph,
              t: t,
              fill: fill,
              border: border,
              borderWidth: borderWidth,
              stretch: stretch,
            ),
            child: child == null
                ? null
                : ClipPath(
                    clipper: MorphClipper(morph, t, stretch: stretch),
                    child: Center(child: child),
                  ),
          ),
        );
      },
      child: child,
    );
  }
}

/// Обрезка по морфящейся форме.
class MorphClipper extends CustomClipper<Path> {
  final ms.Morph morph;
  final double t;
  final bool stretch;

  const MorphClipper(this.morph, this.t, {this.stretch = false});

  @override
  Path getClip(Size size) =>
      fitPathToSize(morph.toPath(progress: t), size, stretch: stretch);

  @override
  bool shouldReclip(covariant MorphClipper old) =>
      old.t != t || old.morph != morph || old.stretch != stretch;
}

/// Рисует силуэт морфа. Публичный, потому что обложки колод держат свой
/// контроллер и рисуют форму сами.
class MorphPainter extends CustomPainter {
  final ms.Morph morph;
  final double t;
  final Color? fill;
  final Color? border;
  final double borderWidth;
  final bool stretch;

  const MorphPainter({
    required this.morph,
    required this.t,
    required this.fill,
    required this.border,
    required this.borderWidth,
    this.stretch = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (fill == null && border == null) return;
    // Обводка рисуется по центру линии — ужимаем путь на её половину, иначе
    // край срезается границей виджета.
    final inset = border == null ? 0.0 : borderWidth / 2;
    final box = Size(size.width - inset * 2, size.height - inset * 2);
    if (box.width <= 0 || box.height <= 0) return;
    final path = fitPathToSize(
      morph.toPath(progress: t),
      box,
      stretch: stretch,
    ).shift(Offset(inset, inset));

    if (fill != null) {
      canvas.drawPath(path, Paint()..color = fill!);
    }
    if (border != null) {
      canvas.drawPath(
        path,
        Paint()
          ..color = border!
          ..style = PaintingStyle.stroke
          ..strokeWidth = borderWidth,
      );
    }
  }

  @override
  bool shouldRepaint(covariant MorphPainter old) =>
      old.t != t ||
      old.fill != fill ||
      old.border != border ||
      old.borderWidth != borderWidth ||
      old.stretch != stretch ||
      old.morph != morph;
}

/// Значок, который бесконечно перетекает по кругу спокойных форм.
///
/// Ставится там, где ждём ответа не от нас: перевод, разбор книги, сеть.
/// Анимация вечная, поэтому показывать её можно только на время ожидания:
/// `pumpAndSettle` в тестах на такой виджет не сходится.
class MorphPulse extends StatefulWidget {
  final double size;
  final Color color;
  final List<ms.RoundedPolygon> ring;

  const MorphPulse({
    super.key,
    this.size = 24,
    required this.color,
    required this.ring,
  });

  @override
  State<MorphPulse> createState() => _MorphPulseState();
}

class _MorphPulseState extends State<MorphPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: 420 * widget.ring.length),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ring = widget.ring;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final total = _c.value * ring.length;
        final index = total.floor() % ring.length;
        final local = Curves.easeInOut.transform(total - total.floor());
        return SizedBox(
          width: widget.size,
          height: widget.size,
          child: Transform.rotate(
            angle: _c.value * 2 * math.pi,
            child: CustomPaint(
              painter: MorphPainter(
                morph: morphBetween(
                  ring[index],
                  ring[(index + 1) % ring.length],
                ),
                t: local,
                fill: widget.color,
                border: null,
                borderWidth: 0,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Ожидание ответа не от нас: перевод слова, разбор книги, распознавание,
/// сеть. Силуэт перетекает по спокойному кольцу форм вместо системного кружка.
///
/// Держит вечную анимацию, поэтому в виджет-тестах `pumpAndSettle` на экране
/// с ним не сходится — такой экран ждут через `pump(duration)`.
class Waiting extends StatelessWidget {
  final double size;
  final Color? color;

  const Waiting({super.key, this.size = 28, this.color});

  @override
  Widget build(BuildContext context) => MorphPulse(
    size: size,
    color: color ?? Theme.of(context).colorScheme.primary,
    ring: FernShapes.waitingRing,
  );
}
