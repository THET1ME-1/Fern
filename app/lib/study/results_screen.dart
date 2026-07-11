import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/strings.dart';
import '../services/deck_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/confetti_overlay.dart';
import '../widgets/reveal.dart';

/// Итог сессии обучения.
class SessionResult {
  final int answered;
  final int correct;
  final Duration elapsed;
  final int? score; // очки режима «Быстрый повtор» (иначе null)
  const SessionResult(this.answered, this.correct, this.elapsed, {this.score});

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
