import 'dart:io';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Набор выразительных форм M3 — обложки колод: круг, звезда, шестиугольник,
/// пятиконечная звезда, ромб, цветок-«печенька».
///
/// (ДНК ScoreMaster — там это были формы-аватары игроков.)
const List<ShapeBorder> kDeckShapes = [
  CircleBorder(),
  StarBorder(
    points: 6,
    innerRadiusRatio: 0.78,
    pointRounding: 0.55,
    valleyRounding: 0.35,
  ),
  StarBorder.polygon(sides: 6, rotation: 90, pointRounding: 0.28),
  StarBorder(
    points: 5,
    innerRadiusRatio: 0.62,
    pointRounding: 0.34,
    valleyRounding: 0.1,
  ),
  StarBorder.polygon(sides: 4, rotation: 45, pointRounding: 0.32),
  StarBorder(
    points: 8,
    innerRadiusRatio: 0.84,
    pointRounding: 0.5,
    valleyRounding: 0.5,
  ),
];

/// Форма по индексу (циклически).
ShapeBorder deckShape(int index) =>
    kDeckShapes[index.abs() % kDeckShapes.length];

/// Обложка колоды в произвольной форме: цвет заливает фигуру, внутри буква,
/// эмодзи или фото (обрезанное по той же форме). Невыбранная приглушается.
class ShapedCover extends StatelessWidget {
  final String label;
  final Color color;
  final String? imagePath;
  final double size;
  final ShapeBorder shape;
  final bool muted;

  const ShapedCover({
    super.key,
    required this.label,
    required this.color,
    required this.imagePath,
    required this.size,
    required this.shape,
    this.muted = false,
  });

  @override
  Widget build(BuildContext context) {
    final hasPhoto = imagePath != null && File(imagePath!).existsSync();

    final Widget content = hasPhoto
        ? SizedBox(
            width: size,
            height: size,
            child: ClipPath(
              clipper: ShapeBorderClipper(shape: shape),
              child: Image.file(
                File(imagePath!),
                width: size,
                height: size,
                fit: BoxFit.cover,
              ),
            ),
          )
        : Container(
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: ShapeDecoration(color: color, shape: shape),
            child: Text(
              label.isNotEmpty ? label.characters.first.toUpperCase() : '?',
              style: TextStyle(
                color: Colors.white,
                fontFamily: AppTheme.displayFont,
                fontWeight: FontWeight.w800,
                fontSize: size * 0.38,
              ),
            ),
          );

    return Opacity(opacity: muted ? 0.45 : 1.0, child: content);
  }
}
