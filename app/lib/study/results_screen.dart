import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/strings.dart';
import '../services/deck_repository.dart';
import 'study_models.dart';
import '../theme/app_theme.dart';
import '../widgets/confetti_overlay.dart';
import '../widgets/reveal.dart';

/// Что планировщик решил сам, пока собирал эту сессию.
///
/// Пять правок подачи (книга, соседи, интерференция) работают молча, и человеку
/// они видны только как «почему-то другие слова». Сводка их проговаривает.
class SessionPlan {
  /// Сколько карт пришло по каждой причине отбора.
  final Map<SelectionReason, int> byReason;

  /// Сколько путаемых пар развели по очереди.
  final int separatedPairs;

  const SessionPlan({this.byReason = const {}, this.separatedPairs = 0});

  int of(SelectionReason r) => byReason[r] ?? 0;

  /// Есть ли о чём рассказывать. Обычная сессия «по срокам» объяснений не
  /// требует — сводка появляется, когда планировщик правда вмешался.
  bool get hasNews =>
      of(SelectionReason.book) > 0 ||
      of(SelectionReason.neighbourLapse) > 0 ||
      separatedPairs > 0;
}

/// Итог сессии обучения.
class SessionResult {
  final int answered;
  final int correct;
  final Duration elapsed;
  final int? score; // очки режима «Быстрый повtор» (иначе null)

  /// Решения планировщика по этой сессии (для блока «Что сделал алгоритм»).
  final SessionPlan plan;

  const SessionResult(
    this.answered,
    this.correct,
    this.elapsed, {
    this.score,
    this.plan = const SessionPlan(),
  });

  int get accuracy => answered == 0 ? 0 : ((correct / answered) * 100).round();
}

/// Экран результатов после завершённой сессии.
class ResultsScreen extends StatefulWidget {
  final SessionResult result;

  /// Колбэк «Ещё сессия». Получает ЖИВОЙ контекст экрана результатов, чтобы
  /// навигация шла от него, а не от уже уничтоженного [SessionScreen].
  final void Function(BuildContext context)? onStudyMore;

  const ResultsScreen({super.key, required this.result, this.onStudyMore});

  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen> {
  bool _goalReached = false; // дневная цель выполнена этой сессией
  bool _confettiDone = false;

  @override
  void initState() {
    super.initState();
    _checkGoal();
  }

  Future<void> _checkGoal() async {
    final reached = await DeckRepository.instance.consumeDailyGoalCelebration();
    if (reached && mounted) {
      HapticFeedback.heavyImpact();
      setState(() => _goalReached = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final result = widget.result;
    final acc = result.accuracy;
    final mins = result.elapsed.inMinutes;
    final secs = result.elapsed.inSeconds % 60;
    final timeStr = mins > 0
        ? trf('dur_min_sec', {'m': mins, 's': secs})
        : trf('dur_sec', {'s': secs});

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
              child: Column(
                children: [
                  const Spacer(),
                  Reveal(
                    child: Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        color: _goalReached
                            ? scheme.tertiaryContainer
                            : scheme.primaryContainer,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _goalReached
                            ? Icons.emoji_events_rounded
                            : Icons.check_rounded,
                        size: 68,
                        color: _goalReached
                            ? scheme.onTertiaryContainer
                            : scheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Reveal(
                    delay: const Duration(milliseconds: 80),
                    child: Text(
                      _goalReached ? tr('goal_done') : tr('session_done'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: AppTheme.displayFont,
                        fontWeight: FontWeight.w800,
                        fontSize: 26,
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
              if (result.score != null) ...[
                const SizedBox(height: 20),
                Reveal(
                  delay: const Duration(milliseconds: 120),
                  child: Column(
                    children: [
                      Text(
                        '${widget.result.score}',
                        style: TextStyle(
                          fontFamily: AppTheme.displayFont,
                          fontWeight: FontWeight.w800,
                          fontSize: 44,
                          color: scheme.primary,
                        ),
                      ),
                      Text(
                        tr('res_score'),
                        style: TextStyle(
                          fontFamily: AppTheme.bodyFont,
                          fontSize: 13,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 28),
              Reveal(
                delay: const Duration(milliseconds: 160),
                child: Row(
                  children: [
                    _stat(scheme, '${result.answered}', tr('res_reviewed')),
                    const SizedBox(width: 12),
                    _stat(scheme, '$acc%', tr('res_accuracy'), highlight: true),
                    const SizedBox(width: 12),
                    _stat(scheme, timeStr, tr('res_time')),
                  ],
                ),
              ),
              if (result.plan.hasNews) ...[
                const SizedBox(height: 20),
                Reveal(
                  delay: const Duration(milliseconds: 220),
                  child: _planCard(scheme, result.plan),
                ),
              ],
              const Spacer(),
              if (widget.onStudyMore != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.tonal(
                      onPressed: () => widget.onStudyMore!(context),
                      child: Text(tr('study_more')),
                    ),
                  ),
                ),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(tr('back_to_deck')),
                ),
              ),
                ],
              ),
            ),
            if (_goalReached && !_confettiDone)
              Positioned.fill(
                child: ConfettiOverlay(
                  onDone: () {
                    if (mounted) setState(() => _confettiDone = true);
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// «Что сделал алгоритм» — человеческим языком, по одной строке на решение.
  Widget _planCard(ColorScheme scheme, SessionPlan plan) {
    final lines = <(IconData, String)>[
      if (plan.of(SelectionReason.book) > 0)
        (
          Icons.menu_book_rounded,
          trf('plan_from_book',
              {'w': trn('n_words', plan.of(SelectionReason.book))})
        ),
      if (plan.of(SelectionReason.neighbourLapse) > 0)
        (
          Icons.hub_rounded,
          trf('plan_neighbours',
              {'w': trn('n_words', plan.of(SelectionReason.neighbourLapse))})
        ),
      if (plan.separatedPairs > 0)
        (
          Icons.call_split_rounded,
          trf('plan_separated', {'p': trn('n_pairs', plan.separatedPairs)})
        ),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr('plan_title'),
            style: TextStyle(
              fontFamily: AppTheme.displayFont,
              fontWeight: FontWeight.w700,
              fontSize: 15,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: 10),
          for (final (icon, text) in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, size: 16, color: scheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      text,
                      style: TextStyle(
                        fontFamily: AppTheme.bodyFont,
                        fontSize: 13.5,
                        height: 1.3,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _stat(
    ColorScheme scheme,
    String value,
    String label, {
    bool highlight = false,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 8),
        decoration: BoxDecoration(
          color: highlight
              ? scheme.primaryContainer
              : scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          children: [
            FittedBox(
              child: Text(
                value,
                style: TextStyle(
                  fontFamily: AppTheme.displayFont,
                  fontWeight: FontWeight.w800,
                  fontSize: 24,
                  color: highlight
                      ? scheme.onPrimaryContainer
                      : scheme.onSurface,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: AppTheme.bodyFont,
                fontSize: 12,
                color:
                    (highlight
                            ? scheme.onPrimaryContainer
                            : scheme.onSurfaceVariant)
                        .withValues(alpha: 0.85),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
