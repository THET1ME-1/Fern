import 'dart:io';

import 'package:flutter/material.dart';
import 'package:material_new_shapes/material_new_shapes.dart' as ms;

import '../theme/app_theme.dart';
import '../theme/fern_shapes.dart';
import 'morph_shapes.dart';

/// Обложки колод и паков живут на настоящих формах M3 (`MaterialShapes`).
/// Роли и порядок — в [FernShapes.deckCovers]; порядок записан в `Deck.shape`,
/// поэтому перестановка сменит обложки у существующих колод.

/// Сколько форм доступно на выбор.
int get deckShapeCount => FernShapes.deckCovers.length;

/// Силуэт по индексу, циклически.
ms.RoundedPolygon deckShape(int index) => FernShapes.deckCover(index);

/// Обложка колоды в произвольной форме: цвет заливает фигуру, внутри буква,
/// эмодзи или фото (обрезанное по той же форме). Невыбранная приглушается.
///
/// Смена [shapeIndex] перетекает, а не подменяет силуэт кадром: так выбор формы
/// в редакторе показывает сам себя. [toSession] тянет обложку в круг занятия —
/// им пользуется плитка колоды при запуске сессии.
class ShapedCover extends StatefulWidget {
  final String label;
  final Color color;
  final String? imagePath;
  final double size;
  final int shapeIndex;
  final bool muted;

  /// 0 — своя форма, 1 — круг занятия.
  final double toSession;

  const ShapedCover({
    super.key,
    required this.label,
    required this.color,
    required this.imagePath,
    required this.size,
    required this.shapeIndex,
    this.muted = false,
    this.toSession = 0,
  });

  @override
  State<ShapedCover> createState() => _ShapedCoverState();
}

class _ShapedCoverState extends State<ShapedCover>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
    value: 1,
  );

  late ms.RoundedPolygon _from = deckShape(widget.shapeIndex);
  late ms.RoundedPolygon _to = deckShape(widget.shapeIndex);

  @override
  void didUpdateWidget(covariant ShapedCover old) {
    super.didUpdateWidget(old);
    if (old.shapeIndex == widget.shapeIndex) return;
    // Начинаем не от прежней формы, а от той, что нарисована сейчас: при
    // быстром переборе форм иначе виден скачок назад.
    _from = _c.isAnimating ? _to : _from;
    _to = deckShape(widget.shapeIndex);
    _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final path = widget.imagePath;

    // Запасной вариант — буква/эмодзи в фигуре. Он же подменяет фото, если файл
    // пропал: проверять существование файла в build() нельзя (синхронный
    // сисколл на каждую перерисовку), поэтому ловим ошибку через errorBuilder.
    final Widget letter = Text(
      widget.label.isNotEmpty
          ? widget.label.characters.first.toUpperCase()
          : '?',
      style: TextStyle(
        color: Colors.white,
        fontFamily: AppTheme.displayFont,
        fontWeight: FontWeight.w800,
        fontSize: size * 0.38,
      ),
    );

    Widget content = letter;
    if (path != null && path.isNotEmpty) {
      // Декодируем под реальный размер обложки, а не в полный размер снимка.
      final px = (size * MediaQuery.devicePixelRatioOf(context)).round();
      content = Image.file(
        File(path),
        width: size,
        height: size,
        fit: BoxFit.cover,
        cacheWidth: px,
        cacheHeight: px,
        errorBuilder: (_, _, _) => Center(child: letter),
      );
    }

    return Opacity(
      opacity: widget.muted ? 0.45 : 1.0,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, child) {
          // Два морфа подряд: между формами обложки и в круг занятия.
          // Промежуточную форму пакет строить не умеет, поэтому при запуске
          // сессии ведём от текущей цели.
          final session = widget.toSession.clamp(0.0, 1.0);
          final morph = session > 0
              ? morphBetween(_to, FernShapes.session)
              : morphBetween(_from, _to);
          final t = session > 0
              ? session
              : AppTheme.emphasized.transform(_c.value);
          return SizedBox(
            width: size,
            height: size,
            child: CustomPaint(
              painter: MorphPainter(
                morph: morph,
                t: t,
                fill: widget.color,
                border: null,
                borderWidth: 0,
              ),
              child: ClipPath(
                clipper: MorphClipper(morph, t),
                child: Center(child: child),
              ),
            ),
          );
        },
        child: content,
      ),
    );
  }
}
