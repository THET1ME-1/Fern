import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import 'review_log.dart';
import 'word_card.dart';

/// Достижение (веха). Значение прогресса берётся из журнала занятий и карт.
class Achievement {
  final IconData icon;
  final String title;
  final String description;
  final int current;
  final int target;

  const Achievement({
    required this.icon,
    required this.title,
    required this.description,
    required this.current,
    required this.target,
  });

  bool get earned => current >= target;
  double get progress =>
      target == 0 ? 1 : (current / target).clamp(0, 1).toDouble();
}

/// Собирает список достижений из статистики пользователя.
List<Achievement> buildAchievements(
    ReviewLog log, List<WordCard> cards, DateTime now) {
  final streak = log.streak(now);
  final reviews = log.totalReviews;
  final mastered =
      cards.where((c) => !c.review.isNew && c.review.stability >= 21).length;
  final seen = cards.where((c) => !c.review.isNew).length;

  Achievement reviewsA(int t, String titleKey, IconData icon) => Achievement(
        icon: icon,
        title: tr(titleKey),
        description: trf('ach_desc_reviews', {'n': t}),
        current: reviews,
        target: t,
      );
  Achievement streakA(int t, String titleKey, IconData icon) => Achievement(
        icon: icon,
        title: tr(titleKey),
        description: trf('ach_desc_streak', {'n': t}),
        current: streak,
        target: t,
      );
  Achievement masteredA(int t, String titleKey, IconData icon) => Achievement(
        icon: icon,
        title: tr(titleKey),
        description: trf('ach_desc_mastered', {'n': t}),
        current: mastered,
        target: t,
      );
  Achievement seenA(int t, String titleKey, IconData icon) => Achievement(
        icon: icon,
        title: tr(titleKey),
        description: trf('ach_desc_seen', {'n': t}),
        current: seen,
        target: t,
      );

  return [
    Achievement(
      icon: Icons.flag_rounded,
      title: tr('ach_first'),
      description: tr('ach_first_desc'),
      current: reviews,
      target: 1,
    ),
    reviewsA(50, 'ach_warmup', Icons.fitness_center_rounded),
    reviewsA(500, 'ach_worker', Icons.bolt_rounded),
    reviewsA(2000, 'ach_marathon', Icons.emoji_events_rounded),
    streakA(3, 'ach_streak3', Icons.local_fire_department_rounded),
    streakA(7, 'ach_streak7', Icons.local_fire_department_rounded),
    streakA(30, 'ach_streak30', Icons.whatshot_rounded),
    seenA(25, 'ach_hello', Icons.visibility_rounded),
    seenA(150, 'ach_vocab', Icons.menu_book_rounded),
    masteredA(10, 'ach_ten', Icons.school_rounded),
    masteredA(50, 'ach_fifty', Icons.workspace_premium_rounded),
    masteredA(200, 'ach_polyglot', Icons.verified_rounded),
  ];
}
