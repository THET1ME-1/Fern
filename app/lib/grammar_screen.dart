import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'analyze/rule_card_tile.dart';
import 'l10n/strings.dart';
import 'models/word_card.dart';
import 'services/construction_catalog.dart';
import 'services/construction_stats.dart';
import 'services/grammar_deck.dart';
import 'study/session_screen.dart';
import 'study/study_models.dart';
import 'theme/app_theme.dart';
import 'widgets/empty_state.dart';
import 'widgets/morph_shapes.dart';
import 'widgets/pressable.dart';
import 'widgets/reveal.dart';

/// Экран «Грамматика»: правила языка по уровням, и рядом с каждым — сколько раз
/// оно встречалось В СВОИХ текстах.
///
/// Учебник даёт правила по программе, Anki не даёт вовсе. Здесь порядок задают
/// собственные книги, видео и разобранные сообщения: то, что попадается сорок
/// раз, стоит выучить раньше того, что не встретилось ни разу.
class GrammarScreen extends StatefulWidget {
  final String languageCode;

  const GrammarScreen({super.key, required this.languageCode});

  @override
  State<GrammarScreen> createState() => _GrammarScreenState();
}

class _GrammarScreenState extends State<GrammarScreen> {
  bool _loading = true;
  List<Construction> _rules = const [];
  Map<String, RuleStat> _stats = const {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool refresh = false}) async {
    await ConstructionCatalog.instance.ensureLoaded(widget.languageCode);
    final stats = await ConstructionStats.forLanguage(
      widget.languageCode,
      refresh: refresh,
    );
    if (!mounted) return;
    setState(() {
      _rules = ConstructionCatalog.instance.all(widget.languageCode);
      _stats = stats;
      _loading = false;
    });
  }

  /// Правила уровня, встреченные чаще, идут выше: внутри уровня порядок задаёт
  /// собственный текст, а не алфавит.
  List<Construction> _ofLevel(String level) {
    final list = [
      for (final r in _rules)
        if (r.level == level) r,
    ]..sort((a, b) {
        final ha = _stats[a.code]?.hits ?? 0;
        final hb = _stats[b.code]?.hits ?? 0;
        return hb.compareTo(ha);
      });
    return list;
  }

  List<WordCard> get _cards => GrammarDeck.rules(widget.languageCode);

  Future<void> _study() async {
    final cards = _cards;
    if (cards.isEmpty) return;
    final deck = await GrammarDeck.ensure(widget.languageCode);
    if (!mounted) return;
    HapticFeedback.selectionClick();
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SessionScreen(
          deck: deck,
          mode: StudyMode.grammar,
          cards: cards,
          reload: () async => GrammarDeck.rules(widget.languageCode),
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _openRule(Construction rule) async {
    final learned = GrammarDeck.find(rule.code, widget.languageCode) != null;
    final stat = _stats[rule.code];
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RuleCardTile(
                rule: rule,
                snippet: rule.examples.isNotEmpty ? rule.examples.first : '',
                learned: learned,
                onLearn: learned
                    ? null
                    : () async {
                        await GrammarDeck.add(
                          languageCode: widget.languageCode,
                          code: rule.code,
                          name: rule.name,
                          hint: rule.hint(),
                          example: rule.examples.isNotEmpty
                              ? rule.examples.first
                              : '',
                        );
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (mounted) setState(() {});
                      },
              ),
              if (stat != null) ...[
                const SizedBox(height: 12),
                Text(
                  trf('grammar_met_detail', {
                    'n': '${stat.hits}',
                    'm': '${stat.sources}',
                  }),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: AppTheme.bodyFont,
                    fontSize: 13,
                    color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final learnedCount = _cards.length;
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('grammar_title')),
        actions: [
          IconButton(
            tooltip: tr('refresh'),
            onPressed: () => _load(refresh: true),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: Waiting(size: 36))
          : _rules.isEmpty
              ? EmptyState(
                  icon: Icons.rule_rounded,
                  title: tr('grammar_none_title'),
                  subtitle: tr('grammar_none_sub'),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  children: [
                    Reveal(child: _header(scheme, learnedCount)),
                    const SizedBox(height: 18),
                    for (final level in ConstructionCatalog.levels)
                      if (_ofLevel(level).isNotEmpty) ...[
                        _levelTitle(level, scheme),
                        const SizedBox(height: 10),
                        for (final rule in _ofLevel(level)) ...[
                          _ruleRow(rule, scheme),
                          const SizedBox(height: 8),
                        ],
                        const SizedBox(height: 14),
                      ],
                  ],
                ),
    );
  }

  Widget _header(ColorScheme scheme, int learned) {
    final met = _stats.length;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            trf('grammar_summary', {'n': '$learned', 'm': '$met'}),
            style: TextStyle(
              fontFamily: AppTheme.displayFont,
              fontWeight: FontWeight.w700,
              fontSize: 17,
              height: 1.3,
              color: scheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            tr('grammar_summary_sub'),
            style: TextStyle(
              fontFamily: AppTheme.bodyFont,
              fontSize: 13,
              height: 1.35,
              color: scheme.onPrimaryContainer.withValues(alpha: 0.85),
            ),
          ),
          if (learned > 0) ...[
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerLeft,
              child: PressableScale(
                child: FilledButton.icon(
                  onPressed: _study,
                  icon: const Icon(Icons.play_arrow_rounded, size: 20),
                  label: Text(tr('grammar_study')),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _levelTitle(String level, ColorScheme scheme) => Text(
        level,
        style: TextStyle(
          fontFamily: AppTheme.displayFont,
          fontWeight: FontWeight.w700,
          fontSize: 15,
          letterSpacing: 1.2,
          color: scheme.primary,
        ),
      );

  Widget _ruleRow(Construction rule, ColorScheme scheme) {
    final stat = _stats[rule.code];
    final card = GrammarDeck.find(rule.code, widget.languageCode);
    final met = stat?.hits ?? 0;

    return Material(
      color: scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openRule(rule),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      rule.name,
                      style: TextStyle(
                        fontFamily: AppTheme.displayFont,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      met == 0
                          ? tr('grammar_not_met')
                          : trn('n_times_met', met),
                      style: TextStyle(
                        fontFamily: AppTheme.bodyFont,
                        fontSize: 12.5,
                        color: met == 0
                            ? scheme.onSurfaceVariant.withValues(alpha: 0.7)
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _statusChip(card, scheme),
            ],
          ),
        ),
      ),
    );
  }

  /// Что с правилом: не взято, учится, выучено. Про «выучено» спрашиваем FSRS —
  /// ту же память, что и у слов.
  Widget _statusChip(WordCard? card, ColorScheme scheme) {
    if (card == null) {
      return Icon(Icons.add_circle_outline_rounded,
          size: 22, color: scheme.primary);
    }
    final mature = card.status == CardStatus.mature;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: mature ? scheme.tertiaryContainer : scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Text(
        mature ? tr('grammar_mastered') : tr('grammar_learning'),
        style: TextStyle(
          fontFamily: AppTheme.bodyFont,
          fontWeight: FontWeight.w600,
          fontSize: 11.5,
          color: mature
              ? scheme.onTertiaryContainer
              : scheme.onSecondaryContainer,
        ),
      ),
    );
  }
}

