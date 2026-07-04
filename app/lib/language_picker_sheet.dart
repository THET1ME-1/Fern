import 'package:flutter/material.dart';

import 'l10n/strings.dart';
import 'models/language.dart';
import 'theme/app_theme.dart';

/// Нижняя панель выбора изучаемого языка (верхний баннер главного экрана —
/// аналог «выбора игры» в ScoreMaster). Возвращает код выбранного языка.
Future<String?> showLanguagePicker(BuildContext context, String selected) {
  final scheme = Theme.of(context).colorScheme;
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: scheme.surfaceContainer,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => _LanguagePickerSheet(selected: selected),
  );
}

class _LanguagePickerSheet extends StatefulWidget {
  final String selected;
  const _LanguagePickerSheet({required this.selected});

  @override
  State<_LanguagePickerSheet> createState() => _LanguagePickerSheetState();
}

class _LanguagePickerSheetState extends State<_LanguagePickerSheet> {
  final TextEditingController _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<StudyLanguage> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return kStudyLanguages;
    return kStudyLanguages
        .where((l) =>
            l.name.toLowerCase().contains(q) ||
            l.code.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final maxH = MediaQuery.of(context).size.height * 0.78;
    final items = _filtered;
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
                Align(
                  alignment: Alignment.centerLeft,
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
                const SizedBox(height: 12),
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
                const SizedBox(height: 12),
                Flexible(
                  child: items.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.symmetric(vertical: 28),
                          child: Text(
                            tr('no_matches'),
                            style: TextStyle(color: scheme.onSurfaceVariant),
                          ),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          itemCount: items.length,
                          itemBuilder: (_, i) => _tile(context, items[i], scheme),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _tile(BuildContext context, StudyLanguage l, ColorScheme scheme) {
    final isSel = l.code == widget.selected;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: isSel ? scheme.primaryContainer : scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Navigator.pop(context, l.code),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Text(l.emoji, style: const TextStyle(fontSize: 26)),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    l.name,
                    style: TextStyle(
                      fontFamily: AppTheme.bodyFont,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color:
                          isSel ? scheme.onPrimaryContainer : scheme.onSurface,
                    ),
                  ),
                ),
                if (isSel)
                  Icon(Icons.check_circle_rounded, color: scheme.primary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
