import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../l10n/strings.dart';
import '../services/card_images.dart';

/// Картинка карточки: превью с кнопкой снятия либо кнопка добавления.
/// Файл кладётся сразу при выборе, наружу отдаётся только имя ([onChanged]) —
/// вызывающий экран решает, когда записать его в карточку.
class CardImageField extends StatefulWidget {
  /// Id карточки: имя файла привязано к ней (одна карточка — одна картинка).
  final String cardId;
  final String initial;
  final ValueChanged<String> onChanged;

  const CardImageField({
    super.key,
    required this.cardId,
    required this.initial,
    required this.onChanged,
  });

  @override
  State<CardImageField> createState() => _CardImageFieldState();
}

class _CardImageFieldState extends State<CardImageField> {
  late String _name = widget.initial;
  bool _busy = false;

  Future<void> _choose() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_rounded),
              title: Text(tr('image_from_camera')),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded),
              title: Text(tr('image_from_gallery')),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source != null) await _pick(source);
  }

  Future<void> _pick(ImageSource source) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final picked = await ImagePicker()
          .pickImage(source: source, imageQuality: 85, maxWidth: 1400);
      if (picked == null) return;
      final name = await CardImages.save(widget.cardId, picked.path);
      if (!mounted) return;
      if (name == null) {
        _toast(tr('image_failed'));
        return;
      }
      setState(() => _name = name);
      widget.onChanged(name);
    } catch (_) {
      if (mounted) _toast(tr('image_failed'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove() async {
    await CardImages.deleteFor(widget.cardId);
    if (!mounted) return;
    setState(() => _name = '');
    widget.onChanged('');
  }

  void _toast(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final path = CardImages.resolve(_name);
    if (path == null) {
      return Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: _busy ? null : _choose,
          icon: const Icon(Icons.add_photo_alternate_outlined),
          label: Text(tr('card_image_add')),
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Stack(
        children: [
          Image.file(
            File(path),
            width: double.infinity,
            height: 170,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => Container(
              height: 170,
              color: scheme.surfaceContainerHighest,
              alignment: Alignment.center,
              child: Icon(
                Icons.broken_image_outlined,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          Positioned(
            top: 6,
            right: 6,
            child: IconButton.filledTonal(
              tooltip: tr('card_image_remove'),
              icon: const Icon(Icons.close_rounded, size: 18),
              visualDensity: VisualDensity.compact,
              onPressed: _remove,
            ),
          ),
        ],
      ),
    );
  }
}
