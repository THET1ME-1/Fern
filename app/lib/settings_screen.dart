import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'l10n/locale_controller.dart';
import 'l10n/strings.dart';
import 'settings/providers_screen.dart';
import 'models/deck.dart';
import 'services/deck_import.dart';
import 'services/deck_repository.dart';
import 'services/notification_service.dart';
import 'services/pos_split.dart';
import 'services/translation/translation_manager.dart';
import 'services/update_service.dart';
import 'services/vocab_export.dart';
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
  bool _showVideoBanner = true;
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
    final showBanner = await _repo.showVideoBanner();
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
        _showVideoBanner = showBanner;
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
          _actionTile(
            icon: Icons.translate_rounded,
            title: tr('providers_title'),
            trailing: TranslationManager.instance.active.name,
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ProvidersScreen()),
              );
              if (mounted) setState(() {});
            },
            scheme: scheme,
          ),
          const SizedBox(height: 16),
          _sectionTitle(tr('home_screen'), scheme),
          _switchTile(
            icon: Icons.subtitles_rounded,
            title: tr('show_video_banner'),
            subtitle: tr('show_video_banner_sub'),
            value: _showVideoBanner,
            onChanged: (v) async {
              setState(() => _showVideoBanner = v);
              await _repo.setShowVideoBanner(v);
            },
            scheme: scheme,
          ),
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
          _actionTile(
            icon: Icons.ios_share_rounded,
            title: tr('export_vocab'),
            onTap: _exportVocab,
            scheme: scheme,
          ),
          _actionTile(
            icon: Icons.file_download_rounded,
            title: tr('import_deck'),
            subtitle: tr('import_deck_sub'),
            onTap: _importDeck,
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

  /// Экспорт личного словаря: выбор формата → генерация файла → «Поделиться».
  Future<void> _exportVocab() async {
    final scheme = Theme.of(context).colorScheme;
    final fmt = await showModalBottomSheet<VocabFormat>(
      context: context,
      backgroundColor: scheme.surfaceContainer,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 14),
            Text(tr('export_vocab'), style: Theme.of(ctx).textTheme.titleMedium),
            const SizedBox(height: 8),
            _exportOption(ctx, VocabFormat.csv, Icons.grid_on_rounded,
                'CSV', tr('fmt_csv_sub')),
            _exportOption(ctx, VocabFormat.ankiTsv, Icons.school_rounded,
                'Anki / Quizlet (TSV)', tr('fmt_anki_sub')),
            _exportOption(ctx, VocabFormat.json, Icons.data_object_rounded,
                'JSON', tr('fmt_json_sub')),
            _exportOption(ctx, VocabFormat.list, Icons.list_rounded,
                tr('fmt_list'), tr('fmt_list_sub')),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (fmt == null) return;
    await _doExport(fmt);
  }

  Widget _exportOption(
    BuildContext ctx,
    VocabFormat fmt,
    IconData icon,
    String title,
    String sub,
  ) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(sub),
      onTap: () => Navigator.pop(ctx, fmt),
    );
  }

  Future<void> _doExport(VocabFormat fmt) async {
    try {
      final cards = await _repo.loadCards();
      if (cards.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(tr('export_empty'))),
          );
        }
        return;
      }
      final content = VocabExport.build(fmt, cards);
      final dir = await getApplicationDocumentsDirectory();
      final file = File(
        '${dir.path}/${VocabExport.fileBaseName(fmt)}.'
        '${VocabExport.extensionFor(fmt)}',
      );
      await file.writeAsString(content);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(trf('export_done', {'n': cards.length}))),
      );
      try {
        await Share.shareXFiles([XFile(file.path)]);
      } catch (_) {
        /* share не поддержан на десктопе — файл уже сохранён */
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr('restore_failed'))),
        );
      }
    }
  }

  /// Импорт колоды из Anki (.apkg) или текстового списка (CSV/TSV/TXT).
  Future<void> _importDeck() async {
    String? path;
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: DeckImport.supportedExtensions,
      );
      path = result?.files.single.path;
    } catch (_) {
      final result = await FilePicker.platform.pickFiles(type: FileType.any);
      path = result?.files.single.path;
    }
    if (path == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(tr('importing'))),
    );
    final lang = await _repo.selectedLanguageCode() ?? 'en';
    final res = await DeckImport.import(path, lang);
    if (!mounted) return;
    final String msg;
    switch (res.outcome) {
      case ImportOutcome.ok:
        msg = trf('import_done', {'n': res.count, 'name': res.deckName});
      case ImportOutcome.unsupported:
        msg = tr('import_unsupported');
      case ImportOutcome.empty:
        msg = tr('import_empty');
      case ImportOutcome.failed:
        msg = tr('import_failed');
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
    if (res.outcome == ImportOutcome.ok) {
      await _offerSplitByPos(res.deckId, res.count);
    }
  }

  /// Предлагает разложить только что импортированную колоду по частям речи.
  Future<void> _offerSplitByPos(String? deckId, int wordCount) async {
    if (deckId == null || !mounted) return;
    Deck? deck;
    for (final d in _repo.decks) {
      if (d.id == deckId) {
        deck = d;
        break;
      }
    }
    if (deck == null) return;
    if (await PosSplit.countGroups(deck) < 2 || !mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('split_by_pos')),
        content: Text(trf('split_by_pos_offer', {'n': wordCount})),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('apply')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final created = await PosSplit.split(deck);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(created > 0
            ? trf('split_done', {'n': created})
            : tr('split_none')),
      ));
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
    String? subtitle,
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
          subtitle: subtitle == null ? null : Text(subtitle),
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
