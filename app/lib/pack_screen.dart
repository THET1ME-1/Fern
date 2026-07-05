import 'package:flutter/material.dart';

import 'deck_screen.dart';
import 'l10n/strings.dart';
import 'models/deck.dart';
import 'models/pack.dart';
import 'models/word_card.dart';
import 'services/deck_repository.dart';
import 'theme/app_theme.dart';
import 'widgets/deck_editor_sheet.dart';
import 'widgets/deck_tiles.dart';
import 'widgets/pack_editor_sheet.dart';
import 'widgets/reveal.dart';
import 'widgets/study_modes.dart';

/// Экран пака: колоды внутри одной «папки». Открывается тапом по плитке пака на
/// главном экране. Вложенности пак-в-пак нет — только колоды.
class PackScreen extends StatefulWidget {
  final Pack pack;
  const PackScreen({super.key, required this.pack});

  @override
  State<PackScreen> createState() => _PackScreenState();
}

class _PackScreenState extends State<PackScreen> {
  final DeckRepository _repo = DeckRepository.instance;

  late Pack _pack = widget.pack;
  List<Deck> _decks = [];
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
    final decks = await _repo.loadDecks();
    final cards = await _repo.loadCards();
    final pack = _repo.packs.where((p) => p.id == widget.pack.id).firstOrNull;
    if (!mounted) return;
    // Пак удалили извне — закрываем экран.
    if (pack == null) {
      Navigator.of(context).maybePop();
      return;
    }
    setState(() {
      _pack = pack;
      _decks = decks.where((d) => d.packId == _pack.id).toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      _cards = cards;
      _loading = false;
    });
  }

  ({int total, int due}) _counts(String deckId) {
    final now = DateTime.now();
    var total = 0, due = 0;
    for (final c in _cards) {
      if (c.deckId != deckId) continue;
      total++;
      if (c.review.isNew || c.isDue(now)) due++;
    }
    return (total: total, due: due);
  }

  int get _totalCards =>
      _decks.fold(0, (s, d) => s + _counts(d.id).total);
  int get _totalDue => _decks.fold(0, (s, d) => s + _counts(d.id).due);

  Future<void> _createDeckInPack() async {
    final deck = await showDeckEditor(
      context,
      languageCode: _pack.languageCode,
      fixedPackId: _pack.id,
    );
    if (deck != null) await _repo.upsertDeck(deck);
  }

  Future<void> _editDeck(Deck deck) async {
    final result = await showDeckEditor(
      context,
      existing: deck,
      languageCode: deck.languageCode,
    );
    if (result != null) await _repo.upsertDeck(result);
  }

  Future<void> _editPack() async {
    final result = await showPackEditor(
      context,
      existing: _pack,
      languageCode: _pack.languageCode,
    );
    if (result != null) await _repo.upsertPack(result);
  }

  Future<void> _deletePack() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_pack.name),
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
    if (ok == true) {
      await _repo.deletePack(_pack.id);
      if (mounted) Navigator.of(context).maybePop();
    }
  }

  Future<void> _deckMenu(Deck deck) async {
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
              leading: const Icon(Icons.edit_rounded),
              title: Text(tr('edit_deck')),
              onTap: () {
                Navigator.pop(ctx);
                _editDeck(deck);
              },
            ),
            ListTile(
              leading: const Icon(Icons.output_rounded),
              title: Text(tr('remove_from_pack')),
              onTap: () {
                Navigator.pop(ctx);
                _repo.setDeckPack(deck.id, null);
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_rounded, color: scheme.error),
              title: Text(tr('delete_deck')),
              onTap: () {
                Navigator.pop(ctx);
                _deleteDeck(deck);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteDeck(Deck deck) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(deck.name),
        content: Text(tr('delete_deck_confirm')),
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
    if (ok == true) await _repo.deleteDeck(deck.id);
  }

  /// Менеджер колод пака: все колоды языка с галочкой «входит в пак». Снятие
  /// галочки ВЫНИМАЕТ колоду из папки (сама колода остаётся), установка —
  /// кладёт/переносит колоду в этот пак. Так можно добавлять, менять и убирать.
  Future<void> _manageDecks() async {
    final scheme = Theme.of(context).colorScheme;
    final all = _repo.decks
        .where((d) => d.languageCode == _pack.languageCode)
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    if (all.isEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(tr('no_free_decks'))));
      return;
    }
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: scheme.surfaceContainer,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final decks = _repo.decks
              .where((d) => d.languageCode == _pack.languageCode)
              .toList()
            ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
          return SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.8,
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
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
                    const SizedBox(height: 14),
                    Text(
                      tr('manage_decks'),
                      style: TextStyle(
                        fontFamily: AppTheme.displayFont,
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      tr('manage_decks_sub'),
                      style: TextStyle(
                        fontFamily: AppTheme.bodyFont,
                        fontSize: 12.5,
                        height: 1.35,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: decks.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (_, i) {
                          final d = decks[i];
                          final inThis = d.packId == _pack.id;
                          final inOther = d.packId != null && !inThis;
                          return Material(
                            color: inThis
                                ? scheme.primaryContainer
                                : scheme.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(16),
                            clipBehavior: Clip.antiAlias,
                            child: CheckboxListTile(
                              value: inThis,
                              controlAffinity:
                                  ListTileControlAffinity.trailing,
                              secondary: CircleAvatar(
                                  backgroundColor: d.color, radius: 14),
                              title: Text(d.name),
                              subtitle: Text(
                                inOther
                                    ? '${trf('cards_n', {'n': _counts(d.id).total})} · ${tr('deck_in_other_pack')}'
                                    : trf('cards_n', {'n': _counts(d.id).total}),
                              ),
                              onChanged: (v) async {
                                await _repo.setDeckPack(
                                    d.id, (v ?? false) ? _pack.id : null);
                                setSheet(() {});
                              },
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(_pack.name),
        actions: [
          IconButton(
            tooltip: tr('manage_decks'),
            icon: const Icon(Icons.playlist_add_check_rounded),
            onPressed: _manageDecks,
          ),
          IconButton(
            tooltip: tr('edit'),
            icon: const Icon(Icons.edit_rounded),
            onPressed: _editPack,
          ),
          IconButton(
            tooltip: tr('delete_pack'),
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: _deletePack,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                Reveal(child: _hero(scheme)),
                if (_totalCards > 0) ...[
                  const SizedBox(height: 20),
                  Reveal(
                    delay: const Duration(milliseconds: 60),
                    child: _sectionTitle(tr('modes_title'), scheme),
                  ),
                  const SizedBox(height: 12),
                  Reveal(
                    delay: const Duration(milliseconds: 90),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: StudyModesGrid(
                        deck: _packDeck,
                        cards: _packCards,
                        reload: () => _repo.cardsForPack(_pack.id),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                Reveal(
                  delay: const Duration(milliseconds: 120),
                  child: _sectionTitle(tr('manage_decks'), scheme),
                ),
                const SizedBox(height: 12),
                _grid(scheme),
              ],
            ),
    );
  }

  /// Синтетическая «колода пака» — чтобы прогнать режимы обучения по всем его
  /// картам сразу (рейтинг обновляет карты по id, независимо от колоды).
  Deck get _packDeck => Deck(
        id: 'pack_${_pack.id}',
        languageCode: _pack.languageCode,
        name: _pack.name,
        colorValue: _pack.colorValue,
        shapeIndex: 0,
        createdAt: _pack.createdAt,
      );

  List<WordCard> get _packCards {
    final ids = _decks.map((d) => d.id).toSet();
    return _cards.where((c) => ids.contains(c.deckId)).toList();
  }

  Widget _sectionTitle(String text, ColorScheme scheme) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Text(
          text,
          style: TextStyle(
            fontFamily: AppTheme.displayFont,
            fontWeight: FontWeight.w700,
            fontSize: 16,
            color: scheme.onSurface,
          ),
        ),
      );

  Widget _hero(ColorScheme scheme) {
    final tint = Color.alphaBlend(
      _pack.color.withValues(alpha: 0.18),
      scheme.surfaceContainerHigh,
    );
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _pack.color.withValues(alpha: 0.5), width: 1.5),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: _pack.color,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(Icons.layers_rounded,
                color: _pack.color.computeLuminance() > 0.5
                    ? Colors.black
                    : Colors.white),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  trf('decks_n', {'n': _decks.length}),
                  style: TextStyle(
                    fontFamily: AppTheme.displayFont,
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${trf('cards_n', {'n': _totalCards})}  ·  ${trf('due_n', {'n': _totalDue})}',
                  style: TextStyle(
                    fontFamily: AppTheme.bodyFont,
                    fontSize: 13,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _grid(ColorScheme scheme) {
    final items = <Widget>[
      for (final d in _decks)
        DeckCoverCard(
          name: d.name,
          color: d.color,
          shapeIndex: d.shapeIndex,
          total: _counts(d.id).total,
          due: _counts(d.id).due,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => DeckScreen(deck: d)),
          ),
          onLongPress: () => _deckMenu(d),
        ),
      AddDashedCard(
        icon: Icons.add_rounded,
        label: tr('create_deck'),
        onTap: _createDeckInPack,
      ),
    ];
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
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
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
