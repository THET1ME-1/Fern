import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../theme/app_theme.dart';
import 'deck_shapes.dart';

/// Пресет-цвета обложек колод (единый источник для главного экрана,
/// редактора колоды и экрана пака).
const List<Color> kDeckPalette = [
  Color(0xFF2E7D5B),
  Color(0xFF3F6FB0),
  Color(0xFFB5622E),
  Color(0xFF8A4FBF),
  Color(0xFFB03F6F),
  Color(0xFF4FA0A8),
  Color(0xFF7A8B2E),
  Color(0xFFB0873F),
];

/// Плитка колоды на сетке: обложка-фигура, название, число карт и бейдж «к
/// повтору». Переиспользуется на главном экране и внутри пака.
class DeckCoverCard extends StatelessWidget {
  final String name;
  final Color color;
  final int shapeIndex;
  final int total;
  final int due;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  /// Режим множественного выбора: обводка + галочка вместо обычного вида.
  final bool selectable;
  final bool selected;

  const DeckCoverCard({
    super.key,
    required this.name,
    required this.color,
    required this.shapeIndex,
    required this.total,
    required this.due,
    required this.onTap,
    this.onLongPress,
    this.selectable = false,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected
              ? scheme.primaryContainer.withValues(alpha: 0.6)
              : scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(28),
          border: selected
              ? Border.all(color: scheme.primary, width: 2)
              : null,
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ShapedCover(
                    label: name,
                    color: color,
                    imagePath: null,
                    size: 84,
                    shape: deckShape(shapeIndex),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    name,
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: AppTheme.displayFont,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: scheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    trf('cards_n', {'n': total}),
                    style: TextStyle(
                      fontFamily: AppTheme.bodyFont,
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (due > 0 && !selectable) _dueBadge(scheme, due),
            if (selectable)
              Positioned(
                top: -4,
                right: -4,
                child: Icon(
                  selected
                      ? Icons.check_circle_rounded
                      : Icons.circle_outlined,
                  color: selected ? scheme.primary : scheme.onSurfaceVariant,
                  size: 24,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Плитка пака — визуально НЕ похожа на колоду: тонированный фон в цвет пака,
/// рамка и «стопка карточек» вместо одной обложки. Сразу читается как «папка».
class PackCoverCard extends StatelessWidget {
  final String name;
  final Color color;

  /// Цвета первых колод внутри (для стопки). Может быть пустым.
  final List<Color> deckColors;
  final int deckCount;
  final int due;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const PackCoverCard({
    super.key,
    required this.name,
    required this.color,
    required this.deckColors,
    required this.deckCount,
    required this.due,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tint = Color.alphaBlend(
      color.withValues(alpha: 0.16),
      scheme.surfaceContainerHigh,
    );
    // Три цвета для стопки: реальные колоды + оттенки цвета пака.
    final colors = <Color>[
      ...deckColors.take(3),
      color,
      Color.alphaBlend(Colors.white.withValues(alpha: 0.18), color),
      Color.alphaBlend(Colors.black.withValues(alpha: 0.18), color),
    ];

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: tint,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: color.withValues(alpha: 0.5), width: 1.5),
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _StackGlyph(colors: colors),
                  const SizedBox(height: 14),
                  Text(
                    name,
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: AppTheme.displayFont,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: scheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    trn('n_decks', deckCount),
                    style: TextStyle(
                      fontFamily: AppTheme.bodyFont,
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            // Метка «пак» в углу — усиливает отличие от колоды.
            Positioned(
              left: -2,
              top: -2,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.layers_rounded,
                    size: 15, color: _onColor(color)),
              ),
            ),
            if (due > 0) _dueBadge(scheme, due),
          ],
        ),
      ),
    );
  }
}

/// «Стопка карточек» — три скруглённых квадрата, слегка повёрнутые веером.
class _StackGlyph extends StatelessWidget {
  final List<Color> colors;
  const _StackGlyph({required this.colors});

  @override
  Widget build(BuildContext context) {
    Widget card(Color c, double angle, double dx) => Transform.translate(
          offset: Offset(dx, 0),
          child: Transform.rotate(
            angle: angle,
            child: Container(
              width: 52,
              height: 66,
              decoration: BoxDecoration(
                color: c,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 6,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
            ),
          ),
        );
    return SizedBox(
      width: 90,
      height: 84,
      child: Stack(
        alignment: Alignment.center,
        children: [
          card(colors[2], -0.20, -20),
          card(colors[1], 0.20, 20),
          card(colors[0], 0, 0),
        ],
      ),
    );
  }
}

/// Пунктирная плитка «+» (создать колоду/пак).
class AddDashedCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const AddDashedCard({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: CustomPaint(
        painter: _DashedBorderPainter(color: scheme.outline),
        child: Container(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 84,
                  height: 84,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 40, color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 12),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: AppTheme.bodyFont,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Widget _dueBadge(ColorScheme scheme, int due) => Positioned(
      top: -2,
      right: -2,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: scheme.primary,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          '$due',
          style: TextStyle(
            fontFamily: AppTheme.displayFont,
            fontWeight: FontWeight.w800,
            fontSize: 13,
            color: scheme.onPrimary,
          ),
        ),
      ),
    );

Color _onColor(Color c) =>
    c.computeLuminance() > 0.5 ? Colors.black : Colors.white;

class _DashedBorderPainter extends CustomPainter {
  final Color color;
  _DashedBorderPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(28),
    );
    final path = Path()..addRRect(rrect);
    const dash = 7.0;
    const gap = 5.0;
    for (final metric in path.computeMetrics()) {
      var dist = 0.0;
      while (dist < metric.length) {
        canvas.drawPath(metric.extractPath(dist, dist + dash), paint);
        dist += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter old) => old.color != color;
}
