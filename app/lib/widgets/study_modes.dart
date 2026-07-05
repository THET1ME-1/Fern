import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/strings.dart';
import '../models/deck.dart';
import '../models/word_card.dart';
import '../study/match_screen.dart';
import '../study/session_screen.dart';
import '../study/study_models.dart';
import '../theme/app_theme.dart';

/// Сетка режимов «Как учить» (крупная плитка «Учить» + сетка остальных).
/// Общая для экрана колоды и экрана пака: [deck] может быть синтетической
/// «колодой пака», [cards] — все карты пака, [reload] — как перезагрузить их
/// для «Ещё сессия».
class StudyModesGrid extends StatelessWidget {
  final Deck deck;
  final List<WordCard> cards;
  final Future<List<WordCard>> Function()? reload;

  const StudyModesGrid({
    super.key,
    required this.deck,
    required this.cards,
    this.reload,
  });

  // (режим, иконка, ключ названия, ключ подписи)
  static const List<(StudyMode, IconData, String, String)> _modes = [
    (StudyMode.learn, Icons.auto_awesome_rounded, 'mode_learn', 'mode_learn_sub'),
    (StudyMode.flashcards, Icons.style_rounded, 'mode_flashcards',
        'mode_flashcards_sub'),
    (StudyMode.test, Icons.quiz_rounded, 'mode_test', 'mode_test_sub'),
    (StudyMode.match, Icons.extension_rounded, 'mode_match', 'mode_match_sub'),
    (StudyMode.write, Icons.edit_rounded, 'mode_write', 'mode_write_sub'),
    (StudyMode.hard, Icons.local_fire_department_rounded, 'mode_hard',
        'mode_hard_sub'),
    (StudyMode.speed, Icons.bolt_rounded, 'mode_speed', 'mode_speed_sub'),
    (StudyMode.audio, Icons.headphones_rounded, 'mode_audio', 'mode_audio_sub'),
    (StudyMode.cloze, Icons.short_text_rounded, 'mode_cloze', 'mode_cloze_sub'),
  ];

  void _launch(BuildContext context, StudyMode mode) {
    if (cards.isEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(tr('empty_deck_sub'))));
      return;
    }
    HapticFeedback.selectionClick();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => mode == StudyMode.match
            ? MatchScreen(deck: deck, cards: cards)
            : SessionScreen(
                deck: deck, mode: mode, cards: cards, reload: reload),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final rest = _modes.skip(1).toList();
    return Column(
      children: [
        _hero(context, _modes.first, scheme),
        const SizedBox(height: 12),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.55,
          ),
          itemCount: rest.length,
          itemBuilder: (_, i) => _tile(context, rest[i], scheme),
        ),
      ],
    );
  }

  Widget _hero(
    BuildContext context,
    (StudyMode, IconData, String, String) m,
    ColorScheme scheme,
  ) {
    return Material(
      color: scheme.primaryContainer,
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _launch(context, m.$1),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Icon(m.$2, size: 40, color: scheme.onPrimaryContainer),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr(m.$3),
                      style: TextStyle(
                        fontFamily: AppTheme.displayFont,
                        fontWeight: FontWeight.w800,
                        fontSize: 22,
                        color: scheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      tr(m.$4),
                      style: TextStyle(
                        fontFamily: AppTheme.bodyFont,
                        fontSize: 13,
                        color: scheme.onPrimaryContainer.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.play_circle_rounded,
                  size: 32, color: scheme.onPrimaryContainer),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tile(
    BuildContext context,
    (StudyMode, IconData, String, String) m,
    ColorScheme scheme,
  ) {
    return Material(
      color: scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _launch(context, m.$1),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(m.$2, size: 26, color: scheme.primary),
              const SizedBox(height: 6),
              Text(
                tr(m.$3),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: AppTheme.displayFont,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: scheme.onSurface,
                ),
              ),
              Text(
                tr(m.$4),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: AppTheme.bodyFont,
                  fontSize: 11.5,
                  height: 1.15,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
