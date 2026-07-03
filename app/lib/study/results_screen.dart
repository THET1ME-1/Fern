import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../theme/app_theme.dart';
import '../widgets/reveal.dart';

/// Итог сессии обучения.
class SessionResult {
  final int answered;
  final int correct;
  final Duration elapsed;
  const SessionResult(this.answered, this.correct, this.elapsed);

  int get accuracy =>
      answered == 0 ? 0 : ((correct / answered) * 100).round();
}

/// Экран результатов после завершённой сессии.
class ResultsScreen extends StatelessWidget {
  final SessionResult result;

  /// Колбэк «Ещё сессия». Получает ЖИВОЙ контекст экрана результатов, чтобы
  /// навигация шла от него, а не от уже уничтоженного [SessionScreen].
  final void Function(BuildContext context)? onStudyMore;

  const ResultsScreen({super.key, required this.result, this.onStudyMore});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final acc = result.accuracy;
    final mins = result.elapsed.inMinutes;
    final secs = result.elapsed.inSeconds % 60;
    final timeStr = mins > 0 ? '$mins мин $secs с' : '$secs с';

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
          child: Column(
            children: [
              const Spacer(),
              Reveal(
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.check_rounded,
                      size: 68, color: scheme.onPrimaryContainer),
                ),
              ),
              const SizedBox(height: 24),
              Reveal(
                delay: const Duration(milliseconds: 80),
                child: Text(
                  tr('session_done'),
                  style: TextStyle(
                    fontFamily: AppTheme.displayFont,
                    fontWeight: FontWeight.w800,
                    fontSize: 26,
                    color: scheme.onSurface,
                  ),
                ),
              ),
              const SizedBox(height: 28),
              Reveal(
                delay: const Duration(milliseconds: 160),
                child: Row(
                  children: [
                    _stat(scheme, '${result.answered}', tr('res_reviewed')),
                    const SizedBox(width: 12),
                    _stat(scheme, '$acc%', tr('res_accuracy'),
                        highlight: true),
                    const SizedBox(width: 12),
                    _stat(scheme, timeStr, tr('res_time')),
                  ],
                ),
              ),
              const Spacer(),
              if (onStudyMore != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.tonal(
                      onPressed: () => onStudyMore!(context),
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
      ),
    );
  }

  Widget _stat(ColorScheme scheme, String value, String label,
      {bool highlight = false}) {
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
                color: (highlight
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
