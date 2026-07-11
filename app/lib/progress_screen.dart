import 'package:flutter/material.dart';

import 'achievements_screen.dart';
import 'l10n/strings.dart';
import 'models/deck.dart';
import 'models/review_log.dart';
import 'models/word_card.dart';
import 'services/deck_repository.dart';
import 'services/language_registry.dart';
import 'services/pos.dart';
import 'services/source_library.dart';
import 'theme/app_theme.dart';
import 'widgets/reveal.dart';
import 'widgets/weekly_recap.dart';

/// Экран «Прогресс»: обзор по всем карточкам, нагрузка на неделю, трудные слова.
class ProgressScreen extends StatefulWidget {
  const ProgressScreen({super.key});

  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> {
  final DeckRepository _repo = DeckRepository.instance;
  final SourceLibrary _library = SourceLibrary.instance;
  List<WordCard> _cards = [];
  List<Deck> _decks = [];
  List<LibrarySource> _books = [];
  ReviewLog _log = ReviewLog.empty();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _repo.addListener(_load);
    _library.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    _repo.removeListener(_load);
    _library.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final cards = await _repo.loadCards();
    final decks = await _repo.loadDecks();
    final log = await _repo.reviewLog();
    final sources = await _library.list();
    if (!mounted) return;
    setState(() {
      _cards = cards;
      _decks = decks;
      _books = sources.where((s) => s.isBook).toList();
      _log = log;
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

    final streak = _log.streak(now);
    var r7 = 0, c7 = 0, activeDays7 = 0;
    for (var i = 0; i < 7; i++) {
      final s = _log.statOn(now.subtract(Duration(days: i)));
      r7 += s.reviews;
      c7 += s.correct;
      if (s.reviews > 0) activeDays7++;
    }
    final acc7 = r7 == 0 ? 0 : ((c7 / r7) * 100).round();

    return Scaffold(
      appBar: AppBar(
        title: Text(tr('progress_title')),
        actions: [
          IconButton(
            tooltip: tr('achievements'),
            icon: const Icon(Icons.emoji_events_rounded),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AchievementsScreen()),
            ),
          ),
        ],
      ),
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
                const SizedBox(height: 10),
                Reveal(
                  delay: const Duration(milliseconds: 150),
                  child: Row(
                    children: [
                      _stat(
                        '$streak',
                        tr('stat_streak'),
                        scheme,
                        highlight: streak > 0,
                      ),
                      const SizedBox(width: 10),
                      _stat(
                        r7 == 0 ? '—' : '$acc7%',
                        tr('stat_accuracy_7d'),
                        scheme,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Reveal(
                  delay: const Duration(milliseconds: 160),
                  child: WeeklyRecapCard(
                    reviews: r7,
                    activeDays: activeDays7,
                    accuracy: acc7,
                    streak: streak,
                  ),
                ),
                ..._extraStats(scheme),
                ..._vocabSection(scheme),
                ..._posSection(scheme),
                ..._readingSection(scheme),
                ..._weeklySection(scheme, now),
                ..._languageSection(scheme),
                const SizedBox(height: 24),
                _sectionTitle(tr('activity'), scheme),
                const SizedBox(height: 12),
                Reveal(
                  delay: const Duration(milliseconds: 180),
                  child: _activityCard(scheme, now),
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

  /// Секция «Чтение»: время, скорость (слов/мин), книг прочитано / в процессе.
  List<Widget> _readingSection(ColorScheme scheme) {
    final seconds = _repo.readingSeconds;
    final words = _repo.readingWords;
    if (_books.isEmpty && seconds <= 0) return const [];
    final finished = _books.where((b) => b.isFinished).length;
    final reading =
        _books.where((b) => b.isStarted && !b.isFinished).length;
    final wpm = seconds > 0 ? (words / (seconds / 60)).round() : 0;
    return [
      const SizedBox(height: 24),
      _sectionTitle(tr('reading_stats'), scheme),
      const SizedBox(height: 12),
      Reveal(
        delay: const Duration(milliseconds: 170),
        child: Row(
          children: [
            _stat(_fmtDuration(seconds), tr('stat_read_time'), scheme),
            const SizedBox(width: 10),
            _stat(wpm > 0 ? '$wpm' : '—', tr('stat_read_speed'), scheme),
          ],
        ),
      ),
      const SizedBox(height: 10),
      Reveal(
        delay: const Duration(milliseconds: 190),
        child: Row(
          children: [
            _stat('$finished', tr('stat_books_read'), scheme,
                highlight: finished > 0),
            const SizedBox(width: 10),
            _stat('$reading', tr('stat_books_reading'), scheme),
          ],
        ),
      ),
    ];
  }

  String _fmtDuration(int seconds) {
    final m = seconds ~/ 60;
    if (m < 60) return trf('read_min', {'m': m});
    final h = m ~/ 60;
    final rem = m % 60;
    return rem == 0
        ? trf('read_hr', {'h': h})
        : trf('read_hr_min', {'h': h, 'm': rem});
  }

  // Цвета статусов словаря (согласованы с анализом книги).
  static const Color _cNew = Color(0xFF5B8DEF);
  static const Color _cLearning = Color(0xFFDDA13F);
  static const Color _cYoung = Color(0xFF7A5AA8);
  static const Color _cMature = Color(0xFF2E9E6B);

  ({int fresh, int learning, int young, int mature}) _vocabCounts() {
    var f = 0, l = 0, y = 0, m = 0;
    for (final c in _cards) {
      switch (c.status) {
        case CardStatus.fresh:
          f++;
        case CardStatus.learning:
          l++;
        case CardStatus.young:
          y++;
        case CardStatus.mature:
          m++;
      }
    }
    return (fresh: f, learning: l, young: y, mature: m);
  }

  // Доп. статистика: рекорд серии, дней занятий, повторов/день, % выучено.
  List<Widget> _extraStats(ColorScheme scheme) {
    final best = _log.bestStreak();
    final days = _log.daysStudied;
    final avg = days > 0 ? (_log.totalReviews / days).round() : 0;
    final v = _vocabCounts();
    final total = _cards.length;
    final masteredPct = total > 0 ? (v.mature / total * 100).round() : 0;
    return [
      const SizedBox(height: 10),
      Reveal(
        delay: const Duration(milliseconds: 165),
        child: Row(
          children: [
            _stat('$best', tr('best_streak'), scheme, highlight: best > 0),
            const SizedBox(width: 10),
            _stat('$days', tr('days_studied'), scheme),
          ],
        ),
      ),
      const SizedBox(height: 10),
      Reveal(
        delay: const Duration(milliseconds: 185),
        child: Row(
          children: [
            _stat('$avg', tr('reviews_per_day'), scheme),
            const SizedBox(width: 10),
            _stat('$masteredPct%', tr('mastered_pct'), scheme),
          ],
        ),
      ),
    ];
  }

  // Состав словаря: полоса new/learning/young/mature + легенда.
  List<Widget> _vocabSection(ColorScheme scheme) {
    if (_cards.isEmpty) return const [];
    final v = _vocabCounts();
    final segs = <(int, Color, String)>[
      (v.fresh, _cNew, tr('stat_new')),
      (v.learning, _cLearning, tr('status_learning')),
      (v.young, _cYoung, tr('status_young')),
      (v.mature, _cMature, tr('status_mature')),
    ];
    return [
      const SizedBox(height: 24),
      _sectionTitle(tr('vocabulary'), scheme),
      const SizedBox(height: 12),
      Reveal(
        delay: const Duration(milliseconds: 175),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _segmentBar([for (final s in segs) (s.$1, s.$2)], scheme),
              const SizedBox(height: 14),
              Wrap(
                spacing: 16,
                runSpacing: 8,
                children: [
                  for (final s in segs) _legendItem(s.$2, s.$3, s.$1, scheme),
                ],
              ),
            ],
          ),
        ),
      ),
    ];
  }

  // Распределение по частям речи (если у карт есть теги).
  List<Widget> _posSection(ColorScheme scheme) {
    final counts = <String, int>{};
    for (final c in _cards) {
      if (c.pos.isNotEmpty) counts[c.pos] = (counts[c.pos] ?? 0) + 1;
    }
    if (counts.isEmpty) return const [];
    final codes = PosDetect.order.where(counts.containsKey).toList()
      ..sort((a, b) => counts[b]!.compareTo(counts[a]!));
    final max = counts.values.fold(0, (m, v) => v > m ? v : m);
    return [
      const SizedBox(height: 24),
      _sectionTitle(tr('by_pos'), scheme),
      const SizedBox(height: 12),
      Reveal(
        delay: const Duration(milliseconds: 175),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            children: [
              for (final code in codes)
                _barRow(
                  tr('pos_deck_$code'),
                  counts[code]!,
                  max,
                  Color(PosDetect.colorOf(code)),
                  scheme,
                ),
            ],
          ),
        ),
      ),
    ];
  }

  // Повторы по дням за последние 14 дней (мини-гистограмма).
  List<Widget> _weeklySection(ColorScheme scheme, DateTime now) {
    const days = 14;
    final today = DateTime(now.year, now.month, now.day);
    final vals = [
      for (var i = days - 1; i >= 0; i--)
        _log.reviewsOn(today.subtract(Duration(days: i))),
    ];
    if (vals.every((v) => v == 0)) return const [];
    final max = vals.fold(0, (m, v) => v > m ? v : m);
    return [
      const SizedBox(height: 24),
      _sectionTitle(tr('weekly_reviews'), scheme),
      const SizedBox(height: 12),
      Reveal(
        delay: const Duration(milliseconds: 175),
        child: Container(
          height: 120,
          padding: const EdgeInsets.fromLTRB(14, 16, 14, 12),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final v in vals)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TweenAnimationBuilder<double>(
                          tween: Tween(end: max == 0 ? 0.0 : v / max),
                          duration: const Duration(milliseconds: 600),
                          curve: AppTheme.emphasizedDecelerate,
                          builder: (_, t, _) => Container(
                            height: 6 + t * 62,
                            decoration: BoxDecoration(
                              color: v == 0
                                  ? scheme.surfaceContainerHighest
                                  : scheme.primary,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ];
  }

  // Разбивка словаря по изучаемым языкам.
  List<Widget> _languageSection(ColorScheme scheme) {
    final deckLang = {for (final d in _decks) d.id: d.languageCode};
    final counts = <String, int>{};
    for (final c in _cards) {
      final l = deckLang[c.deckId];
      if (l != null) counts[l] = (counts[l] ?? 0) + 1;
    }
    if (counts.length < 2) return const [];
    final langs = counts.keys.toList()
      ..sort((a, b) => counts[b]!.compareTo(counts[a]!));
    final max = counts.values.fold(0, (m, v) => v > m ? v : m);
    return [
      const SizedBox(height: 24),
      _sectionTitle(tr('by_language'), scheme),
      const SizedBox(height: 12),
      Reveal(
        delay: const Duration(milliseconds: 175),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            children: [
              for (final code in langs)
                _barRow(
                  _langName(code),
                  counts[code]!,
                  max,
                  scheme.primary,
                  scheme,
                ),
            ],
          ),
        ),
      ),
    ];
  }

  String _langName(String code) {
    final l = LanguageRegistry.instance.byCode(code);
    return l == null ? code.toUpperCase() : '${l.emoji} ${l.name}';
  }

  // ---- мелкие строительные блоки ----

  Widget _segmentBar(List<(int, Color)> segs, ColorScheme scheme) {
    final total = segs.fold(0, (s, e) => s + e.$1);
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        height: 14,
        child: total == 0
            ? ColoredBox(color: scheme.surfaceContainerHighest)
            : Row(
                children: [
                  for (final s in segs)
                    if (s.$1 > 0)
                      Expanded(flex: s.$1, child: ColoredBox(color: s.$2)),
                ],
              ),
      ),
    );
  }

  Widget _legendItem(Color color, String label, int count, ColorScheme scheme) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          '$label · $count',
          style: TextStyle(
            fontFamily: AppTheme.bodyFont,
            fontSize: 12.5,
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _barRow(
    String label,
    int count,
    int max,
    Color color,
    ColorScheme scheme,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: AppTheme.bodyFont,
                fontSize: 13,
                color: scheme.onSurface,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: max == 0 ? 0.0 : count / max),
                duration: const Duration(milliseconds: 650),
                curve: AppTheme.emphasizedDecelerate,
                builder: (_, t, _) => LinearProgressIndicator(
                  value: t,
                  minHeight: 10,
                  backgroundColor: scheme.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation(color),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '$count',
            style: TextStyle(
              fontFamily: AppTheme.displayFont,
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: scheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  Widget _stat(
    String value,
    String label,
    ColorScheme scheme, {
    bool highlight = false,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
        decoration: BoxDecoration(
          color: highlight
              ? scheme.primaryContainer
              : scheme.surfaceContainerHigh,
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
                color: highlight ? scheme.onPrimaryContainer : scheme.onSurface,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: AppTheme.bodyFont,
                fontSize: 12,
                color: highlight
                    ? scheme.onPrimaryContainer.withValues(alpha: 0.85)
                    : scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Тепловая карта активности (в духе «травки» GitHub): последние ~18 недель,
  /// колонки — недели, строки — дни, насыщенность = число повторов.
  Widget _activityCard(ColorScheme scheme, DateTime now) {
    const weeks = 18;
    const gap = 3.0;
    final today = DateTime(now.year, now.month, now.day);
    // Понедельник самой ранней недели в сетке.
    final startMonday = today.subtract(
      Duration(days: (weeks - 1) * 7 + (today.weekday - 1)),
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (_, c) {
              final cell = ((c.maxWidth - (weeks - 1) * gap) / weeks).clamp(
                6.0,
                18.0,
              );
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var w = 0; w < weeks; w++)
                    Padding(
                      padding: EdgeInsets.only(right: w == weeks - 1 ? 0 : gap),
                      child: Column(
                        children: [
                          for (var d = 0; d < 7; d++)
                            _heatCell(
                              startMonday.add(Duration(days: w * 7 + d)),
                              today,
                              cell,
                              gap,
                              scheme,
                            ),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          _heatLegend(scheme),
        ],
      ),
    );
  }

  Widget _heatCell(
    DateTime day,
    DateTime today,
    double size,
    double gap,
    ColorScheme scheme,
  ) {
    final future = day.isAfter(today);
    final reviews = future ? 0 : _log.reviewsOn(day);
    return Padding(
      padding: EdgeInsets.only(bottom: gap),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: future ? Colors.transparent : _heatColor(reviews, scheme),
          borderRadius: BorderRadius.circular(3),
        ),
      ),
    );
  }

  Color _heatColor(int reviews, ColorScheme scheme) {
    if (reviews <= 0) return scheme.surfaceContainerHighest;
    final p = scheme.primary;
    if (reviews < 4) return p.withValues(alpha: 0.35);
    if (reviews < 10) return p.withValues(alpha: 0.55);
    if (reviews < 20) return p.withValues(alpha: 0.78);
    return p;
  }

  Widget _heatLegend(ColorScheme scheme) {
    Widget box(Color c) => Container(
      width: 11,
      height: 11,
      margin: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        color: c,
        borderRadius: BorderRadius.circular(3),
      ),
    );
    final p = scheme.primary;
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text(
          tr('less'),
          style: TextStyle(
            fontFamily: AppTheme.bodyFont,
            fontSize: 11,
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: 6),
        box(scheme.surfaceContainerHighest),
        box(p.withValues(alpha: 0.35)),
        box(p.withValues(alpha: 0.55)),
        box(p.withValues(alpha: 0.78)),
        box(p),
        const SizedBox(width: 6),
        Text(
          tr('more'),
          style: TextStyle(
            fontFamily: AppTheme.bodyFont,
            fontSize: 11,
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
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
    final labels = [tr('forecast_today'), '+1', '+2', '+3', '+4', '+5', '+6'];

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
                          color: i == 0
                              ? scheme.primary
                              : scheme.primary.withValues(alpha: 0.5),
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
    final hard =
        _cards
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
                Icon(
                  Icons.local_fire_department_rounded,
                  color: scheme.error,
                  size: 20,
                ),
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
