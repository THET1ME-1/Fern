import 'package:flutter/material.dart';

import 'l10n/strings.dart';
import 'models/achievement.dart';
import 'models/review_log.dart';
import 'models/word_card.dart';
import 'services/deck_repository.dart';
import 'theme/app_theme.dart';
import 'widgets/reveal.dart';

/// Экран достижений (вех). Данные — из журнала занятий и карточек.
class AchievementsScreen extends StatefulWidget {
  const AchievementsScreen({super.key});

  @override
  State<AchievementsScreen> createState() => _AchievementsScreenState();
}

class _AchievementsScreenState extends State<AchievementsScreen> {
  final DeckRepository _repo = DeckRepository.instance;
  ReviewLog _log = ReviewLog.empty();
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
    final log = await _repo.reviewLog();
    if (!mounted) return;
    setState(() {
      _cards = cards;
      _log = log;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final items = buildAchievements(_log, _cards, DateTime.now());
    final earned = items.where((a) => a.earned).length;

    return Scaffold(
      appBar: AppBar(title: Text(tr('achievements'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                _header(scheme, earned, items.length),
                const SizedBox(height: 16),
                for (final e in items.asMap().entries)
                  Reveal(
                    delay: Duration(milliseconds: 30 * e.key.clamp(0, 12)),
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _tile(e.value, scheme),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _header(ColorScheme scheme, int earned, int total) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 20),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        children: [
          Icon(Icons.emoji_events_rounded,
              size: 40, color: scheme.onPrimaryContainer),
          const SizedBox(height: 8),
          Text(
            trf('ach_earned', {'n': earned, 'm': total}),
            style: TextStyle(
              fontFamily: AppTheme.displayFont,
              fontWeight: FontWeight.w800,
              fontSize: 26,
              color: scheme.onPrimaryContainer,
            ),
          ),
        ],
      ),
    );
  }

  Widget _tile(Achievement a, ColorScheme scheme) {
    final earned = a.earned;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: earned ? scheme.surfaceContainerHigh : scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(20),
        border: earned
            ? Border.all(color: scheme.primary.withValues(alpha: 0.4))
            : null,
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: earned
                  ? scheme.primary
                  : scheme.surfaceContainerHighest,
              shape: BoxShape.circle,
            ),
            child: Icon(
              earned ? a.icon : Icons.lock_rounded,
              size: 24,
              color: earned ? scheme.onPrimary : scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  a.title,
                  style: TextStyle(
                    fontFamily: AppTheme.displayFont,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: earned ? scheme.onSurface : scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  a.description,
                  style: TextStyle(
                    fontFamily: AppTheme.bodyFont,
                    fontSize: 13,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                if (!earned) ...[
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: a.progress,
                      minHeight: 6,
                      backgroundColor: scheme.surfaceContainerHighest,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${a.current.clamp(0, a.target)} / ${a.target}',
                    style: TextStyle(
                      fontFamily: AppTheme.bodyFont,
                      fontSize: 11,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (earned)
            Icon(Icons.check_circle_rounded, color: scheme.primary, size: 22),
        ],
      ),
    );
  }
}
