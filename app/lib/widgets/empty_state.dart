import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/fern_shapes.dart';
import 'morph_shapes.dart';
import 'reveal.dart';

/// Крупная выразительная «заглушка» для пустых/будущих разделов в духе
/// Material 3 Expressive: большая скруглённая плашка с иконкой, заголовок и
/// подпись. Появляется с каскадной анимацией.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? action;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Reveal(
              // Плашка под иконкой — не скруглённый квадрат, а силуэт из того
              // же набора форм, что обложки колод и кольцо цели.
              child: MorphShape(
                from: FernShapes.empty,
                to: FernShapes.empty,
                progress: 0,
                size: 140,
                fill: scheme.primaryContainer,
                child: Icon(icon, size: 62, color: scheme.onPrimaryContainer),
              ),
            ),
            const SizedBox(height: 28),
            Reveal(
              delay: const Duration(milliseconds: 80),
              child: Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: AppTheme.displayFont,
                  fontWeight: FontWeight.w800,
                  fontSize: 26,
                  letterSpacing: -0.5,
                  color: scheme.onSurface,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Reveal(
              delay: const Duration(milliseconds: 140),
              child: Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: AppTheme.bodyFont,
                  fontSize: 15,
                  height: 1.4,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            if (action != null) ...[
              const SizedBox(height: 24),
              Reveal(delay: const Duration(milliseconds: 200), child: action!),
            ],
          ],
        ),
      ),
    );
  }
}
