import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'l10n/strings.dart';
import 'models/deck.dart';
import 'models/word_card.dart';
import 'services/deck_repository.dart';
import 'study/match_screen.dart';
import 'study/session_screen.dart';
import 'study/study_models.dart';
import 'theme/app_theme.dart';
import 'widgets/deck_shapes.dart';
import 'widgets/reveal.dart';

/// Экран колоды: пусковая панель режимов обучения + список карточек.
class DeckScreen extends StatefulWidget {
  final Deck deck;
  const DeckScreen({super.key, required this.deck});

  @override
  State<DeckScreen> createState() => _DeckScreenState();
}

class _DeckScreenState extends State<DeckScreen> {
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
    final cards = await _repo.cardsForDeck(widget.deck.id);
    if (!mounted) return;
    setState(() {
      _cards = cards;
      _loading = false;
    });
  }

  ({int total, int due, int fresh, int mature}) get _counts {
    final now = DateTime.now();
    var due = 0, fresh = 0, mature = 0;
    for (final c in _cards) {
      if (c.review.isNew) {
        fresh++;
        due++;
      } else {
        if (c.isDue(now)) due++;
        if (c.review.stability >= 21) mature++;
      }
    }
    return (total: _cards.length, due: due, fresh: fresh, mature: mature);
  }

  void _launch(StudyMode mode, bool enabled) {
    if (!enabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('soon'))),
      );
      return;
    }
    if (_cards.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('empty_deck_sub'))),
      );
      return;
    }
    HapticFeedback.selectionClick();
    final route = MaterialPageRoute(
      builder: (_) => mode == StudyMode.match
          ? MatchScreen(deck: widget.deck, cards: _cards)
          : SessionScreen(deck: widget.deck, mode: mode, cards: _cards),
    );
    Navigator.push(context, route);
  }

  Future<void> _addOrEditCard([WordCard? existing]) async {
    final result = await showModalBottomSheet<WordCard>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => _CardEditorSheet(existing: existing, deckId: widget.deck.id),
    );
    if (result == null) return;
    await _repo.upsertCard(result);
  }

  Future<void> _quickAdd() async {
    final result = await showModalBottomSheet<List<WordCard>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => _QuickAddSheet(deckId: widget.deck.id),
    );
    if (result == null || result.isEmpty) return;
    final all = await _repo.loadCards()
      ..addAll(result);
    await _repo.saveCards(all);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(trf('added_n_cards', {'n': result.length}))),
      );
    }
  }

  Future<void> _deleteCard(WordCard card) async {
    await _repo.deleteCard(card.id);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final deck = widget.deck;

    return Scaffold(
      appBar: AppBar(
        title: Text(deck.name),
        actions: [
          IconButton(
            tooltip: tr('quick_add'),
            icon: const Icon(Icons.playlist_add_rounded),
            onPressed: _quickAdd,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addOrEditCard(),
        icon: const Icon(Icons.add_rounded),
        label: Text(tr('add_card')),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              children: [
                _header(deck, scheme),
                const SizedBox(height: 24),
                _sectionTitle(tr('modes_title'), scheme),
                const SizedBox(height: 12),
                _modesGrid(scheme),
                const SizedBox(height: 24),
                _sectionTitle(tr('cards_section'), scheme),
                const SizedBox(height: 12),
                if (_cards.isEmpty)
                  _emptyCards(scheme)
                else
                  ..._cards.asMap().entries.map(
                        (e) => Reveal(
                          delay: Duration(milliseconds: 25 * e.key),
                          child: _cardTile(e.value, scheme),
                        ),
                      ),
              ],
            ),
    );
  }

  Widget _header(Deck deck, ColorScheme scheme) {
    final c = _counts;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Row(
        children: [
          ShapedCover(
            label: deck.name,
            color: deck.color,
            imagePath: null,
            size: 72,
            shape: deckShape(deck.shapeIndex),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _miniStat('${c.total}', tr('cards_total'), scheme),
                _miniStat('${c.due}', tr('stat_due'), scheme,
                    highlight: c.due > 0),
                _miniStat('${c.mature}', tr('stat_mature'), scheme),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniStat(String value, String label, ColorScheme scheme,
      {bool highlight = false}) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontFamily: AppTheme.displayFont,
            fontWeight: FontWeight.w800,
            fontSize: 22,
            color: highlight ? scheme.primary : scheme.onSurface,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontFamily: AppTheme.bodyFont,
            fontSize: 11,
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _modesGrid(ColorScheme scheme) {
    // (режим, иконка, ключ названия, ключ подписи, доступен)
    final modes = <(StudyMode, IconData, String, String, bool)>[
      (StudyMode.learn, Icons.auto_awesome_rounded, 'mode_learn',
          'mode_learn_sub', true),
      (StudyMode.flashcards, Icons.style_rounded, 'mode_flashcards',
          'mode_flashcards_sub', true),
      (StudyMode.test, Icons.quiz_rounded, 'mode_test', 'mode_test_sub', true),
      (StudyMode.match, Icons.extension_rounded, 'mode_match', 'mode_match_sub',
          true),
      (StudyMode.write, Icons.edit_rounded, 'mode_write', 'mode_write_sub',
          true),
      (StudyMode.hard, Icons.local_fire_department_rounded, 'mode_hard',
          'mode_hard_sub', true),
      (StudyMode.speed, Icons.bolt_rounded, 'mode_speed', 'mode_speed_sub',
          true),
      (StudyMode.audio, Icons.headphones_rounded, 'mode_audio', 'mode_audio_sub',
          false),
    ];
    final learn = modes.first;
    final rest = modes.skip(1).toList();

    return Column(
      children: [
        // «Учить» — крупная главная плитка во всю ширину.
        _heroMode(learn, scheme),
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
          itemBuilder: (_, i) => _modeTile(rest[i], scheme),
        ),
      ],
    );
  }

  Widget _heroMode(
      (StudyMode, IconData, String, String, bool) m, ColorScheme scheme) {
    return Material(
      color: scheme.primaryContainer,
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _launch(m.$1, m.$5),
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

  Widget _modeTile(
      (StudyMode, IconData, String, String, bool) m, ColorScheme scheme) {
    final enabled = m.$5;
    return Material(
      color: scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _launch(m.$1, enabled),
        child: Opacity(
          opacity: enabled ? 1 : 0.5,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(m.$2, size: 26, color: scheme.primary),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Flexible(
                      child: Text(
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
                    ),
                    if (!enabled) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: scheme.tertiaryContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          tr('soon'),
                          style: TextStyle(
                            fontFamily: AppTheme.bodyFont,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: scheme.onTertiaryContainer,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String text, ColorScheme scheme) => Text(
        text,
        style: TextStyle(
          fontFamily: AppTheme.displayFont,
          fontWeight: FontWeight.w700,
          fontSize: 18,
          color: scheme.onSurface,
        ),
      );

  Widget _cardTile(WordCard card, ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Dismissible(
        key: ValueKey(card.id),
        direction: DismissDirection.endToStart,
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 24),
          decoration: BoxDecoration(
            color: scheme.errorContainer,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Icon(Icons.delete_rounded, color: scheme.onErrorContainer),
        ),
        onDismissed: (_) => _deleteCard(card),
        child: Material(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(18),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => _addOrEditCard(card),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          card.front,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: AppTheme.bodyFont,
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                            color: scheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          card.back,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: AppTheme.bodyFont,
                            fontSize: 14,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (card.review.isNew)
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: scheme.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _emptyCards(ColorScheme scheme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          Icon(Icons.add_card_rounded, size: 48, color: scheme.primary),
          const SizedBox(height: 12),
          Text(
            tr('empty_deck_title'),
            style: TextStyle(
              fontFamily: AppTheme.displayFont,
              fontWeight: FontWeight.w700,
              fontSize: 17,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            tr('empty_deck_sub'),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: AppTheme.bodyFont,
              fontSize: 13,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================ Редактор карточки ============================

class _CardEditorSheet extends StatefulWidget {
  final WordCard? existing;
  final String deckId;
  const _CardEditorSheet({this.existing, required this.deckId});

  @override
  State<_CardEditorSheet> createState() => _CardEditorSheetState();
}

class _CardEditorSheetState extends State<_CardEditorSheet> {
  late final TextEditingController _front;
  late final TextEditingController _back;
  late final TextEditingController _example;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _front = TextEditingController(text: e?.front ?? '');
    _back = TextEditingController(text: e?.back ?? '');
    _example = TextEditingController(text: e?.example ?? '');
  }

  @override
  void dispose() {
    _front.dispose();
    _back.dispose();
    _example.dispose();
    super.dispose();
  }

  void _save() {
    final front = _front.text.trim();
    final back = _back.text.trim();
    if (front.isEmpty || back.isEmpty) return;
    HapticFeedback.selectionClick();
    final e = widget.existing;
    final card = WordCard(
      id: e?.id ?? 'card_${DateTime.now().microsecondsSinceEpoch}',
      deckId: widget.deckId,
      front: front,
      back: back,
      example: _example.text.trim(),
      review: e?.review,
    );
    Navigator.pop(context, card);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: scheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                tr(widget.existing == null ? 'add_card' : 'edit_card'),
                style: TextStyle(
                  fontFamily: AppTheme.displayFont,
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                  color: scheme.onSurface,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _front,
                autofocus: widget.existing == null,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: tr('card_front'),
                  prefixIcon: const Icon(Icons.translate_rounded),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _back,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: tr('card_back'),
                  prefixIcon: const Icon(Icons.g_translate_rounded),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _example,
                textCapitalization: TextCapitalization.sentences,
                maxLines: 2,
                minLines: 1,
                decoration: InputDecoration(
                  labelText: tr('card_example'),
                  prefixIcon: const Icon(Icons.format_quote_rounded),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.tonal(
                      onPressed: () => Navigator.pop(context),
                      child: Text(tr('cancel')),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _save,
                      child: Text(tr('save')),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================ Быстрое добавление списком ============================

class _QuickAddSheet extends StatefulWidget {
  final String deckId;
  const _QuickAddSheet({required this.deckId});

  @override
  State<_QuickAddSheet> createState() => _QuickAddSheetState();
}

class _QuickAddSheetState extends State<_QuickAddSheet> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _apply() {
    final lines = _controller.text.split('\n');
    final cards = <WordCard>[];
    var i = 0;
    for (final line in lines) {
      final parts = line.split(RegExp(r'\s[—–-]\s|\t'));
      if (parts.length < 2) continue;
      final front = parts[0].trim();
      final back = parts.sublist(1).join(' ').trim();
      if (front.isEmpty || back.isEmpty) continue;
      cards.add(WordCard(
        id: 'card_${DateTime.now().microsecondsSinceEpoch}_${i++}',
        deckId: widget.deckId,
        front: front,
        back: back,
      ));
    }
    Navigator.pop(context, cards);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: scheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                tr('quick_add'),
                style: TextStyle(
                  fontFamily: AppTheme.displayFont,
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                  color: scheme.onSurface,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                tr('quick_add_hint'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: AppTheme.bodyFont,
                  fontSize: 13,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _controller,
                autofocus: true,
                maxLines: 8,
                minLines: 5,
                decoration: InputDecoration(
                  hintText: 'hello — привет\nwater — вода',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _apply,
                  icon: const Icon(Icons.playlist_add_check_rounded),
                  label: Text(tr('quick_add_apply')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
