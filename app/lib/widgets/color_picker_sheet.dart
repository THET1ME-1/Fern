import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';

import '../l10n/strings.dart';
import '../theme/app_theme.dart';

/// HEX-строка цвета вида `#RRGGBB` (без альфы).
String colorToHex(Color color) {
  final argb = color.toARGB32();
  return '#${argb.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
}

/// Настоящий колор-пикер в выезжающей снизу панели (M3):
/// HSV-колесо + поле ввода HEX + значения RGB. Возвращает выбранный цвет,
/// [resetTo] (если задан) при «Сбросить», или null при отмене.
Future<Color?> showColorPickerSheet(
  BuildContext context, {
  required Color initial,
  String title = 'Свой цвет',
  Color? resetTo,
}) {
  final scheme = Theme.of(context).colorScheme;
  return showModalBottomSheet<Color>(
    context: context,
    isScrollControlled: true,
    backgroundColor: scheme.surfaceContainer,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (context) =>
        _ColorPickerSheet(initial: initial, title: title, resetTo: resetTo),
  );
}

class _ColorPickerSheet extends StatefulWidget {
  final Color initial;
  final String title;
  final Color? resetTo;

  const _ColorPickerSheet({
    required this.initial,
    required this.title,
    this.resetTo,
  });

  @override
  State<_ColorPickerSheet> createState() => _ColorPickerSheetState();
}

class _ColorPickerSheetState extends State<_ColorPickerSheet> {
  late Color _color = widget.initial;

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
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: _color,
                      shape: BoxShape.circle,
                      border: Border.all(color: scheme.outlineVariant, width: 2),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    widget.title,
                    style: TextStyle(
                      fontFamily: AppTheme.displayFont,
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                      color: scheme.onSurface,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ColorPicker(
                pickerColor: _color,
                onColorChanged: (c) => setState(() => _color = c),
                enableAlpha: false,
                displayThumbColor: true,
                paletteType: PaletteType.hueWheel,
                labelTypes: const [ColorLabelType.rgb, ColorLabelType.hsv],
                hexInputBar: true,
                portraitOnly: true,
                pickerAreaBorderRadius: BorderRadius.circular(16),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  if (widget.resetTo != null)
                    TextButton(
                      onPressed: () =>
                          Navigator.pop(context, widget.resetTo),
                      child: Text(tr('reset')),
                    ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(tr('cancel')),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, _color),
                    child: Text(tr('apply')),
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
