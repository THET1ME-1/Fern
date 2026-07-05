import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'deck_screen.dart';
import 'l10n/strings.dart';
import 'language_picker_sheet.dart';
import 'models/deck.dart';
import 'models/language.dart';
import 'models/pack.dart';
import 'models/review_log.dart';
import 'models/word_card.dart';
import 'pack_screen.dart';
import 'services/deck_repository.dart';
import 'services/starter_decks.dart';
import 'theme/app_theme.dart';
import 'video/video_import_screen.dart';
import 'widgets/count_up_number.dart';
import 'widgets/deck_editor_sheet.dart';
import 'widgets/deck_shapes.dart';
import 'widgets/deck_tiles.dart';
import 'widgets/goal_ring.dart';
import 'widgets/pack_editor_sheet.dart';
import 'widgets/reveal.dart';

/// Главный экран: сверху баннер выбора изучаемого языка, ниже — сетка паков и
/// колод этого языка. ДНК ScoreMaster (меню выбора игроков).
class DecksScreen extends StatefulWidget {
  const DecksScreen({super.key});

  @override
  State<DecksScreen> createState() => _DecksScreenState();
}

class _DecksScreenState extends State<DecksScreen> {
  final DeckRepository _repo = DeckRepository.instance;

  List<Deck> _decks = [];
  List<Pack> _packs = [];
  List<WordCard> _cards = [];
  ReviewLog _log = ReviewLog.empty();
  int _goal = 20;
  String _lang = 'en';
  bool _loading = true;
  bool _hasStarter = false;
  bool _showVideoBanner = true;

