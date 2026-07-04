import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/strings.dart';
import '../models/deck.dart';
import '../models/pack.dart';
import '../services/deck_repository.dart';
import '../theme/app_theme.dart';
import 'color_picker_sheet.dart';
import 'deck_shapes.dart';
import 'deck_tiles.dart';
import 'pack_editor_sheet.dart';

/// Редактор колоды (создание/правка): название, цвет, форма обложки,
/// направление и — если разрешено — пак, в который вложена колода.
///
/// [fixedPackId] — жёстко задать пак (напр., создание колоды внутри пака);
/// тогда выбор пака скрыт.
Future<Deck?> showDeckEditor(
  BuildContext context, {
  Deck? existing,
  required String languageCode,
  String? fixedPackId,
  bool allowPackChange = true,
}) {
  return showModalBottomSheet<Deck>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => _DeckEditorSheet(
      existing: existing,
      languageCode: languageCode,
      fixedPackId: fixedPackId,
      allowPackChange: allowPackChange && fixedPackId == null,
    ),
  );
}

class _DeckEditorSheet extends StatefulWidget {
  final Deck? existing;
  final String languageCode;
  final String? fixedPackId;
  final bool allowPackChange;
  const _DeckEditorSheet({
    this.existing,
    required this.languageCode,
    this.fixedPackId,
    required this.allowPackChange,
  });

  @override
  State<_DeckEditorSheet> createState() => _DeckEditorSheetState();
}

class _DeckEditorSheetState extends State<_DeckEditorSheet> {
  late final TextEditingController _name;
  late int _color;
  late int _shape;
  late int _direction;
  late String? _packId;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _color = e?.colorValue ?? kDeckPalette.first.toARGB32();
    _shape = e?.shapeIndex ?? 0;
    _direction = e?.directionIndex ?? 0;
    _packId = widget.fixedPackId ?? e?.packId;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  List<Pack> get _packs => DeckRepository.instance.packs
      .where((p) => p.languageCode == widget.languageCode)
      .toList();

  Future<void> _pickCustomColor() async {
    final picked = await showColorPickerSheet(
      context,
      initial: Color(_color),
      title: tr('deck_color'),
    );
    if (picked != null) setState(() => _color = picked.toARGB32());
  }

  Future<void> _createPack() async {
    final pack = await showPackEditor(
      context,
      languageCode: widget.languageCode,
    );
    if (pack == null) return;
    await DeckRepository.instance.upsertPack(pack);
    if (mounted) setState(() => _packId = pack.id);
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
      directionIndex: _direction,
      createdAt: e?.createdAt ?? DateTime.now().millisecondsSinceEpoch,
      packId: _packId,
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
                  for (final c in kDeckPalette) _swatch(c, scheme),
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
              const SizedBox(height: 20),
              _sectionLabel(scheme, tr('deck_direction')),
              const SizedBox(height: 8),
              _directionSelector(scheme),
              if (widget.allowPackChange) ...[
                const SizedBox(height: 20),
                _sectionLabel(scheme, tr('deck_pack')),
                const SizedBox(height: 8),
                _packSelector(scheme),
              ],
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

  Widget _packSelector(ColorScheme scheme) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ChoiceChip(
          label: Text(tr('pack_none')),
          selected: _packId == null,
          onSelected: (_) => setState(() => _packId = null),
        ),
        for (final p in _packs)
          ChoiceChip(
            avatar: CircleAvatar(backgroundColor: p.color, radius: 8),
            label: Text(p.name),
            selected: _packId == p.id,
            onSelected: (_) => setState(() => _packId = p.id),
          ),
        ActionChip(
          avatar: Icon(Icons.add_rounded, size: 18, color: scheme.primary),
          label: Text(tr('pack_new')),
          onPressed: _createPack,
        ),
      ],
    );
  }

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
          border: selected ? Border.all(color: scheme.onSurface, width: 3) : null,
        ),
        child: selected
            ? const Icon(Icons.check_rounded, color: Colors.white, size: 22)
            : null,
      ),
    );
  }

  Widget _customSwatch(ColorScheme scheme) {
    final isCustom = !kDeckPalette.any((c) => c.toARGB32() == _color);
    return GestureDetector(
      onTap: _pickCustomColor,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          gradient: const SweepGradient(
            colors: [
              Colors.red,
              Colors.yellow,
              Colors.green,
              Colors.cyan,
              Colors.blue,
              Colors.purple,
              Colors.red,
            ],
          ),
          shape: BoxShape.circle,
          border:
              isCustom ? Border.all(color: scheme.onSurface, width: 3) : null,
        ),
        child: const Icon(Icons.colorize_rounded, color: Colors.white, size: 20),
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

  Widget _directionSelector(ColorScheme scheme) {
    final opts = <(int, IconData, String)>[
      (0, Icons.east_rounded, tr('dir_forward')),
      (2, Icons.sync_alt_rounded, tr('dir_both')),
      (1, Icons.west_rounded, tr('dir_reverse')),
    ];
    return Column(
      children: [
        for (var i = 0; i < opts.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          _directionOption(opts[i].$1, opts[i].$2, opts[i].$3, scheme),
        ],
      ],
    );
  }

  Widget _directionOption(
      int value, IconData icon, String label, ColorScheme scheme) {
    final selected = _direction == value;
    return Material(
      color: selected ? scheme.primaryContainer : scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => setState(() => _direction = value),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(icon,
                  size: 20,
                  color: selected
                      ? scheme.onPrimaryContainer
                      : scheme.onSurfaceVariant),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontFamily: AppTheme.bodyFont,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    fontSize: 14,
                    color: selected
                        ? scheme.onPrimaryContainer
                        : scheme.onSurface,
                  ),
                ),
              ),
              if (selected)
                Icon(Icons.check_rounded,
                    size: 18, color: scheme.onPrimaryContainer),
            ],
          ),
        ),
      ),
    );
  }
}
