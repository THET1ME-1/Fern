import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/strings.dart';
import '../language_picker_sheet.dart';
import '../services/language_registry.dart';
import '../services/source_library.dart';
import '../theme/app_theme.dart';

/// Редактор метаданных книги: название, автор, описание, жанры, теги.
/// Сохраняет прямо в [SourceLibrary]. Возвращает true, если что-то поменяли.
Future<bool> showBookMetaEditor(
  BuildContext context,
  LibrarySource source,
) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => _BookMetaEditor(source: source),
  );
  return saved ?? false;
}

class _BookMetaEditor extends StatefulWidget {
  final LibrarySource source;
  const _BookMetaEditor({required this.source});

  @override
  State<_BookMetaEditor> createState() => _BookMetaEditorState();
}

class _BookMetaEditorState extends State<_BookMetaEditor> {
  late final TextEditingController _title;
  late final TextEditingController _author;
  late final TextEditingController _description;
  late List<String> _genres;
  late List<String> _tags;
  late String _lang;

  @override
  void initState() {
    super.initState();
    final s = widget.source;
    _title = TextEditingController(text: s.title);
    _author = TextEditingController(text: s.author);
    _description = TextEditingController(text: s.description);
    _genres = List<String>.from(s.genres);
    _tags = List<String>.from(s.tags);
    _lang = s.languageCode;
  }

  @override
  void dispose() {
    _title.dispose();
    _author.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) return;
    HapticFeedback.selectionClick();
    await SourceLibrary.instance.updateBook(
      widget.source.id,
      title: _title.text,
      author: _author.text,
      description: _description.text,
      genres: _genres,
      tags: _tags,
      languageCode: _lang,
    );
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _pickLanguage() async {
    final code = await showLanguagePicker(context, _lang, unknownCode: _lang);
    if (code != null && mounted) setState(() => _lang = code);
  }

  Widget _languageRow(ColorScheme scheme) {
    final lang = LanguageRegistry.instance.byCode(_lang);
    final label = lang == null ? _lang.toUpperCase() : '${lang.emoji}  ${lang.name}';
    return Material(
      color: scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _pickLanguage,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(Icons.translate_rounded, color: scheme.onSurfaceVariant),
              const SizedBox(width: 12),
              Text(
                tr('book_language'),
                style: TextStyle(
                  fontFamily: AppTheme.bodyFont,
                  fontSize: 14,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              Text(
                label,
                style: TextStyle(
                  fontFamily: AppTheme.bodyFont,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: scheme.onSurface,
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.expand_more_rounded, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
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
                tr('book_edit'),
                style: TextStyle(
                  fontFamily: AppTheme.displayFont,
                  fontWeight: FontWeight.w800,
                  fontSize: 20,
                  color: scheme.onSurface,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _title,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: tr('book_title_label'),
                  prefixIcon: const Icon(Icons.menu_book_rounded),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _author,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: tr('book_author'),
                  prefixIcon: const Icon(Icons.person_outline_rounded),
                ),
              ),
              const SizedBox(height: 12),
              _languageRow(scheme),
              const SizedBox(height: 12),
              TextField(
                controller: _description,
                textCapitalization: TextCapitalization.sentences,
                minLines: 2,
                maxLines: 5,
                decoration: InputDecoration(
                  labelText: tr('book_description'),
                  alignLabelWithHint: true,
                  prefixIcon: const Icon(Icons.notes_rounded),
                ),
              ),
              const SizedBox(height: 20),
              _ChipsField(
                label: tr('book_genres'),
                icon: Icons.theater_comedy_outlined,
                values: _genres,
                onChanged: (v) => setState(() => _genres = v),
              ),
              const SizedBox(height: 18),
              _ChipsField(
                label: tr('book_tags'),
                icon: Icons.sell_outlined,
                values: _tags,
                onChanged: (v) => setState(() => _tags = v),
              ),
              const SizedBox(height: 24),
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

/// Поле-ввод набора меток (жанры/теги): чип за чипом, Enter/запятая добавляет.
class _ChipsField extends StatefulWidget {
  final String label;
  final IconData icon;
  final List<String> values;
  final ValueChanged<List<String>> onChanged;

  const _ChipsField({
    required this.label,
    required this.icon,
    required this.values,
    required this.onChanged,
  });

  @override
  State<_ChipsField> createState() => _ChipsFieldState();
}

class _ChipsFieldState extends State<_ChipsField> {
  final TextEditingController _input = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _commit(String raw) {
    // Разрешаем ввести сразу несколько через запятую.
    final parts = raw.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty);
    if (parts.isEmpty) {
      _input.clear();
      return;
    }
    final next = List<String>.from(widget.values);
    for (final p in parts) {
      if (!next.any((e) => e.toLowerCase() == p.toLowerCase())) next.add(p);
    }
    widget.onChanged(next);
    _input.clear();
  }

  void _remove(String value) {
    widget.onChanged(
      widget.values.where((e) => e != value).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: TextStyle(
            fontFamily: AppTheme.bodyFont,
            fontWeight: FontWeight.w600,
            fontSize: 14,
            color: scheme.onSurfaceVariant,
          ),
        ),
        if (widget.values.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final v in widget.values)
                InputChip(
                  label: Text(v),
                  onDeleted: () => _remove(v),
                  deleteIcon: const Icon(Icons.close_rounded, size: 18),
                ),
            ],
          ),
        ],
        const SizedBox(height: 8),
        TextField(
          controller: _input,
          textInputAction: TextInputAction.done,
          textCapitalization: TextCapitalization.sentences,
          onSubmitted: _commit,
          decoration: InputDecoration(
            hintText: tr('chips_add_hint'),
            prefixIcon: Icon(widget.icon),
            suffixIcon: IconButton(
              icon: const Icon(Icons.add_rounded),
              onPressed: () => _commit(_input.text),
            ),
          ),
        ),
      ],
    );
  }
}
