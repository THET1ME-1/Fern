import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'l10n/locale_controller.dart';
import 'l10n/strings.dart';
import 'services/deck_repository.dart';
import 'services/notification_service.dart';
import 'services/update_service.dart';
import 'theme/app_theme.dart';
import 'theme/theme_controller.dart';
import 'utils/app_version.dart';
import 'widgets/color_picker_sheet.dart';
import 'widgets/update_sheet.dart';

/// Экран настроек: внешний вид, обучение, язык интерфейса, данные, о программе.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final DeckRepository _repo = DeckRepository.instance;
  final ThemeController _theme = ThemeController.instance;
  final LocaleController _locale = LocaleController.instance;

  String _version = '';
  int _goal = 20;
  bool _reminderOn = false;
  TimeOfDay _reminderTime = const TimeOfDay(hour: 20, minute: 0);

  @override
  void initState() {
    super.initState();
    _loadInfo();
  }

  Future<void> _loadInfo() async {
    final goal = await _repo.dailyGoal();
    final on = await _repo.reminderEnabled();
    final h = await _repo.reminderHour();
    final m = await _repo.reminderMinute();
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() => _version = '${info.version}+${info.buildNumber}');
      }
    } catch (_) {
      /* игнор */
    }
    if (mounted) {
      setState(() {
        _goal = goal;
        _reminderOn = on;
        _reminderTime = TimeOfDay(hour: h, minute: m);
      });
    }
  }

  Future<void> _toggleReminder(bool on) async {
    if (on) {
      final granted = await NotificationService.instance.requestPermission();
      if (!granted) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(tr('notifications_blocked'))));
        }
        return; // тумблер остаётся выключенным
      }
      await _repo.setReminderEnabled(true);
      await NotificationService.instance.scheduleDaily(
        hour: _reminderTime.hour,
        minute: _reminderTime.minute,
        title: tr('reminder_push_title'),
        body: tr('reminder_push_body'),
      );
      if (mounted) setState(() => _reminderOn = true);
    } else {
      await _repo.setReminderEnabled(false);
      await NotificationService.instance.cancelDaily();
      if (mounted) setState(() => _reminderOn = false);
    }
  }

  Future<void> _pickReminderTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _reminderTime,
    );
    if (picked == null) return;
    await _repo.setReminderTime(picked.hour, picked.minute);
    if (mounted) setState(() => _reminderTime = picked);
    if (_reminderOn) {
      await NotificationService.instance.scheduleDaily(
        hour: picked.hour,
        minute: picked.minute,
        title: tr('reminder_push_title'),
        body: tr('reminder_push_body'),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(tr('settings_title'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _sectionTitle(tr('appearance'), scheme),
          _themeModeTile(scheme),
          _colorTile(scheme),
          _switchTile(
            icon: Icons.palette_rounded,
            title: tr('dynamic_color'),
            subtitle: tr('dynamic_color_sub'),
            value: _theme.useDynamicColor,
            onChanged: (v) => _theme.setUseDynamicColor(v),
            scheme: scheme,
          ),
          if (_theme.isDark)
            _switchTile(
              icon: Icons.contrast_rounded,
              title: tr('amoled'),
              subtitle: tr('amoled_sub'),
              value: _theme.amoled,
              onChanged: (v) => _theme.setAmoled(v),
              scheme: scheme,
            ),
          const SizedBox(height: 16),
          _sectionTitle(tr('study'), scheme),
          _goalTile(scheme),
          const SizedBox(height: 16),
          _sectionTitle(tr('reminders'), scheme),
          _switchTile(
            icon: Icons.notifications_active_rounded,
            title: tr('daily_reminder'),
            subtitle: tr('daily_reminder_sub'),
            value: _reminderOn,
            onChanged: _toggleReminder,
            scheme: scheme,
          ),
          if (_reminderOn)
            _actionTile(
              icon: Icons.schedule_rounded,
              title: tr('reminder_time'),
              trailing: _reminderTime.format(context),
              onTap: _pickReminderTime,
              scheme: scheme,
            ),
          const SizedBox(height: 16),
          _sectionTitle(tr('language'), scheme),
          _languageTile(scheme),
          const SizedBox(height: 16),
          _sectionTitle(tr('data'), scheme),
          _actionTile(
            icon: Icons.backup_rounded,
            title: tr('create_backup'),
            onTap: _backup,
            scheme: scheme,
          ),
          _actionTile(
            icon: Icons.restore_rounded,
            title: tr('restore_backup'),
            onTap: _restore,
            scheme: scheme,
          ),
          const SizedBox(height: 16),
          _sectionTitle(tr('about'), scheme),
          _infoTile(
            icon: Icons.info_outline_rounded,
            title: tr('version'),
            trailing: _version,
            scheme: scheme,
          ),
          _actionTile(
            icon: Icons.system_update_rounded,
            title: tr('check_updates'),
            onTap: _checkUpdates,
            scheme: scheme,
          ),
        ],
      ),
    );
  }

  // ------------------------------- Внешний вид -------------------------------

  Widget _themeModeTile(ColorScheme scheme) {
    final label = switch (_theme.mode) {
      AppThemeMode.light => tr('theme_light'),
      AppThemeMode.dark => tr('theme_dark'),
      AppThemeMode.system => tr('theme_system'),
      AppThemeMode.autoTime => tr('theme_auto'),
    };
    return _actionTile(
      icon: Icons.brightness_6_rounded,
      title: tr('theme_mode'),
      trailing: label,
      onTap: _pickThemeMode,
      scheme: scheme,
    );
  }

  Future<void> _pickThemeMode() async {
    final scheme = Theme.of(context).colorScheme;
    await showModalBottomSheet(
      context: context,
      backgroundColor: scheme.surfaceContainer,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => SafeArea(
        child: RadioGroup<AppThemeMode>(
          groupValue: _theme.mode,
          onChanged: (v) {
            if (v != null) _theme.setMode(v);
            Navigator.pop(ctx);
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              for (final m in AppThemeMode.values)
                RadioListTile<AppThemeMode>(
                  value: m,
                  title: Text(switch (m) {
                    AppThemeMode.light => tr('theme_light'),
                    AppThemeMode.dark => tr('theme_dark'),
                    AppThemeMode.system => tr('theme_system'),
                    AppThemeMode.autoTime => tr('theme_auto'),
                  }),
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _colorTile(ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          leading: Icon(
            Icons.color_lens_rounded,
            color: scheme.onSurfaceVariant,
          ),
          title: Text(tr('theme_color')),
          subtitle: Text(
            _theme.isDefaultSeed
                ? tr('theme_color_default')
                : colorToHex(_theme.seedColor),
          ),
          trailing: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: _theme.seedColor,
              shape: BoxShape.circle,
              border: Border.all(color: scheme.outlineVariant),
            ),
          ),
          onTap: () async {
            final picked = await showColorPickerSheet(
              context,
              initial: _theme.seedColor,
              title: tr('theme_color'),
              resetTo: AppTheme.defaultSeed,
            );
            if (picked != null) _theme.setSeedColor(picked);
          },
        ),
      ),
    );
  }

  // ------------------------------- Обучение -------------------------------

  Widget _goalTile(ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Icon(Icons.flag_rounded, color: scheme.onSurfaceVariant),
              const SizedBox(width: 16),
              Expanded(child: Text(tr('daily_goal'))),
              IconButton(
                icon: const Icon(Icons.remove_circle_outline_rounded),
                onPressed: _goal > 5 ? () => _setGoal(_goal - 5) : null,
              ),
              SizedBox(
                width: 36,
                child: Text(
                  '$_goal',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: AppTheme.displayFont,
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                    color: scheme.onSurface,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add_circle_outline_rounded),
                onPressed: _goal < 100 ? () => _setGoal(_goal + 5) : null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _setGoal(int v) async {
    setState(() => _goal = v);
    await _repo.setDailyGoal(v);
  }

  // ------------------------------- Язык -------------------------------

  Widget _languageTile(ColorScheme scheme) {
    final current = LocaleController.languages
        .firstWhere(
          (l) => l.code == _locale.code,
          orElse: () => LocaleController.languages.first,
        )
        .nativeName;
    return _actionTile(
      icon: Icons.language_rounded,
      title: tr('language'),
      trailing: current,
      onTap: _pickLanguage,
      scheme: scheme,
    );
  }

  Future<void> _pickLanguage() async {
    final scheme = Theme.of(context).colorScheme;
    await showModalBottomSheet(
      context: context,
      backgroundColor: scheme.surfaceContainer,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => SafeArea(
        child: RadioGroup<String>(
          groupValue: _locale.code,
          onChanged: (v) {
            if (v != null) _locale.setCode(v);
            Navigator.pop(ctx);
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              for (final l in LocaleController.languages)
                RadioListTile<String>(value: l.code, title: Text(l.nativeName)),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  // ------------------------------- Данные -------------------------------

  Future<void> _backup() async {
    try {
      final json = await _repo.exportJson();
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/fern_backup.json');
      await file.writeAsString(json);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(tr('backup_done'))));
      try {
        await Share.shareXFiles([XFile(file.path)]);
      } catch (_) {
        /* share не поддержан на десктопе — файл уже сохранён */
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(tr('restore_failed'))));
      }
    }
  }

  /// Ручная проверка обновления: показывает меню обновления или сообщает, что
  /// установлена последняя версия.
  Future<void> _checkUpdates() async {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('checking_updates'))),
      );
    }
    final current = await appVersionName();
    final info =
        current.isEmpty ? null : await UpdateService.checkForUpdate(current);
    if (!mounted) return;
    if (info == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('up_to_date'))),
      );
    } else {
      await UpdateSheet.show(context, info, current);
    }
  }

  Future<void> _restore() async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.any);
      final path = result?.files.single.path;
      if (path == null) return;
      final raw = await File(path).readAsString();
      await _repo.importJson(raw);
      await _theme.load();
      await _locale.load();
      await _loadInfo();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(tr('restore_done'))));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(tr('restore_failed'))));
      }
    }
  }

  // ------------------------------- Строительные блоки -------------------------------

  Widget _sectionTitle(String text, ColorScheme scheme) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
    child: Text(
      text,
      style: TextStyle(
        fontFamily: AppTheme.displayFont,
        fontWeight: FontWeight.w700,
        fontSize: 16,
        color: scheme.primary,
      ),
    ),
  );

  Widget _switchTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    required ColorScheme scheme,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: SwitchListTile(
          secondary: Icon(icon, color: scheme.onSurfaceVariant),
          title: Text(title),
          subtitle: Text(subtitle),
          value: value,
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _actionTile({
    required IconData icon,
    required String title,
    String? trailing,
    required VoidCallback onTap,
    required ColorScheme scheme,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          leading: Icon(icon, color: scheme.onSurfaceVariant),
          title: Text(title),
          trailing: trailing == null
              ? const Icon(Icons.chevron_right_rounded)
              : Text(
                  trailing,
                  style: TextStyle(
                    fontFamily: AppTheme.bodyFont,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
          onTap: onTap,
        ),
      ),
    );
  }

  Widget _infoTile({
    required IconData icon,
    required String title,
    required String trailing,
    required ColorScheme scheme,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          leading: Icon(icon, color: scheme.onSurfaceVariant),
          title: Text(title),
          trailing: Text(
            trailing,
            style: TextStyle(
              fontFamily: AppTheme.bodyFont,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}
