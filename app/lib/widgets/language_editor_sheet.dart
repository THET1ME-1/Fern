import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/strings.dart';
import '../models/language.dart';
import '../services/language_registry.dart';
import '../theme/app_theme.dart';

/// Редактор своего изучаемого языка: код (только при создании), название и флаг.
///
/// Возвращает [StudyLanguage] (создание/правку) или null, если отменили.
/// [existing] — правим существующий (код неизменяем, иначе осиротеют колоды).
/// [prefillCode] — предзаполнить код (например, язык видео, которого нет в
/// списке).
Future<StudyLanguage?> showLanguageEditor(
  BuildContext context, {
  StudyLanguage? existing,
  String? prefillCode,
}) {
  final scheme = Theme.of(context).colorScheme;
  return showModalBottomSheet<StudyLanguage>(
    context: context,
    isScrollControlled: true,
    backgroundColor: scheme.surfaceContainer,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => _LanguageEditorSheet(
      existing: existing,
      prefillCode: prefillCode,
    ),
  );
}

class _LanguageEditorSheet extends StatefulWidget {
  final StudyLanguage? existing;
  final String? prefillCode;
  const _LanguageEditorSheet({this.existing, this.prefillCode});

  @override
  State<_LanguageEditorSheet> createState() => _LanguageEditorSheetState();
}

class _LanguageEditorSheetState extends State<_LanguageEditorSheet> {
  late final TextEditingController _code = TextEditingController(
      text: widget.existing?.code ?? widget.prefillCode?.trim().toLowerCase());
  late final TextEditingController _name =
      TextEditingController(text: widget.existing?.name);
  late final TextEditingController _emoji =
      TextEditingController(text: widget.existing?.emoji);
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    _emoji.dispose();
    super.dispose();
  }

  void _save() {
    final code = _code.text
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9-]'), '');
    final name = _name.text.trim();
    if (code.isEmpty || name.isEmpty) {
      setState(() => _error = tr('field_required'));
      return;
    }
    // При создании нельзя занять уже существующий код (встроенный или свой).
    if (!_isEdit && LanguageRegistry.instance.byCode(code) != null) {
      setState(() => _error = tr('lang_code_taken'));
      return;
    }
    final emoji = _emoji.text.trim().isEmpty ? '🌐' : _emoji.text.trim();
    HapticFeedback.selectionClick();
    Navigator.pop(context, StudyLanguage(code, name, emoji));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
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
                _isEdit ? tr('edit_language') : tr('create_language'),
                style: TextStyle(
                  fontFamily: AppTheme.displayFont,
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                  color: scheme.onSurface,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 84,
                    child: TextField(
                      controller: _emoji,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 24),
                      decoration: InputDecoration(
                        labelText: tr('lang_emoji_hint'),
                        labelStyle: const TextStyle(fontSize: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _name,
                      textCapitalization: TextCapitalization.words,
                      decoration: InputDecoration(
                        labelText: tr('lang_name_hint'),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _code,
                enabled: !_isEdit, // код неизменяем при правке
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: tr('language_code_hint'),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  style: TextStyle(color: scheme.error, fontSize: 12.5),
                ),
              ],
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
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
