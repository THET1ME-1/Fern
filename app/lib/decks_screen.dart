import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'deck_screen.dart';
import 'l10n/strings.dart';
import 'language_picker_sheet.dart';
import 'models/deck.dart';
import 'models/language.dart';
import 'models/word_card.dart';
import 'services/deck_repository.dart';
import 'theme/app_theme.dart';
import 'widgets/color_picker_sheet.dart';
import 'widgets/deck_shapes.dart';
import 'widgets/reveal.dart';

/// Пресет-цвета обложек колод.
const List<Color> _deckPalette = [
  Color(0xFF2E7D5B),
  Color(0xFF3F6FB0),
  Color(0xFFB5622E),
  Color(0xFF8A4FBF),
  Color(0xFFB03F6F),
  Color(0xFF4FA0A8),
  Color(0xFF7A8B2E),
  Color(0xFFB0873F),
];

/// Главный экран: сверху баннер выбора изучаемого языка, ниже — сетка колод
/// (паков слов) этого языка. ДНК ScoreMaster (меню выбора игроков).
class DecksScreen extends StatefulWidget {
  const DecksScreen({super.key});

  @override
  State<DecksScreen> createState() => _DecksScreenState();
}

class _DecksScreenState extends State<DecksScreen> {
  final DeckRepository _repo = DeckRepository.instance;

