import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/strings.dart';
import '../models/pack.dart';
import '../theme/app_theme.dart';
import 'color_picker_sheet.dart';

/// Пресет-цвета паков (те же, что у колод).
const List<Color> kPackPalette = [
  Color(0xFF3F6FB0),
  Color(0xFF2E7D5B),
  Color(0xFFB5622E),
  Color(0xFF8A4FBF),
  Color(0xFFB03F6F),
  Color(0xFF4FA0A8),
  Color(0xFF7A8B2E),
  Color(0xFFB0873F),
];

/// Показывает редактор пака (создание/правка). Возвращает [Pack] или null.
Future<Pack?> showPackEditor(
  BuildContext context, {
  Pack? existing,
  required String languageCode,
}) {
  return showModalBottomSheet<Pack>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => _PackEditorSheet(existing: existing, languageCode: languageCode),
  );
}

class _PackEditorSheet extends StatefulWidget {
  final Pack? existing;
  final String languageCode;
  const _PackEditorSheet({this.existing, required this.languageCode});

  @override
  State<_PackEditorSheet> createState() => _PackEditorSheetState();
}

class _PackEditorSheetState extends State<_PackEditorSheet> {
  late final TextEditingController _name;
  late int _color;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.existing?.name ?? '');
    _color = widget.existing?.colorValue ?? kPackPalette.first.toARGB32();
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
      title: tr('pack_color'),
    );
    if (picked != null) setState(() => _color = picked.toARGB32());
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    HapticFeedback.selectionClick();
    final e = widget.existing;
    final pack = Pack(
      id: e?.id ?? 'pack_${DateTime.now().millisecondsSinceEpoch}',
      languageCode: e?.languageCode ?? widget.languageCode,
      name: name,
      colorValue: _color,
      createdAt: e?.createdAt ?? DateTime.now().millisecondsSinceEpoch,
    );
    Navigator.pop(context, pack);
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
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: Color(_color),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(Icons.layers_rounded,
                    color: Colors.white, size: 34),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _name,
                autofocus: widget.existing == null,
                textCapitalization: TextCapitalization.sentences,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: tr('pack_name'),
                  prefixIcon: const Icon(Icons.layers_rounded),
                ),
              ),
              const SizedBox(height: 20),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  tr('pack_color'),
                  style: TextStyle(
                    fontFamily: AppTheme.bodyFont,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final c in kPackPalette) _swatch(c, scheme),
                  _customSwatch(scheme),
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
    final isCustom = !kPackPalette.any((c) => c.toARGB32() == _color);
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
}
