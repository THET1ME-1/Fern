import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../models/fsrs.dart';
import '../services/deck_repository.dart';
import '../services/schedule_lab.dart';
import '../widgets/empty_state.dart';
import '../widgets/reveal.dart';
import '../theme/app_theme.dart';

/// «Как Fern решает» — что планировщик обещал и что вышло на самом деле.
///
/// Экран намеренно скупой на обещания. Единственное, что можно проверить по
/// собственной истории, — насколько точны были предсказания вероятности
/// вспомнить. «Вы запомните на 15% больше» отсюда не следует и здесь не пишется.
class ScheduleExplainScreen extends StatefulWidget {
  const ScheduleExplainScreen({super.key});

  @override
  State<ScheduleExplainScreen> createState() => _ScheduleExplainScreenState();
}

class _ScheduleExplainScreenState extends State<ScheduleExplainScreen> {
  bool _loading = true;
  ScheduleQuality _default = ScheduleQuality.empty;
  ScheduleQuality _personal = ScheduleQuality.empty;
  bool _hasCustomWeights = false;

  @override
  void initState() {
    super.initState();
    _measure();
  }

  Future<void> _measure() async {
    final repo = DeckRepository.instance;
    final events = await repo.reviewEvents();
    final weights = await repo.fsrsWeights();
    final retention = Fsrs.instance.requestRetention;

    final byDefault =
        ScheduleLab.evaluate(events, weights: null, retention: retention);
    final byPersonal = weights == null
        ? ScheduleQuality.empty
        : ScheduleLab.evaluate(events, weights: weights, retention: retention);

    if (!mounted) return;
    setState(() {
      _default = byDefault;
      _personal = byPersonal;
      _hasCustomWeights = weights != null;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(tr('how_fern_decides'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _default.hasData
              ? ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                  children: _content(scheme),
                )
              : _notEnough(scheme),
    );
  }

  // ----------------------------- Мало данных -----------------------------

  Widget _notEnough(ColorScheme scheme) => EmptyState(
        icon: Icons.hourglass_empty_rounded,
        title: tr('explain_no_data'),
        subtitle: trf('explain_no_data_sub', {'n': ScheduleLab.minSamples}),
      );

  // ----------------------------- Есть что показать -----------------------------

  List<Widget> _content(ColorScheme scheme) {
    final actual = (_default.actual * 100).round();
    final promised = (_default.predicted * 100).round();

    return [
      Reveal(child: _retentionCard(scheme, actual, promised)),
      const SizedBox(height: 12),
      Reveal(
        delay: const Duration(milliseconds: 80),
        child: _accuracyCard(scheme),
      ),
      const SizedBox(height: 12),
      Reveal(
        delay: const Duration(milliseconds: 160),
        child: _disclaimer(scheme),
      ),
    ];
  }

  /// Крупная цифра: сколько повторов на самом деле кончились «вспомнил».
  Widget _retentionCard(ColorScheme scheme, int actual, int promised) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 26, 24, 26),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr('retention_measured'),
            style: TextStyle(
              fontFamily: AppTheme.bodyFont,
              fontWeight: FontWeight.w700,
              fontSize: 11.5,
              letterSpacing: 0.9,
              color: scheme.onPrimaryContainer.withValues(alpha: 0.75),
            ),
          ),
          const SizedBox(height: 6),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: actual.toDouble()),
            duration: const Duration(milliseconds: 800),
            curve: AppTheme.emphasizedDecelerate,
            builder: (_, v, _) => Text(
              '${v.round()}%',
              style: TextStyle(
                fontFamily: AppTheme.displayFont,
                fontWeight: FontWeight.w800,
                fontSize: 52,
                height: 1.05,
                color: scheme.onPrimaryContainer,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            trf('retention_vs_promise', {
              'promised': promised,
              'n': _default.samples,
            }),
            style: TextStyle(
              fontFamily: AppTheme.bodyFont,
              fontSize: 13.5,
              height: 1.4,
              color: scheme.onPrimaryContainer.withValues(alpha: 0.9),
            ),
          ),
        ],
      ),
    );
  }

  /// Сравнение: обычные веса против личных.
  Widget _accuracyCard(ColorScheme scheme) {
    final gain = _hasCustomWeights
        ? ScheduleLab.improvementPercent(_default, _personal)
        : 0.0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr('prediction_accuracy'),
            style: TextStyle(
              fontFamily: AppTheme.displayFont,
              fontWeight: FontWeight.w700,
              fontSize: 16,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            tr('log_loss_sub'),
            style: TextStyle(
              fontFamily: AppTheme.bodyFont,
              fontSize: 12.5,
              height: 1.35,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          _lossRow(scheme, tr('weights_default'), _default.logLoss,
              best: !_hasCustomWeights || gain <= 0),
          if (_hasCustomWeights) ...[
            const SizedBox(height: 10),
            _lossRow(scheme, tr('weights_personal'), _personal.logLoss,
                best: gain > 0),
          ],
          const SizedBox(height: 14),
          Text(
            _hasCustomWeights
                ? trf('weights_gain', {'g': gain.toStringAsFixed(1)})
                : tr('weights_default_only'),
            style: TextStyle(
              fontFamily: AppTheme.bodyFont,
              fontSize: 13,
              height: 1.4,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  /// Строка сравнения. Шкала обратная: меньше лог-лосс — точнее предсказание.
  Widget _lossRow(
    ColorScheme scheme,
    String label,
    double loss, {
    required bool best,
  }) {
    return Row(
      children: [
        Icon(
          best ? Icons.check_circle_rounded : Icons.circle_outlined,
          size: 18,
          color: best ? scheme.primary : scheme.outlineVariant,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontFamily: AppTheme.bodyFont,
              fontSize: 14,
              fontWeight: best ? FontWeight.w700 : FontWeight.w400,
              color: scheme.onSurface,
            ),
          ),
        ),
        Text(
          loss.toStringAsFixed(3),
          style: TextStyle(
            fontFamily: AppTheme.displayFont,
            fontWeight: FontWeight.w700,
            fontSize: 15,
            color: best ? scheme.primary : scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  /// Оговорка. Без неё цифру прочитают как обещание помнить больше.
  Widget _disclaimer(ColorScheme scheme) => Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(28),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline_rounded,
                size: 18, color: scheme.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                tr('explain_disclaimer'),
                style: TextStyle(
                  fontFamily: AppTheme.bodyFont,
                  fontSize: 12.5,
                  height: 1.45,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      );
}
