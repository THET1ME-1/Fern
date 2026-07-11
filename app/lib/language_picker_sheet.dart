import 'package:flutter/material.dart';

import 'l10n/strings.dart';
import 'models/language.dart';
import 'services/language_registry.dart';
import 'theme/app_theme.dart';
import 'widgets/language_editor_sheet.dart';

/// Нижняя панель выбора изучаемого языка. Закреплённые — вверху (чтобы не
/// искать); можно создавать/править/удалять свои языки и закреплять любые.
/// [unknownCode] — код источника (видео/книги), которого нет в списке: тогда
/// сверху появляется кнопка «Добавить «код»». Возвращает код выбранного языка.
Future<String?> showLanguagePicker(
  BuildContext context,
  String selected, {
  String? unknownCode,
}) {
  final scheme = Theme.of(context).colorScheme;
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: scheme.surfaceContainer,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) =>
        _LanguagePickerSheet(selected: selected, unknownCode: unknownCode),
  );
}

class _LanguagePickerSheet extends StatefulWidget {
  final String selected;
  final String? unknownCode;
  const _LanguagePickerSheet({required this.selected, this.unknownCode});

  @override
  State<_LanguagePickerSheet> createState() => _LanguagePickerSheetState();
}

class _LanguagePickerSheetState extends State<_LanguagePickerSheet> {
  final LanguageRegistry _reg = LanguageRegistry.instance;
  final TextEditingController _search = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _reg.addListener(_onReg);
  }

  @override
  void dispose() {
    _reg.removeListener(_onReg);
    _search.dispose();
    super.dispose();
  }

  void _onReg() {
    if (mounted) setState(() {});
  }

  bool _matches(StudyLanguage l, String q) =>
      l.name.toLowerCase().contains(q) || l.code.toLowerCase().contains(q);

  Future<void> _createLanguage({String? prefill}) async {
    final lang = await showLanguageEditor(context, prefillCode: prefill);
    if (lang == null) return;
    await _reg.addOrUpdateCustom(lang, pin: true);
    if (mounted) Navigator.pop(context, lang.code); // создали → сразу выбрали
  }

  Future<void> _editLanguage(StudyLanguage l) async {
    final lang = await showLanguageEditor(context, existing: l);
    if (lang == null) return;
    await _reg.addOrUpdateCustom(lang); // остаёмся в пикере
  }

  Future<void> _deleteLanguage(StudyLanguage l) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('delete_language')),
        content: Text(tr('delete_language_confirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('delete')),
          ),
        ],
      ),
    );
    if (ok == true) await _reg.removeCustom(l.code);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final maxH = MediaQuery.of(context).size.height * 0.82;
    final q = _query.trim().toLowerCase();

    final all = _reg.all;
    final pinnedSet = _reg.pinnedCodes.toSet();
    final searching = q.isNotEmpty;

    // Элементы списка: заголовки-секции + языки. При поиске — плоский список.
    final rows = <_Row>[];
    if (searching) {
      for (final l in all.where((l) => _matches(l, q))) {
        rows.add(_Row.lang(l));
      }
    } else {
      final pinned = all.where((l) => pinnedSet.contains(l.code)).toList();
      final rest = all.where((l) => !pinnedSet.contains(l.code)).toList();
      if (pinned.isNotEmpty) {
        rows.add(_Row.header(tr('pinned')));
        for (final l in pinned) {
          rows.add(_Row.lang(l));
        }
        rows.add(_Row.header(tr('all_languages')));
      }
      for (final l in rest) {
        rows.add(_Row.lang(l));
      }
    }

    final showAddUnknown = widget.unknownCode != null &&
        widget.unknownCode!.isNotEmpty &&
        !_reg.isKnown(widget.unknownCode!);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxH),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
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
                  children: [
                    Expanded(
                      child: Text(
                        tr('choose_language'),
                        style: TextStyle(
                          fontFamily: AppTheme.displayFont,
                          fontWeight: FontWeight.w700,
                          fontSize: 18,
                          color: scheme.onSurface,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => _createLanguage(),
                      icon: const Icon(Icons.add_rounded, size: 20),
                      label: Text(tr('create_language')),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _search,
                  onChanged: (v) => setState(() => _query = v),
                  decoration: InputDecoration(
                    hintText: tr('search_language'),
                    prefixIcon: const Icon(Icons.search_rounded),
                    isDense: true,
                    filled: true,
                    fillColor: scheme.surfaceContainerHigh,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                if (showAddUnknown) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.tonalIcon(
                      onPressed: () =>
                          _createLanguage(prefill: widget.unknownCode),
                      icon: const Icon(Icons.add_circle_outline_rounded),
                      label: Text(
                        trf('add_language_named', {'code': widget.unknownCode!}),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Flexible(
                  child: rows.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.symmetric(vertical: 28),
                          child: Text(
                            tr('no_matches'),
                            style: TextStyle(color: scheme.onSurfaceVariant),
                          ),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          itemCount: rows.length,
                          itemBuilder: (_, i) => rows[i].header != null
                              ? _sectionHeader(rows[i].header!, scheme)
                              : _tile(rows[i].lang!, scheme),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionHeader(String text, ColorScheme scheme) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 10, 4, 6),
        child: Text(
          text,
          style: TextStyle(
            fontFamily: AppTheme.bodyFont,
            fontWeight: FontWeight.w700,
            fontSize: 12.5,
            letterSpacing: 0.3,
            color: scheme.onSurfaceVariant,
          ),
        ),
      );

  Widget _tile(StudyLanguage l, ColorScheme scheme) {
    final isSel = l.code == widget.selected;
    final isPinned = _reg.isPinned(l.code);
    final isCustom = _reg.isCustom(l.code);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: isSel ? scheme.primaryContainer : scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Navigator.pop(context, l.code),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 6, 10),
            child: Row(
              children: [
                Text(l.emoji, style: const TextStyle(fontSize: 26)),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              l.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: AppTheme.bodyFont,
                                fontSize: 16.5,
                                fontWeight: FontWeight.w600,
                                color: isSel
                                    ? scheme.onPrimaryContainer
                                    : scheme.onSurface,
                              ),
                            ),
                          ),
                          if (isCustom) ...[
                            const SizedBox(width: 8),
                            _customTag(scheme),
                          ],
                        ],
                      ),
                      Text(
                        l.code,
                        style: TextStyle(
                          fontFamily: AppTheme.bodyFont,
                          fontSize: 11.5,
                          color: (isSel
                                  ? scheme.onPrimaryContainer
                                  : scheme.onSurfaceVariant)
                              .withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: isPinned ? tr('unpin_language') : tr('pin_language'),
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    isPinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                    size: 20,
                    color: isPinned ? scheme.primary : scheme.onSurfaceVariant,
                  ),
                  onPressed: () => _reg.togglePin(l.code),
                ),
                if (isCustom)
                  PopupMenuButton<String>(
                    tooltip: '',
                    icon: Icon(Icons.more_vert_rounded,
                        size: 20, color: scheme.onSurfaceVariant),
                    onSelected: (v) {
                      if (v == 'edit') _editLanguage(l);
                      if (v == 'delete') _deleteLanguage(l);
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(value: 'edit', child: Text(tr('edit_language'))),
                      PopupMenuItem(
                          value: 'delete', child: Text(tr('delete_language'))),
                    ],
                  )
                else if (isSel)
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child:
                        Icon(Icons.check_circle_rounded, color: scheme.primary),
                  )
                else
                  const SizedBox(width: 10),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _customTag(ColorScheme scheme) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: scheme.tertiary.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          tr('custom_lang_tag'),
          style: TextStyle(
            fontFamily: AppTheme.bodyFont,
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: scheme.tertiary,
          ),
        ),
      );
}

/// Строка списка: либо заголовок секции, либо язык.
class _Row {
  final String? header;
  final StudyLanguage? lang;
  const _Row.header(this.header) : lang = null;
  const _Row.lang(this.lang) : header = null;
}