  // Множественный выбор колод (по удержанию) для удаления.
  bool _selecting = false;
  final Set<String> _selectedDecks = {};

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
    final decks = await _repo.loadDecks();
    final packs = await _repo.loadPacks();
    final cards = await _repo.loadCards();
    final log = await _repo.reviewLog();
    final goal = await _repo.dailyGoal();
    final showBanner = await _repo.showVideoBanner();
    var lang = await _repo.selectedLanguageCode();
    lang ??= decks.isNotEmpty ? decks.first.languageCode : 'en';
    final hasStarter = await StarterDecks.hasPacksFor(lang);
    if (!mounted) return;
    setState(() {
      _decks = decks;
      _packs = packs;
      _cards = cards;
      _log = log;
      _goal = goal;
      _lang = lang!;
      _hasStarter = hasStarter;
      _showVideoBanner = showBanner;
      _loading = false;
    });
  }

  /// Открывает лист с готовыми колодами для текущего языка.
  Future<void> _openStarter() async {
    final packs = await StarterDecks.forLanguage(_lang);
    if (!mounted) return;
    final existingNames = _decks
        .where((d) => d.languageCode == _lang)
        .map((d) => d.name)
        .toSet();
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) =>
          _StarterDecksSheet(packs: packs, existingNames: existingNames),
    );
  }

  /// Сколько карточек ждут повтора прямо сейчас во всех колодах.
  int get _dueTotalAll {
    final now = DateTime.now();
    var due = 0;
    for (final c in _cards) {
      if (c.review.isNew || c.isDue(now)) due++;
    }
    return due;
  }

  /// Верхнеуровневые колоды текущего языка (не вложенные в пак).
  List<Deck> get _visibleDecks => _decks
      .where((d) => d.languageCode == _lang && d.packId == null)
      .toList()
    ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  /// Паки текущего языка.
  List<Pack> get _visiblePacks =>
      _packs.where((p) => p.languageCode == _lang).toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  List<Deck> _decksInPack(String packId) =>
      _decks.where((d) => d.packId == packId).toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  ({int total, int due}) _packCounts(String packId) {
    var total = 0, due = 0;
    for (final d in _decksInPack(packId)) {
      final c = _counts(d.id);
      total += c.total;
      due += c.due;
    }
    return (total: total, due: due);
  }

  ({int total, int due, int fresh}) _counts(String deckId) {
    final now = DateTime.now();
    var total = 0, due = 0, fresh = 0;
    for (final c in _cards) {
      if (c.deckId != deckId) continue;
      total++;
      if (c.review.isNew) {
        fresh++;
        due++;
      } else if (c.isDue(now)) {
        due++;
      }
    }
    return (total: total, due: due, fresh: fresh);
  }

  Future<void> _pickLanguage() async {
    final code = await showLanguagePicker(context, _lang);
    if (code == null) return;
    await _repo.setSelectedLanguageCode(code);
  }

  Future<void> _createOrEditDeck([Deck? existing]) async {
    final result = await showDeckEditor(
      context,
      existing: existing,
      languageCode: _lang,
    );
    if (result == null) return;
    await _repo.upsertDeck(result);
  }

  Future<void> _createPack() async {
    final pack = await showPackEditor(context, languageCode: _lang);
    if (pack == null) return;
    await _repo.upsertPack(pack);
  }

  /// Меню плитки «+»: создать колоду или пак.
  Future<void> _addChooser() async {
    final scheme = Theme.of(context).colorScheme;
    await showModalBottomSheet(
      context: context,
      backgroundColor: scheme.surfaceContainer,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            ListTile(
              leading: Icon(Icons.style_rounded, color: scheme.primary),
              title: Text(tr('create_deck')),
              subtitle: Text(tr('create_deck_sub')),
              onTap: () {
                Navigator.pop(ctx);
                _createOrEditDeck();
              },
            ),
            ListTile(
              leading: Icon(Icons.layers_rounded, color: scheme.tertiary),
              title: Text(tr('create_pack')),
              subtitle: Text(tr('create_pack_sub')),
              onTap: () {
                Navigator.pop(ctx);
                _createPack();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final decks = _visibleDecks;
    final packs = _visiblePacks;

    return PopScope(
      canPop: !_selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _selecting) _exitSelection();
      },
      child: Scaffold(
        appBar: _selecting ? _selectionBar(scheme) : _normalBar(scheme),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  // Дневная сводка / баннеры прячем в режиме выбора.
                  if (!_selecting) ...[
                    if (_cards.isNotEmpty) Reveal(child: _todayHero(scheme)),
                    _languageBanner(scheme),
                    if (_showVideoBanner)
                      Reveal(child: _videoBanner(scheme)),
                  ],
                  Expanded(
                    child: decks.isEmpty && packs.isEmpty
                        ? _emptyState(scheme)
                        : _grid(packs, decks, scheme),
                  ),
                ],
              ),
      ),
    );
  }

  AppBar _normalBar(ColorScheme scheme) => AppBar(
        title: const Text('Fern'),
        actions: [
          if (_hasStarter)
            IconButton(
              tooltip: tr('starter_decks'),
              icon: const Icon(Icons.auto_stories_rounded),
              onPressed: _openStarter,
            ),
        ],
      );

  AppBar _selectionBar(ColorScheme scheme) => AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: _exitSelection,
        ),
        title: Text(trf('n_selected', {'n': _selectedDecks.length})),
        actions: [
          IconButton(
            tooltip: tr('select_all'),
            icon: const Icon(Icons.select_all_rounded),
            onPressed: _selectAllDecks,
          ),
          IconButton(
            tooltip: tr('delete'),
            icon: const Icon(Icons.delete_rounded),
            onPressed:
                _selectedDecks.isEmpty ? null : _deleteSelectedDecks,
          ),
        ],
      );

  void _enterSelection(String deckId) {
    HapticFeedback.mediumImpact();
    setState(() {
      _selecting = true;
      _selectedDecks.add(deckId);
    });
  }

  void _toggleDeck(String deckId) {
    setState(() {
      if (!_selectedDecks.remove(deckId)) _selectedDecks.add(deckId);
    });
  }

  void _exitSelection() {
    setState(() {
      _selecting = false;
      _selectedDecks.clear();
    });
  }

  void _selectAllDecks() {
    setState(() => _selectedDecks.addAll(_visibleDecks.map((d) => d.id)));
  }

  Future<void> _deleteSelectedDecks() async {
    final n = _selectedDecks.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(trf('delete_n_decks', {'n': n})),
        content: Text(tr('delete_n_decks_confirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.errorContainer,
              foregroundColor: Theme.of(ctx).colorScheme.onErrorContainer,
            ),
            child: Text(tr('delete')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    for (final id in _selectedDecks.toList()) {
      await _repo.deleteDeck(id);
    }
    _exitSelection();
  }

  void _openVideo() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const VideoImportScreen()),
    );
  }

  /// Заметный баннер «Разобрать видео» — вход в разбор субтитров.
  Widget _videoBanner(ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Material(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(22),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _openVideo,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: scheme.onPrimaryContainer.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.subtitles_rounded,
                      color: scheme.onPrimaryContainer),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tr('video_banner_title'),
                        style: TextStyle(
                          fontFamily: AppTheme.displayFont,
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          color: scheme.onPrimaryContainer,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        tr('video_banner_sub'),
                        style: TextStyle(
                          fontFamily: AppTheme.bodyFont,
                          fontSize: 12.5,
                          color: scheme.onPrimaryContainer.withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded,
                    color: scheme.onPrimaryContainer),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Дневная сводка: кольцо цели (повторы сегодня), серия и «к повтору».
  Widget _todayHero(ColorScheme scheme) {
    final now = DateTime.now();
    final reviewsToday = _log.statOn(now).reviews;
    final streak = _log.streak(now);
    final goal = _goal <= 0 ? 20 : _goal;
    final reached = reviewsToday >= goal;
    final due = _dueTotalAll;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Row(
        children: [
          GoalRing(
            progress: reviewsToday / goal,
            size: 76,
            strokeWidth: 9,
            color: scheme.primary,
            trackColor: scheme.surfaceContainerHighest,
            child: reached
                ? Icon(Icons.check_rounded, color: scheme.primary, size: 34)
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CountUpNumber(
                        value: reviewsToday,
                        style: TextStyle(
                          fontFamily: AppTheme.displayFont,
                          fontWeight: FontWeight.w800,
                          fontSize: 24,
                          height: 1,
                          color: scheme.onSurface,
                        ),
                      ),
                      Text(
                        trf('of_goal', {'n': goal}),
                        style: TextStyle(
                          fontFamily: AppTheme.bodyFont,
                          fontSize: 10,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  reached ? tr('goal_done') : tr('today_title'),
                  style: TextStyle(
                    fontFamily: AppTheme.displayFont,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: reached ? scheme.primary : scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 10),
                _streakLine(scheme, streak),
                const SizedBox(height: 6),
                _dueLine(scheme, due),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _streakLine(ColorScheme scheme, int streak) {
    final active = streak > 0;
    final flame = active ? const Color(0xFFFF8A34) : scheme.onSurfaceVariant;
    return Row(
      children: [
        Icon(Icons.local_fire_department_rounded, size: 20, color: flame),
        const SizedBox(width: 8),
        if (active) ...[
          CountUpNumber(
            value: streak,
            style: TextStyle(
              fontFamily: AppTheme.displayFont,
              fontWeight: FontWeight.w800,
              fontSize: 17,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            tr('streak_suffix'),
            style: TextStyle(
              fontFamily: AppTheme.bodyFont,
              fontSize: 13,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ] else
          Text(
            tr('start_streak'),
            style: TextStyle(
              fontFamily: AppTheme.bodyFont,
              fontSize: 13,
              color: scheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }

  Widget _dueLine(ColorScheme scheme, int due) {
    return Row(
      children: [
        Icon(
          Icons.notifications_active_rounded,
          size: 20,
          color: due > 0 ? scheme.primary : scheme.onSurfaceVariant,
        ),
        const SizedBox(width: 8),
        Text(
          due > 0 ? '$due ' : '— ',
          style: TextStyle(
            fontFamily: AppTheme.displayFont,
            fontWeight: FontWeight.w800,
            fontSize: 17,
            color: due > 0 ? scheme.primary : scheme.onSurfaceVariant,
          ),
        ),
        Text(
          tr('stat_due').toLowerCase(),
          style: TextStyle(
            fontFamily: AppTheme.bodyFont,
            fontSize: 13,
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _languageBanner(ColorScheme scheme) {
    final lang = languageByCode(_lang);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Material(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _pickLanguage,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Text(lang?.emoji ?? '🌐', style: const TextStyle(fontSize: 26)),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tr('studying'),
                        style: TextStyle(
                          fontFamily: AppTheme.bodyFont,
                          fontSize: 12,
                          color: scheme.onSecondaryContainer.withValues(
                            alpha: 0.8,
                          ),
                        ),
                      ),
                      Text(
                        lang?.name ?? _lang,
                        style: TextStyle(
                          fontFamily: AppTheme.displayFont,
                          fontWeight: FontWeight.w700,
                          fontSize: 18,
                          color: scheme.onSecondaryContainer,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.unfold_more_rounded,
                  color: scheme.onSecondaryContainer,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _grid(List<Pack> packs, List<Deck> decks, ColorScheme scheme) {
    // Паки идут первыми (визуально отдельная «полка»), затем колоды, затем «+».
    final items = <Widget>[
      for (final p in packs) _packCard(p),
      for (final d in decks) _deckCard(d),
      if (!_selecting)
        AddDashedCard(
          icon: Icons.add_rounded,
          label: tr('add'),
          onTap: _addChooser,
        ),
    ];
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.82,
      ),
      itemCount: items.length,
      itemBuilder: (_, i) => Reveal(
        delay: Duration(milliseconds: 45 * i),
        child: items[i],
      ),
    );
  }

  Widget _packCard(Pack pack) {
    final c = _packCounts(pack.id);
    final deckColors = [for (final d in _decksInPack(pack.id)) d.color];
    return PackCoverCard(
      name: pack.name,
      color: pack.color,
      deckColors: deckColors,
      deckCount: _decksInPack(pack.id).length,
      due: c.due,
      onTap: _selecting
          ? () {} // в режиме выбора паки не трогаем (выбираем только колоды)
          : () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => PackScreen(pack: pack)),
              ),
      onLongPress: _selecting ? null : () => _packMenu(pack),
    );
  }

  Future<void> _packMenu(Pack pack) async {
    final scheme = Theme.of(context).colorScheme;
    await showModalBottomSheet(
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
            ListTile(
              leading: const Icon(Icons.open_in_full_rounded),
              title: Text(tr('open_pack')),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => PackScreen(pack: pack)),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit_rounded),
              title: Text(tr('edit_pack')),
              onTap: () async {
                Navigator.pop(ctx);
                final res =
                    await showPackEditor(context, existing: pack, languageCode: _lang);
                if (res != null) await _repo.upsertPack(res);
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_rounded, color: scheme.error),
              title: Text(tr('delete_pack')),
              subtitle: Text(tr('delete_pack_keeps_decks')),
              onTap: () {
                Navigator.pop(ctx);
                _deletePack(pack);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _deletePack(Pack pack) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(pack.name),
        content: Text(tr('delete_pack_confirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.errorContainer,
              foregroundColor: Theme.of(ctx).colorScheme.onErrorContainer,
            ),
            child: Text(tr('delete')),
          ),
        ],
      ),
    );
    if (ok == true) await _repo.deletePack(pack.id);
  }

  Widget _deckCard(Deck deck) {
    final c = _counts(deck.id);
    return DeckCoverCard(
      name: deck.name,
      color: deck.color,
      shapeIndex: deck.shapeIndex,
      total: c.total,
      due: c.due,
      selectable: _selecting,
      selected: _selectedDecks.contains(deck.id),
      onTap: () => _selecting
          ? _toggleDeck(deck.id)
          : Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => DeckScreen(deck: deck)),
            ),
      onLongPress: _selecting ? null : () => _enterSelection(deck.id),
    );
  }

  Widget _emptyState(ColorScheme scheme) {
    // Скроллируемый центр: на низких экранах не переполняется, на обычных
    // остаётся по центру.
    return LayoutBuilder(
      builder: (_, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.style_rounded, size: 72, color: scheme.primary),
                  const SizedBox(height: 20),
                  Text(
                    tr('no_decks_title'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: AppTheme.displayFont,
                      fontWeight: FontWeight.w700,
                      fontSize: 22,
                      color: scheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    tr('no_decks_sub'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: AppTheme.bodyFont,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: () => _createOrEditDeck(),
                    icon: const Icon(Icons.add_rounded),
                    label: Text(tr('create_deck')),
                  ),
                  if (_hasStarter) ...[
                    const SizedBox(height: 12),
                    FilledButton.tonalIcon(
                      onPressed: _openStarter,
                      icon: const Icon(Icons.auto_stories_rounded),
                      label: Text(tr('starter_decks')),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Лист с готовыми колодами (стартерами) для выбранного языка.
class _StarterDecksSheet extends StatefulWidget {
  final List<StarterPack> packs;
  final Set<String> existingNames;
  const _StarterDecksSheet({required this.packs, required this.existingNames});

  @override
  State<_StarterDecksSheet> createState() => _StarterDecksSheetState();
}

class _StarterDecksSheetState extends State<_StarterDecksSheet> {
  late final Set<String> _added = {...widget.existingNames};
  final Set<String> _busy = {};

  Future<void> _add(StarterPack pack) async {
    if (_added.contains(pack.name) || _busy.contains(pack.name)) return;
    setState(() => _busy.add(pack.name));
    await StarterDecks.add(pack);
    if (!mounted) return;
    setState(() {
      _busy.remove(pack.name);
      _added.add(pack.name);
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(tr('starter_added'))));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: scheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              tr('starter_decks'),
              style: TextStyle(
                fontFamily: AppTheme.displayFont,
                fontWeight: FontWeight.w700,
                fontSize: 20,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              tr('starter_decks_sub'),
              style: TextStyle(
                fontFamily: AppTheme.bodyFont,
                fontSize: 13,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            if (widget.packs.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 28),
                child: Center(
                  child: Text(
                    tr('starter_none'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: AppTheme.bodyFont,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: widget.packs.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => _packRow(widget.packs[i], i, scheme),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _packRow(StarterPack pack, int i, ColorScheme scheme) {
    final added = _added.contains(pack.name);
    final busy = _busy.contains(pack.name);
    final color = kDeckPalette[i % kDeckPalette.length];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          ShapedCover(
            label: pack.name,
            color: color,
            imagePath: null,
            size: 48,
            shape: deckShape(pack.shapeIndex),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  pack.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: AppTheme.bodyFont,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  trf('words_n', {'n': pack.wordCount}),
                  style: TextStyle(
                    fontFamily: AppTheme.bodyFont,
                    fontSize: 12.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (added)
            Row(
              children: [
                Icon(
                  Icons.check_circle_rounded,
                  size: 18,
                  color: scheme.primary,
                ),
                const SizedBox(width: 4),
                Text(
                  tr('added_label'),
                  style: TextStyle(
                    fontFamily: AppTheme.bodyFont,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: scheme.primary,
                  ),
                ),
              ],
            )
          else
            FilledButton.tonal(
              onPressed: busy ? null : () => _add(pack),
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 40),
                padding: const EdgeInsets.symmetric(horizontal: 18),
              ),
              child: busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(tr('add')),
            ),
        ],
      ),
    );
  }
}
