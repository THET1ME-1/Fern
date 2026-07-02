import 'package:flutter/material.dart';

import 'l10n/strings.dart';
import 'models/word_card.dart';
import 'services/deck_repository.dart';
import 'theme/app_theme.dart';
import 'widgets/reveal.dart';

/// Экран «Прогресс»: обзор по всем карточкам, нагрузка на неделю, трудные слова.
class ProgressScreen extends StatefulWidget {
  const ProgressScreen({super.key});

  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> {
  final DeckRepository _repo = DeckRepository.instance;
  List<WordCard> _cards = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _repo.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    _repo.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final cards = await _repo.loadCards();
    if (!mounted) return;
    setState(() {
      _cards = cards;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();

    var fresh = 0, learning = 0, mature = 0, due = 0;
    for (final c in _cards) {
      if (c.review.isNew) {
        fresh++;
        due++;
      } else {
        if (c.isDue(now)) due++;
        if (c.review.stability >= 21) {
          mature++;
        } else {
          learning++;
        }
      }
    }

    return Scaffold(
      appBar: AppBar(title: Text(tr('progress_title'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _cards.isEmpty
              ? _empty(scheme)
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  children: [
                    Reveal(child: _dueHero(due, scheme)),
                    const SizedBox(height: 16),
                    Reveal(
                      delay: const Duration(milliseconds: 60),
                      child: Row(
                        children: [
                          _stat('${_cards.length}', tr('cards_total'), scheme),
                          const SizedBox(width: 10),
                          _stat('$fresh', tr('stat_new'), scheme),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Reveal(
                      delay: const Duration(milliseconds: 120),
                      child: Row(
                        children: [
                          _stat('$learning', tr('stat_learning'), scheme),
                          const SizedBox(width: 10),
                          _stat('$mature', tr('stat_mature'), scheme),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    _sectionTitle(tr('forecast'), scheme),
                    const SizedBox(height: 12),
                    Reveal(
                      delay: const Duration(milliseconds: 160),
                      child: _forecast(now, scheme),
                    ),
                    const SizedBox(height: 24),
                    ..._hardest(scheme),
                  ],
                ),
    );
  }

  Widget _dueHero(int due, ColorScheme scheme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 24),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        children: [
          Text(
            '$due',
            style: TextStyle(
              fontFamily: AppTheme.displayFont,
              fontWeight: FontWeight.w800,
              fontSize: 56,
              color: scheme.onPrimaryContainer,
            ),
          ),
          Text(
            tr('stat_due'),
            style: TextStyle(
              fontFamily: AppTheme.bodyFont,
              fontSize: 15,
              color: scheme.onPrimaryContainer.withValues(alpha: 0.85),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stat(String value, String label, ColorScheme scheme) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontFamily: AppTheme.displayFont,
                fontWeight: FontWeight.w800,
                fontSize: 26,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontFamily: AppTheme.bodyFont,
                fontSize: 12,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Столбики: сколько карт придёт на повтор в ближайшие 7 дней.
  Widget _forecast(DateTime now, ColorScheme scheme) {
    final today = DateTime(now.year, now.month, now.day);
    final counts = List<int>.filled(7, 0);
    for (final c in _cards) {
      if (c.review.isNew) {
        counts[0]++;
        continue;
      }
      final due = c.review.due;
      if (due == null) continue;
      final dueDay = DateTime(due.year, due.month, due.day);
      final diff = dueDay.difference(today).inDays;
      if (diff <= 0) {
        counts[0]++;
      } else if (diff < 7) {
        counts[diff]++;
      }
    }
    final maxV = counts.fold<int>(1, (m, v) => v > m ? v : m);
    const labels = ['Сег', '+1', '+2', '+3', '+4', '+5', '+6'];

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(24),
      ),
      child: SizedBox(
        height: 130,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var i = 0; i < 7; i++)
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      '${counts[i]}',
                      style: TextStyle(
                        fontFamily: AppTheme.bodyFont,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: counts[i] / maxV),
                      duration: const Duration(milliseconds: 500),
                      curve: Curves.easeOutCubic,
                      builder: (_, t, _) => Container(
                        height: 80 * t + 4,
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(
                          color: i == 0 ? scheme.primary : scheme.primary
                              .withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      labels[i],
                      style: TextStyle(
                        fontFamily: AppTheme.bodyFont,
                        fontSize: 10,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> _hardest(ColorScheme scheme) {
    final hard = _cards
        .where((c) => c.review.lapses > 0 || c.review.difficulty >= 7)
        .toList()
      ..sort((a, b) {
        final byL = b.review.lapses.compareTo(a.review.lapses);
        if (byL != 0) return byL;
        return b.review.difficulty.compareTo(a.review.difficulty);
      });
    if (hard.isEmpty) return [];
    final top = hard.take(5).toList();
    return [
      _sectionTitle(tr('hardest_words'), scheme),
      const SizedBox(height: 12),
      for (final c in top)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              children: [
                Icon(Icons.local_fire_department_rounded,
                    color: scheme.error, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '${c.front} — ${c.back}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: AppTheme.bodyFont,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface,
                    ),
                  ),
                ),
                if (c.review.lapses > 0)
                  Text(
                    '×${c.review.lapses}',
                    style: TextStyle(
                      fontFamily: AppTheme.displayFont,
                      fontWeight: FontWeight.w700,
                      color: scheme.error,
                    ),
                  ),
              ],
            ),
          ),
        ),
    ];
  }

  Widget _sectionTitle(String text, ColorScheme scheme) => Align(
        alignment: Alignment.centerLeft,
        child: Text(
          text,
          style: TextStyle(
            fontFamily: AppTheme.displayFont,
            fontWeight: FontWeight.w700,
            fontSize: 18,
            color: scheme.onSurface,
          ),
        ),
      );

  Widget _empty(ColorScheme scheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.insights_rounded, size: 72, color: scheme.primary),
            const SizedBox(height: 20),
            Text(
              tr('no_data'),
              style: TextStyle(
                fontFamily: AppTheme.displayFont,
                fontWeight: FontWeight.w700,
                fontSize: 20,
                color: scheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
