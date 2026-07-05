import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'l10n/locale_controller.dart';
import 'l10n/strings.dart';
import 'models/deck.dart';
import 'models/word_card.dart';
import 'services/deck_repository.dart';
import 'services/pos.dart';
import 'services/pos_split.dart';
import 'services/translation/translation_manager.dart';
import 'theme/app_theme.dart';
import 'widgets/deck_shapes.dart';
import 'widgets/reveal.dart';
import 'widgets/speaker_button.dart';
import 'widgets/study_modes.dart';

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
  String _posFilter = ''; // '' = все части речи

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
  /// Части речи, встречающиеся в колоде → число карт (для фильтр-чипов).
  Map<String, int> get _posCounts {
    final counts = <String, int>{};
    for (final c in _cards) {
      if (c.pos.isNotEmpty) counts[c.pos] = (counts[c.pos] ?? 0) + 1;
    }
    return counts;
  }

  List<WordCard> get _visibleCards {
    final q = _query.trim().toLowerCase();
    var list = q.isEmpty
        ? List<WordCard>.from(_cards)
        : _cards
              .where(
                (c) =>
                    c.front.toLowerCase().contains(q) ||
                    c.back.toLowerCase().contains(q) ||
                    c.example.toLowerCase().contains(q),
              )
              .toList();
    if (_posFilter.isNotEmpty) {
      list = list.where((c) => c.pos == _posFilter).toList();
    }
    final now = DateTime.now();
    switch (_sort) {
      case _CardSort.added:
        break; // естественный порядок добавления
      case _CardSort.alpha:
        list.sort(
          (a, b) => a.front.toLowerCase().compareTo(b.front.toLowerCase()),
        );
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

  /// Раскладывает колоду по частям речи (в отдельный пак с колодами по типам).
  /// По умолчанию сперва спрашивает подтверждение (с галочкой «не спрашивать»).
  Future<void> _splitByPos() async {
    if (await _repo.posSplitAsk()) {
      if (!mounted) return;
      var dontAsk = false;
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setD) => AlertDialog(
            title: Text(tr('split_by_pos')),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr('split_confirm')),
                const SizedBox(height: 8),
                CheckboxListTile(
                  value: dontAsk,
                  onChanged: (v) => setD(() => dontAsk = v ?? false),
                  title: Text(tr('dont_ask_again')),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  dense: true,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(tr('cancel')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(tr('apply')),
              ),
            ],
          ),
        ),
      );
      if (ok != true) return;
      if (dontAsk) await _repo.setPosSplitAsk(false);
    }
    final created = await PosSplit.split(widget.deck);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(created > 0
            ? trf('split_done', {'n': created})
            : tr('split_none')),
      ));
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

  Future<void> _addOrEditCard([WordCard? existing]) async {
    final result = await showModalBottomSheet<WordCard>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => _CardEditorSheet(
        existing: existing,
        deckId: widget.deck.id,
        languageCode: widget.deck.languageCode,
      ),
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
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'split') _splitByPos();
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'split',
                child: Row(
                  children: [
                    const Icon(Icons.category_outlined, size: 20),
                    const SizedBox(width: 10),
                    Text(tr('split_by_pos')),
                  ],
                ),
              ),
            ],
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
                StudyModesGrid(deck: widget.deck, cards: _cards),
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
                  if (_posCounts.length >= 2) ...[
                    _posFilterRow(scheme),
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
                leading: Icon(
                  s.icon,
                  color: s == _sort ? scheme.primary : scheme.onSurfaceVariant,
                ),
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
                _miniStat(
                  '${c.due}',
                  tr('stat_due'),
                  scheme,
                  highlight: c.due > 0,
                ),
                _miniStat('${c.mature}', tr('stat_mature'), scheme),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniStat(
    String value,
    String label,
    ColorScheme scheme, {
    bool highlight = false,
  }) {
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
    CardStatus s,
    ColorScheme scheme,
  ) {
    switch (s) {
      case CardStatus.fresh:
        return (
          color: scheme.primary,
          icon: Icons.fiber_new_rounded,
          label: tr('status_new'),
        );
      case CardStatus.learning:
        return (
          color: scheme.tertiary,
          icon: Icons.trending_up_rounded,
          label: tr('status_learning'),
        );
      case CardStatus.young:
        return (
          color: scheme.secondary,
          icon: Icons.spa_rounded,
          label: tr('status_young'),
        );
      case CardStatus.mature:
        return (
          color: scheme.primary,
          icon: Icons.verified_rounded,
          label: tr('status_mature'),
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

  /// Горизонтальный ряд фильтр-чипов по частям речи (+«Все»).
  Widget _posFilterRow(ColorScheme scheme) {
    final counts = _posCounts;
    // По порядку частотности типов.
    final codes =
        PosDetect.order.where((c) => counts.containsKey(c)).toList();
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _posFilterChip('', tr('pos_filter_all'), _cards.length, scheme),
          for (final code in codes) ...[
            const SizedBox(width: 8),
            _posFilterChip(
              code,
              tr('pos_deck_$code'),
              counts[code]!,
              scheme,
            ),
          ],
        ],
      ),
    );
  }

  Widget _posFilterChip(
    String code,
    String label,
    int count,
    ColorScheme scheme,
  ) {
    final selected = _posFilter == code;
    return FilterChip(
      label: Text('$label · $count'),
      selected: selected,
      visualDensity: VisualDensity.compact,
      onSelected: (_) => setState(() => _posFilter = selected ? '' : code),
    );
  }

  /// Цветной тег части речи рядом со словом (гл./сущ./арт.…).
  Widget _posBadge(String code, ColorScheme scheme) {
    final color = Color(PosDetect.colorOf(code));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        tr('pos_short_$code'),
        style: TextStyle(
          fontFamily: AppTheme.bodyFont,
          fontWeight: FontWeight.w700,
          fontSize: 11,
          color: color,
        ),
      ),
    );
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
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
                            if (card.pos.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              _posBadge(card.pos, scheme),
                            ],
                            if (hasExample) ...[
                              const SizedBox(width: 6),
                              Icon(
                                Icons.format_quote_rounded,
                                size: 13,
                                color: scheme.onSurfaceVariant,
                              ),
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
                  SpeakerButton(
                    text: card.front,
                    languageCode: widget.deck.languageCode,
                    sourceUrl: card.sourceUrl,
                    clipStartMs: card.clipStartMs,
                    clipEndMs: card.clipEndMs,
                  ),
                  const SizedBox(width: 4),
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
                            fontWeight: isDue
                                ? FontWeight.w700
                                : FontWeight.w400,
                            color: isDue
                                ? scheme.primary
                                : scheme.onSurfaceVariant.withValues(
                                    alpha: 0.7,
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
  final String languageCode;
  const _CardEditorSheet({
    this.existing,
    required this.deckId,
    required this.languageCode,
  });

  @override
  State<_CardEditorSheet> createState() => _CardEditorSheetState();
}

class _CardEditorSheetState extends State<_CardEditorSheet> {
  late final TextEditingController _front;
  late final TextEditingController _back;
  late final TextEditingController _example;
  String _pos = '';
  bool _translating = false;

  /// Варианты перевода/значения для выбора чипсом и словарные подсказки.
  List<String> _options = [];
  String? _partOfSpeech;
  String? _phonetic;
  List<String> _dictExamples = [];

  final TranslationManager _mgr = TranslationManager.instance;

  /// Язык перевода = язык интерфейса пользователя (его родной).
  String get _targetLang => LocaleController.instance.code;
  bool get _canTranslate =>
      _mgr.canTranslate(widget.languageCode, _targetLang);

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _front = TextEditingController(text: e?.front ?? '');
    _back = TextEditingController(text: e?.back ?? '');
    _example = TextEditingController(text: e?.example ?? '');
    _pos = e?.pos ?? '';
  }

  Future<void> _translate() async {
    final text = _front.text.trim();
    if (text.isEmpty || _translating) return;
    HapticFeedback.selectionClick();
    // Для офлайн-провайдера (ML Kit) при первом использовании модель качается —
    // предупредим, чтобы не выглядело зависанием.
    if (_mgr.active.isOffline) {
      final ready =
          await _mgr.active.isReady(widget.languageCode, _targetLang);
      if (mounted && !ready) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(tr('translate_downloading'))));
      }
    }
    setState(() => _translating = true);
    final res = await _mgr.translate(
      text,
      widget.languageCode,
      _targetLang,
      context: _example.text.trim().isEmpty ? null : _example.text.trim(),
    );
    if (!mounted) return;
    setState(() {
      _translating = false;
      if (res != null) {
        _back.text = res.primary;
        _options = res.options;
        _partOfSpeech = res.partOfSpeech;
        _phonetic = res.phonetic;
        _dictExamples = res.examples;
        // Авто-определение части речи из словаря (если ещё не выбрана вручную).
        final detected = PosDetect.detect(
          text,
          dictPos: res.partOfSpeech,
          languageCode: widget.languageCode,
        );
        if (detected.isNotEmpty) _pos = detected;
      }
    });
    if (res == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(tr('translate_failed'))));
    }
  }

  void _pickOption(String value) {
    HapticFeedback.selectionClick();
    setState(() => _back.text = value);
  }

  /// Варианты перевода (чипсы) + словарные подсказки (часть речи, транскрипция,
  /// примеры). Появляется плавно после перевода. Тап по чипсу подставляет
  /// значение; тап по примеру заполняет поле примера.
  Widget _variantsSection(ColorScheme scheme) {
    final hasOptions = _options.length > 1;
    final meta = <String>[
      if (_partOfSpeech != null && _partOfSpeech!.isNotEmpty) _partOfSpeech!,
      if (_phonetic != null && _phonetic!.isNotEmpty) _phonetic!,
    ].join('  ·  ');
    final show = hasOptions || meta.isNotEmpty || _dictExamples.isNotEmpty;
    return AnimatedSize(
      duration: const Duration(milliseconds: 260),
      curve: AppTheme.emphasizedDecelerate,
      alignment: Alignment.topCenter,
      child: !show
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (meta.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(left: 4, bottom: 6),
                      child: Text(
                        meta,
                        style: TextStyle(
                          fontFamily: AppTheme.bodyFont,
                          fontStyle: FontStyle.italic,
                          fontSize: 12.5,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  if (hasOptions)
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        for (final opt in _options)
                          ChoiceChip(
                            label: Text(opt),
                            selected: _back.text.trim() == opt,
                            onSelected: (_) => _pickOption(opt),
                            visualDensity: VisualDensity.compact,
                          ),
                      ],
                    ),
                  for (final ex in _dictExamples)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() => _example.text = ex);
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 4),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.format_quote_rounded,
                                  size: 15, color: scheme.onSurfaceVariant),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  ex,
                                  style: TextStyle(
                                    fontFamily: AppTheme.bodyFont,
                                    fontSize: 12.5,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  @override
  void dispose() {
    _front.dispose();
    _back.dispose();
    _example.dispose();
    super.dispose();
  }

  /// Выбор части речи (тег карточки) — чипсы по типам + «не указана».
  Widget _posChooser(ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            tr('part_of_speech'),
            style: TextStyle(
              fontFamily: AppTheme.bodyFont,
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              label: Text(tr('pos_none')),
              selected: _pos.isEmpty,
              visualDensity: VisualDensity.compact,
              onSelected: (_) => setState(() => _pos = ''),
            ),
            for (final code in PosDetect.order)
              ChoiceChip(
                label: Text(tr('pos_deck_$code')),
                selected: _pos == code,
                visualDensity: VisualDensity.compact,
                onSelected: (_) => setState(() => _pos = code),
              ),
          ],
        ),
      ],
    );
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
      pos: _pos,
      // Сохраняем поля источника при редактировании.
      sentence: e?.sentence ?? '',
      sourceUrl: e?.sourceUrl ?? '',
      clipStartMs: e?.clipStartMs,
      clipEndMs: e?.clipEndMs,
    );
    Navigator.pop(context, card);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
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
                  prefixIcon: const Icon(Icons.text_fields_rounded),
                  suffixIcon: _canTranslate
                      ? IconButton(
                          tooltip: tr('translate_action'),
                          icon: _translating
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.translate_rounded),
                          onPressed: _translating ? null : _translate,
                        )
                      : null,
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
              _variantsSection(scheme),
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
              const SizedBox(height: 16),
              _posChooser(scheme),
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
      cards.add(
        WordCard(
          id: 'card_${DateTime.now().microsecondsSinceEpoch}_${i++}',
          deckId: widget.deckId,
          front: front,
          back: back,
        ),
      );
    }
    Navigator.pop(context, cards);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
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
