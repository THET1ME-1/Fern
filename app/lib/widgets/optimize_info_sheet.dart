import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../models/fsrs.dart';
import '../models/word_card.dart';
import '../services/fsrs_optimizer.dart';
import '../theme/app_theme.dart';

/// «Что даёт оптимизация» — объяснение кнопки человеческим языком.
///
/// Кнопка меняет одно число: через сколько дней вернётся слово, встреченное
/// сегодня. Названия весов и лог-лосс тут не помогут, поэтому лист показывает
/// сами сроки — сначала общие, а рядом личные, когда они уже посчитаны.
class OptimizeInfoSheet extends StatelessWidget {
  /// Готовность журнала — чтобы человек видел, сколько ещё заниматься.
  final FsrsReadiness data;

  /// Личные веса, если подгонка уже применена.
  final List<double>? personal;

  /// Целевое удержание: от него зависят и общие сроки, и личные.
  final double retention;

  const OptimizeInfoSheet({
    super.key,
    required this.data,
    required this.personal,
    required this.retention,
  });

  static Future<void> show(
    BuildContext context, {
    required FsrsReadiness data,
    required List<double>? personal,
    required double retention,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => OptimizeInfoSheet(
        data: data,
        personal: personal,
        retention: retention,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final media = MediaQuery.of(context);

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: media.size.height * 0.86),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                tr('opt_info_title'),
                style: TextStyle(
                  fontFamily: AppTheme.displayFont,
                  fontWeight: FontWeight.w700,
                  fontSize: 20,
                  color: scheme.onSurface,
                ),
              ),
              const SizedBox(height: 12),
              _paragraph(scheme, tr('opt_info_lead')),
              const SizedBox(height: 8),
              _paragraph(scheme, tr('opt_info_lead2')),
              const SizedBox(height: 18),
              _intervalsCard(scheme),
              const SizedBox(height: 14),
              _effectCard(scheme),
              const SizedBox(height: 14),
              _note(scheme),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonal(
                  onPressed: () => Navigator.pop(context),
                  child: Text(tr('close')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _paragraph(ColorScheme scheme, String text) => Text(
        text,
        style: TextStyle(
          fontFamily: AppTheme.bodyFont,
          fontSize: 14,
          height: 1.45,
          color: scheme.onSurfaceVariant,
        ),
      );

  /// Главное содержимое: сроки первого повтора по каждой оценке. Пока подгонки
  /// нет — один столбец, после неё — общий и личный рядом, чтобы разница
  /// читалась без объяснений.
  Widget _intervalsCard(ColorScheme scheme) {
    final byDefault = Fsrs.forSimulation(weights: null, retention: retention);
    final mine = personal == null
        ? null
        : Fsrs.forSimulation(weights: personal, retention: retention);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr('opt_info_hold'),
            style: TextStyle(
              fontFamily: AppTheme.displayFont,
              fontWeight: FontWeight.w700,
              fontSize: 15,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          // Без этой строки «Не помню — 1 день» читается неправдой: сначала
          // слово вернётся через минуту и через десять, и только потом уйдёт на
          // срок в днях.
          Text(
            tr('opt_info_hold_sub'),
            style: TextStyle(
              fontFamily: AppTheme.bodyFont,
              fontSize: 12,
              height: 1.35,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          if (mine != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  const Spacer(),
                  _columnLabel(scheme, tr('opt_info_col_avg')),
                  const SizedBox(width: 14),
                  _columnLabel(scheme, tr('opt_info_col_you'), accent: true),
                ],
              ),
            ),
          for (final r in Rating.values)
            _intervalRow(scheme, r, byDefault.firstIntervalDays(r),
                mine?.firstIntervalDays(r)),
        ],
      ),
    );
  }

  Widget _columnLabel(ColorScheme scheme, String text, {bool accent = false}) =>
      SizedBox(
        width: 74,
        child: Text(
          text,
          textAlign: TextAlign.end,
          style: TextStyle(
            fontFamily: AppTheme.bodyFont,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
            color: accent ? scheme.primary : scheme.onSurfaceVariant,
          ),
        ),
      );

  Widget _intervalRow(
      ColorScheme scheme, Rating rating, int common, int? personalDays) {
    final label = switch (rating) {
      Rating.again => tr('rate_again'),
      Rating.hard => tr('rate_hard'),
      Rating.good => tr('rate_good'),
      Rating.easy => tr('rate_easy'),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontFamily: AppTheme.bodyFont,
                fontSize: 14,
                color: scheme.onSurface,
              ),
            ),
          ),
          SizedBox(
            width: 74,
            child: Text(
              trn('n_days', common),
              textAlign: TextAlign.end,
              style: TextStyle(
                fontFamily: AppTheme.displayFont,
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: personalDays == null
                    ? scheme.onSurface
                    : scheme.onSurfaceVariant,
              ),
            ),
          ),
          if (personalDays != null) ...[
            const SizedBox(width: 14),
            SizedBox(
              width: 74,
              child: Text(
                trn('n_days', personalDays),
                textAlign: TextAlign.end,
                style: TextStyle(
                  fontFamily: AppTheme.displayFont,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: scheme.primary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Что человек заметит на своих занятиях — обе стороны сразу, потому что
  /// подгонка может и приблизить повтор.
  Widget _effectCard(ColorScheme scheme) => Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr('opt_info_effect'),
              style: TextStyle(
                fontFamily: AppTheme.displayFont,
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: 10),
            _effectRow(scheme, Icons.trending_down_rounded,
                tr('opt_info_effect_slow')),
            const SizedBox(height: 8),
            _effectRow(
                scheme, Icons.trending_up_rounded, tr('opt_info_effect_fast')),
          ],
        ),
      );

  Widget _effectRow(ColorScheme scheme, IconData icon, String text) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: scheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontFamily: AppTheme.bodyFont,
                fontSize: 13.5,
                height: 1.4,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      );

  /// Оговорка и состояние сбора: без первой цифру прочитают как обещание, без
  /// второго человек не поймёт, чего ждать дальше.
  Widget _note(ColorScheme scheme) {
    final status = personal != null
        ? tr('optimize_active')
        : data.total < data.needTotal
            ? trf('optimize_progress',
                {'n': data.total, 'need': data.needTotal})
            : data.pairs < data.needPairs
                ? trf('optimize_pairs',
                    {'n': data.pairs, 'need': data.needPairs})
                : tr('optimize_ready');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded,
              size: 18, color: scheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr('opt_info_note'),
                  style: TextStyle(
                    fontFamily: AppTheme.bodyFont,
                    fontSize: 12.5,
                    height: 1.45,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  status,
                  style: TextStyle(
                    fontFamily: AppTheme.bodyFont,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