  List<Deck> _decks = [];
  List<WordCard> _cards = [];
  String _lang = 'en';
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
    var lang = await _repo.selectedLanguageCode();
    lang ??= decks.isNotEmpty ? decks.first.languageCode : 'en';
    if (!mounted) return;
    setState(() {
      _decks = decks;
      _cards = cards;
      _lang = lang!;
      _loading = false;
    });
  }

  List<Deck> get _visibleDecks =>
      _decks.where((d) => d.languageCode == _lang).toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

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
    final result = await showModalBottomSheet<Deck>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => _DeckEditorSheet(existing: existing, languageCode: _lang),
    );
    if (result == null) return;
    await _repo.upsertDeck(result);
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
                _createOrEditDeck(deck);
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final decks = _visibleDecks;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Fern'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _languageBanner(scheme),
                Expanded(
                  child: decks.isEmpty
                      ? _emptyState(scheme)
                      : _grid(decks, scheme),
                ),
              ],
            ),
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
                Text(lang?.emoji ?? '🌐',
                    style: const TextStyle(fontSize: 26)),
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
                          color: scheme.onSecondaryContainer
                              .withValues(alpha: 0.8),
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
                Icon(Icons.unfold_more_rounded,
                    color: scheme.onSecondaryContainer),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _grid(List<Deck> decks, ColorScheme scheme) {
    final items = <Widget>[
      for (final d in decks) _deckCard(d, scheme),
      _addCard(scheme),
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
      itemBuilder: (_, i) =>
          Reveal(delay: Duration(milliseconds: 45 * i), child: items[i]),
    );
  }

  Widget _deckCard(Deck deck, ColorScheme scheme) {
    final c = _counts(deck.id);
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => DeckScreen(deck: deck)),
      ),
      onLongPress: () => _deckMenu(deck),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(28),
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ShapedCover(
                    label: deck.name,
                    color: deck.color,
                    imagePath: null,
                    size: 84,
                    shape: deckShape(deck.shapeIndex),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    deck.name,
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: AppTheme.displayFont,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: scheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    trf('cards_n', {'n': c.total}),
                    style: TextStyle(
                      fontFamily: AppTheme.bodyFont,
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (c.due > 0)
              Positioned(
                top: -2,
                right: -2,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    '${c.due}',
                    style: TextStyle(
                      fontFamily: AppTheme.displayFont,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      color: scheme.onPrimary,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _addCard(ColorScheme scheme) {
    return GestureDetector(
      onTap: () => _createOrEditDeck(),
      child: CustomPaint(
        painter: _DashedBorderPainter(color: scheme.outline),
        child: Container(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 84,
                  height: 84,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.add_rounded,
                      size: 40, color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 12),
                Text(
                  tr('create_deck'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: AppTheme.bodyFont,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _emptyState(ColorScheme scheme) {
    return Center(
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
          ],
        ),
      ),
    );
  }
}

/// Пунктирная рамка для карточки «+».
class _DashedBorderPainter extends CustomPainter {
  final Color color;
  _DashedBorderPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(28),
    );
    final path = Path()..addRRect(rrect);
    const dash = 7.0;
    const gap = 5.0;
    for (final metric in path.computeMetrics()) {
      var dist = 0.0;
      while (dist < metric.length) {
        canvas.drawPath(
          metric.extractPath(dist, dist + dash),
          paint,
        );
        dist += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter old) => old.color != color;
}

/// Редактор колоды (создание/правка): название, цвет и форма обложки.
class _DeckEditorSheet extends StatefulWidget {
  final Deck? existing;
  final String languageCode;
  const _DeckEditorSheet({this.existing, required this.languageCode});

  @override
  State<_DeckEditorSheet> createState() => _DeckEditorSheetState();
}

class _DeckEditorSheetState extends State<_DeckEditorSheet> {
  late final TextEditingController _name;
  late int _color;
  late int _shape;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _color = e?.colorValue ?? _deckPalette.first.toARGB32();
    _shape = e?.shapeIndex ?? 0;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _pickCustomColor() async {
    final picked = await showColorPickerSheet(
      context,
      initial: Color(_color),
      title: tr('deck_color'),
    );
    if (picked != null) setState(() => _color = picked.toARGB32());
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    HapticFeedback.selectionClick();
    final e = widget.existing;
    final deck = Deck(
      id: e?.id ?? 'deck_${DateTime.now().millisecondsSinceEpoch}',
      languageCode: e?.languageCode ?? widget.languageCode,
      name: name,
      colorValue: _color,
      shapeIndex: _shape,
      createdAt: e?.createdAt ?? DateTime.now().millisecondsSinceEpoch,
    );
    Navigator.pop(context, deck);
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
              const SizedBox(height: 16),
              // Живой предпросмотр обложки.
              ShapedCover(
                label: _name.text.isEmpty ? '?' : _name.text,
                color: Color(_color),
                imagePath: null,
                size: 80,
                shape: deckShape(_shape),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _name,
                autofocus: widget.existing == null,
                textCapitalization: TextCapitalization.sentences,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: tr('deck_name'),
                  prefixIcon: const Icon(Icons.style_rounded),
                ),
              ),
              const SizedBox(height: 20),
              _sectionLabel(scheme, tr('deck_color')),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final c in _deckPalette) _swatch(c, scheme),
                  _customSwatch(scheme),
                ],
              ),
              const SizedBox(height: 20),
              _sectionLabel(scheme, tr('deck_shape')),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (var i = 0; i < kDeckShapes.length; i++)
                    _shapeChoice(i, scheme),
                ],
              ),
              const SizedBox(height: 24),
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

  Widget _sectionLabel(ColorScheme scheme, String text) => Align(
        alignment: Alignment.centerLeft,
        child: Text(
          text,
          style: TextStyle(
            fontFamily: AppTheme.bodyFont,
            fontWeight: FontWeight.w600,
            fontSize: 14,
            color: scheme.onSurfaceVariant,
          ),
        ),
      );

  Widget _swatch(Color c, ColorScheme scheme) {
    final selected = c.toARGB32() == _color;
    return GestureDetector(
      onTap: () => setState(() => _color = c.toARGB32()),
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: c,
          shape: BoxShape.circle,
          border: selected
              ? Border.all(color: scheme.onSurface, width: 3)
              : null,
        ),
        child: selected
            ? const Icon(Icons.check_rounded, color: Colors.white, size: 22)
            : null,
      ),
    );
  }

  Widget _customSwatch(ColorScheme scheme) {
    final isCustom = !_deckPalette.any((c) => c.toARGB32() == _color);
    return GestureDetector(
      onTap: _pickCustomColor,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          gradient: const SweepGradient(colors: [
            Colors.red,
            Colors.yellow,
            Colors.green,
            Colors.cyan,
            Colors.blue,
            Colors.purple,
            Colors.red,
          ]),
          shape: BoxShape.circle,
          border: isCustom
              ? Border.all(color: scheme.onSurface, width: 3)
              : null,
        ),
        child: const Icon(Icons.colorize_rounded,
            color: Colors.white, size: 20),
      ),
    );
  }

  Widget _shapeChoice(int i, ColorScheme scheme) {
    final selected = i == _shape;
    return GestureDetector(
      onTap: () => setState(() => _shape = i),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: selected
              ? Border.all(color: scheme.primary, width: 2)
              : Border.all(color: Colors.transparent, width: 2),
        ),
        child: Container(
          width: 34,
          height: 34,
          decoration: ShapeDecoration(
            color: selected ? Color(_color) : scheme.surfaceContainerHighest,
            shape: deckShape(i),
          ),
        ),
      ),
    );
  }
}
