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

class _LanguagePickerSheet extends StatelessWidget {
  final String selected;
  const _LanguagePickerSheet({required this.selected});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
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
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final l in kStudyLanguages) _tile(context, l, scheme),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tile(BuildContext context, StudyLanguage l, ColorScheme scheme) {
    final isSel = l.code == selected;
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
