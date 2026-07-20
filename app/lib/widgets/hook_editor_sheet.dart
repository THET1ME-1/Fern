import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../models/word_card.dart';
import '../services/deck_repository.dart';
import '../theme/app_theme.dart';
import 'card_image_field.dart';

/// Быстрый лист «придумать крючок»: только мнемоника и картинка, без остальных
/// полей карточки. Открывается оттуда, где видно, что слово не даётся.
/// Возвращает true, если карточку сохранили.
Future<bool> showHookEditor(BuildContext context, WordCard card) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _HookEditorSheet(card: card),
  );
  return saved ?? false;
}

class _HookEditorSheet extends StatefulWidget {
  final WordCard card;
  const _HookEditorSheet({required this.card});

  @override
  State<_HookEditorSheet> createState() => _HookEditorSheetState();
}

class _HookEditorSheetState extends State<_HookEditorSheet> {
  late final TextEditingController _hook =
      TextEditingController(text: widget.card.mnemonic);
  late String _image = widget.card.image;

  @override
  void dispose() {
    _hook.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    widget.card.mnemonic = _hook.text.trim();
    widget.card.image = _image;
    await DeckRepository.instance.upsertCard(widget.card);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final card = widget.card;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 18,
                ),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  children: [
                    Text(
                      card.front,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: AppTheme.displayFont,
                        fontWeight: FontWeight.w700,
                        fontSize: 24,
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      card.back,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: AppTheme.bodyFont,
                        fontSize: 16,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    if (card.review.lapses > 0) ...[
                      const SizedBox(height: 10),
                      Text(
                        trf('hook_lapses', {'n': '${card.review.lapses}'}),
                        style: TextStyle(
                          fontFamily: AppTheme.bodyFont,
                          fontSize: 12.5,
                          color: scheme.error,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _hook,
                autofocus: true,
                minLines: 2,
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: tr('card_mnemonic'),
                  prefixIcon: const Icon(Icons.lightbulb_outline_rounded),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                tr('hook_advice'),
                style: TextStyle(
                  fontFamily: AppTheme.bodyFont,
                  fontSize: 12.5,
                  height: 1.4,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              CardImageField(
                cardId: card.id,
                initial: _image,
                onChanged: (name) => _image = name,
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.tonal(
                      onPressed: () => Navigator.pop(context, false),
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
