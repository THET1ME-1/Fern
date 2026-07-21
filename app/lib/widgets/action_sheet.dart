import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Пункт нижнего меню.
class SheetAction {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// Опасное действие (удаление) — красится ролью ошибки.
  final bool destructive;

  /// Подсвеченный пункт: включённое состояние вроде «Остановить чтение».
  final bool highlighted;

  const SheetAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
    this.highlighted = false,
  });
}

/// Меню действий листом снизу — вместо выпадающего списка у края экрана.
///
/// Всплывающее меню появляется под пальцем в углу, где его нижние пункты
/// приходится доставать второй рукой, а на широком экране оно ещё и уезжает от
/// места нажатия. Лист снизу открывается там, где рука уже есть.
class ActionSheet {
  ActionSheet._();

  static Future<void> show(
    BuildContext context, {
    required List<SheetAction> actions,
    String? title,

    /// Цвета листа. По умолчанию — из темы приложения; читалка передаёт свои,
    /// чтобы меню совпадало с бумагой (сепия, ночь).
    Color? background,
    Color? foreground,
    Color? accent,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final bg = background ?? scheme.surfaceContainerHigh;
    final fg = foreground ?? scheme.onSurface;
    final hl = accent ?? scheme.primary;

    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: fg.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              if (title != null) ...[
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    title,
                    style: TextStyle(
                      fontFamily: AppTheme.displayFont,
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                      color: fg,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 10),
              for (final a in actions)
                _Item(
                  action: a,
                  foreground: fg,
                  highlight: hl,
                  danger: scheme.error,
                  onTap: () {
                    Navigator.pop(ctx);
                    a.onTap();
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Item extends StatelessWidget {
  final SheetAction action;
  final Color foreground;
  final Color highlight;
  final Color danger;
  final VoidCallback onTap;

  const _Item({
    required this.action,
    required this.foreground,
    required this.highlight,
    required this.danger,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = action.destructive
        ? danger
        : action.highlighted
            ? highlight
            : foreground;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          child: Row(
            children: [
              Icon(action.icon, size: 22, color: color),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  action.label,
                  style: TextStyle(
                    fontFamily: AppTheme.bodyFont,
                    fontSize: 15.5,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
