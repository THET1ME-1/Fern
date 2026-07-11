import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../services/grammar.dart';
import '../theme/app_theme.dart';

/// M3-карточка грамматических форм слова (спряжение/множественное число).
/// Показывается в редакторе карточки и в окне перевода, если для слова есть
/// таблица. Формы — из офлайн-правил [Grammar]; при приблизительности показываем
/// честную сноску.
class GrammarCard extends StatelessWidget {
  final List<GrammarTable> tables;

  const GrammarCard({super.key, required this.tables});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final approx = tables.any((t) => t.approximate);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.table_chart_rounded, size: 20, color: scheme.primary),
              const SizedBox(width: 8),
              Text(
                tr('grammar_title'),
                style: TextStyle(
                  fontFamily: AppTheme.displayFont,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  color: scheme.onSurface,
                ),
              ),
            ],
          ),
          for (var i = 0; i < tables.length; i++) ...[
            const SizedBox(height: 14),
            _table(scheme, tables[i]),
          ],
          if (approx) ...[
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded,
                    size: 14, color: scheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    tr('grammar_approx'),
                    style: TextStyle(
                      fontFamily: AppTheme.bodyFont,
                      fontSize: 11.5,
                      height: 1.3,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _table(ColorScheme scheme, GrammarTable t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          t.title,
          style: TextStyle(
            fontFamily: AppTheme.bodyFont,
            fontWeight: FontWeight.w700,
            fontSize: 13,
            color: scheme.primary,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: scheme.surface.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            children: [
              for (var i = 0; i < t.rows.length; i++)
                _row(scheme, t.rows[i], last: i == t.rows.length - 1),
            ],
          ),
        ),
      ],
    );
  }

  Widget _row(ColorScheme scheme, GrammarRow r, {required bool last}) {
    return Container(
      decoration: BoxDecoration(
        border: last
            ? null
            : Border(
                bottom: BorderSide(
                  color: scheme.outlineVariant.withValues(alpha: 0.4),
                ),
              ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      child: Row(
        children: [
          SizedBox(
            width: 96,
            child: Text(
              r.label,
              style: TextStyle(
                fontFamily: AppTheme.bodyFont,
                fontSize: 13.5,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              r.form,
              style: TextStyle(
                fontFamily: AppTheme.bodyFont,
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
