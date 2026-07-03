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

/// Порядок сортировки списка карточек в колоде.
enum _CardSort { added, alpha, status, due }

extension _CardSortInfo on _CardSort {
  String get labelKey => switch (this) {
        _CardSort.added => 'sort_added',
        _CardSort.alpha => 'sort_alpha',
        _CardSort.status => 'sort_status',
        _CardSort.due => 'sort_due',
      };
  IconData get icon => switch (this) {
        _CardSort.added => Icons.schedule_rounded,
        _CardSort.alpha => Icons.sort_by_alpha_rounded,
        _CardSort.status => Icons.donut_small_rounded,
        _CardSort.due => Icons.notifications_active_rounded,
      };
}

/// Экран колоды: пусковая панель режимов обучения + список карточек.
class DeckScreen extends StatefulWidget {
  final Deck deck;
  const DeckScreen({super.key, required this.deck});

  @override
  State<DeckScreen> createState() => _DeckScreenState();
}

class _DeckScreenState extends State<DeckScreen> {
  final DeckRepository _repo = DeckRepository.instance;
  final TextEditingController _search = TextEditingController();
  List<WordCard> _cards = [];
  bool _loading = true;
  String _query = '';
  _CardSort _sort = _CardSort.added;

  @override
  void initState() {
    super.initState();
    _repo.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    _repo.removeListener(_load);
    _search.dispose();
    super.dispose();
  }

  /// Карточки после применения поиска и выбранной сортировки.
  List<WordCard> get _visibleCards {
    final q = _query.trim().toLowerCase();
    final list = q.isEmpty
        ? List<WordCard>.from(_cards)
        : _cards
            .where((c) =>
                c.front.toLowerCase().contains(q) ||
                c.back.toLowerCase().contains(q) ||
                c.example.toLowerCase().contains(q))
            .toList();
    final now = DateTime.now();
    switch (_sort) {
      case _CardSort.added:
        break; // естественный порядок добавления
      case _CardSort.alpha:
        list.sort((a, b) =>
            a.front.toLowerCase().compareTo(b.front.toLowerCase()));
      case _CardSort.status:
        list.sort((a, b) => a.status.index.compareTo(b.status.index));
      case _CardSort.due:
        int key(WordCard c) => c.isDue(now) ? 0 : 1;
        list.sort((a, b) {
          final byDue = key(a).compareTo(key(b));
          if (byDue != 0) return byDue;
          final da = a.review.due ?? DateTime(9999);
          final db = b.review.due ?? DateTime(9999);
          return da.compareTo(db);
        });
    }
    return list;
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
    await _repo.addCards(result);
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
                _cardsHeader(scheme),
                const SizedBox(height: 12),
                if (_cards.isEmpty)
                  _emptyCards(scheme)
                else ...[
                  if (_cards.length >= 6) ...[
                    _searchField(scheme),
                    const SizedBox(height: 12),
                  ],
                  ..._buildCardList(scheme),
                ],
              ],
            ),
    );
  }

  Widget _cardsHeader(ColorScheme scheme) {
    return Row(
      children: [
        Expanded(child: _sectionTitle(tr('cards_section'), scheme)),
        if (_cards.length >= 2)
          IconButton(
            tooltip: tr('sort_by'),
            icon: const Icon(Icons.sort_rounded),
            onPressed: _pickSort,
          ),
      ],
    );
  }

  Future<void> _pickSort() async {
    final scheme = Theme.of(context).colorScheme;
    final picked = await showModalBottomSheet<_CardSort>(
      context: context,
      backgroundColor: scheme.surfaceContainer,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            for (final s in _CardSort.values)
              ListTile(
                leading: Icon(s.icon,
                    color: s == _sort ? scheme.primary : scheme.onSurfaceVariant),
                title: Text(tr(s.labelKey)),
                trailing: s == _sort
                    ? Icon(Icons.check_rounded, color: scheme.primary)
                    : null,
                onTap: () => Navigator.pop(ctx, s),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked != null) setState(() => _sort = picked);
  }

  Widget _searchField(ColorScheme scheme) {
    return TextField(
      controller: _search,
      onChanged: (v) => setState(() => _query = v),
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        isDense: true,
        hintText: tr('search_cards'),
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: _query.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () {
                  _search.clear();
                  setState(() => _query = '');
                },
              ),
        filled: true,
        fillColor: scheme.surfaceContainerHigh,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  List<Widget> _buildCardList(ColorScheme scheme) {
    final cards = _visibleCards;
    if (cards.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 28),
          child: Center(
            child: Text(
              tr('no_matches'),
              style: TextStyle(
                fontFamily: AppTheme.bodyFont,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ];
    }
    return [
      for (final e in cards.asMap().entries)
        Reveal(
          delay: Duration(milliseconds: 25 * (e.key.clamp(0, 12))),
          child: _cardTile(e.value, scheme),
        ),
    ];
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

  /// Цвет + иконка + подпись статуса карты.
  ({Color color, IconData icon, String label}) _statusVisual(
      CardStatus s, ColorScheme scheme) {
    switch (s) {
      case CardStatus.fresh:
        return (
          color: scheme.primary,
          icon: Icons.fiber_new_rounded,
          label: tr('status_new')
        );
      case CardStatus.learning:
        return (
          color: scheme.tertiary,
          icon: Icons.trending_up_rounded,
          label: tr('status_learning')
        );
      case CardStatus.young:
        return (
          color: scheme.secondary,
          icon: Icons.spa_rounded,
          label: tr('status_young')
        );
      case CardStatus.mature:
        return (
          color: scheme.primary,
          icon: Icons.verified_rounded,
          label: tr('status_mature')
        );
    }
  }

  /// Короткая подпись срока повтора («к повтору» / «через 3 дн»).
  String _dueLabel(WordCard card, DateTime now) {
    if (card.review.isNew) return '';
    final due = card.review.due;
    if (due == null) return '';
    if (!due.isAfter(now)) return tr('due_now');
    return trf('due_in', {'t': durationLabel(due.difference(now))});
  }

  Widget _cardTile(WordCard card, ColorScheme scheme) {
    final now = DateTime.now();
    final vis = _statusVisual(card.status, scheme);
    final isDue = !card.review.isNew && card.isDue(now);
    final dueText = _dueLabel(card, now);
    final hasExample = card.example.trim().isNotEmpty;

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
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  // Индикатор статуса владения.
                  Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: vis.color.withValues(alpha: 0.16),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(vis.icon, size: 20, color: vis.color),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
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
                            ),
                            if (hasExample) ...[
                              const SizedBox(width: 6),
                              Icon(Icons.format_quote_rounded,
                                  size: 13, color: scheme.onSurfaceVariant),
                            ],
                          ],
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
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        vis.label,
                        style: TextStyle(
                          fontFamily: AppTheme.bodyFont,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: vis.color,
                        ),
                      ),
                      if (dueText.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          dueText,
                          style: TextStyle(
                            fontFamily: AppTheme.bodyFont,
                            fontSize: 10.5,
                            fontWeight: isDue ? FontWeight.w700 : FontWeight.w400,
                            color: isDue
                                ? scheme.primary
                                : scheme.onSurfaceVariant
                                    .withValues(alpha: 0.7),
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
