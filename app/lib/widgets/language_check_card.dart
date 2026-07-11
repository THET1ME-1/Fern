import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../services/language_registry.dart';
import '../theme/app_theme.dart';
import 'pressable.dart';

/// Карточка-напоминание: язык источника (видео/книги) определён автоматически
/// и может быть неверным. Показывает текущий язык (флаг + название) и по нажатию
/// зовёт [onChange], где вызывающий открывает выбор языка и пересчитывает анализ.
///
/// Общая для страницы книги и страницы видео — единый вид и текст предупреждения.
class LanguageCheckCard extends StatelessWidget {
  final String languageCode;
  final Future<void> Function() onChange;

  const LanguageCheckCard({
    super.key,
    required this.languageCode,
    required this.onChange,
  });

  // Тёплый «предупреждающий» акцент, читаемый в любой теме.
  static const Color _warn = Color(0xFFDDA13F);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final lang = LanguageRegistry.instance.byCode(languageCode);
    final label = lang != null
        ? '${lang.emoji}  ${lang.name}'
        : '🌐  ${tr('unknown_language')} ($languageCode)';

    return PressableScale(
      child: Material(
        color: _warn.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onChange,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.translate_rounded, size: 20, color: _warn),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        tr('lang_check_title'),
                        style: TextStyle(
                          fontFamily: AppTheme.displayFont,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: scheme.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 9,
                        ),
                        decoration: BoxDecoration(
                          color: scheme.surface.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: AppTheme.bodyFont,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            color: scheme.onSurface,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    FilledButton.tonalIcon(
                      onPressed: onChange,
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                      icon: const Icon(Icons.edit_rounded, size: 18),
                      label: Text(tr('change_language')),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  tr('lang_detect_warning'),
                  style: TextStyle(
                    fontFamily: AppTheme.bodyFont,
                    fontSize: 12.5,
                    height: 1.35,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
