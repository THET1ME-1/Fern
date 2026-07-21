import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'l10n/locale_controller.dart';
import 'l10n/strings.dart';
import 'services/billing_service.dart';
import 'services/license_service.dart';
import 'utils/build_config.dart';
import 'services/pro.dart';
import 'widgets/pro_sheet.dart';
import 'settings/providers_screen.dart';
import 'services/backup_service.dart';
import 'services/deck_import.dart';
import 'services/deck_repository.dart';
import 'services/language_registry.dart';
import 'models/fsrs.dart';
import 'services/fsrs_optimizer.dart';
import 'study/schedule_explain_screen.dart';
import 'services/schedule_lab.dart';
import 'services/source_library.dart';
import 'study/reader_settings.dart';
import 'services/notification_service.dart';
import 'services/translation/translation_manager.dart';
import 'services/store_update.dart';
import 'services/vocab_export.dart';
import 'theme/app_theme.dart';
import 'theme/theme_controller.dart';
import 'widgets/color_picker_sheet.dart';
import 'widgets/seed_swatch.dart';

/// Готовые seed-цвета для быстрых цветовых схем (первый — фирменный зелёный Fern).
const List<Color> _kSeedPalettes = [
  Color(0xFF2E7D5B), // папоротниковый зелёный (по умолчанию)
  Color(0xFF00897B), // бирюзовый
  Color(0xFF1E88E5), // синий
  Color(0xFF7C4DFF), // фиолетовый
  Color(0xFFE53935), // красный
  Color(0xFFFF7043), // коралловый
  Color(0xFFFFB300), // янтарный
  Color(0xFFEC407A), // розовый
];

/// Экран настроек: внешний вид, обучение, язык интерфейса, данные, о программе.
/// Куда ведут кнопки доната. Те же адреса, что в Kadr: автор один, а
/// заводить вторую страницу сбора ради второго приложения незачем.
final Uri kBoostyUrl = Uri.parse('https://boosty.to/sntcompany');
final Uri kDonationAlertsUrl =
    Uri.parse('https://www.donationalerts.com/r/thet1me');

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final DeckRepository _repo = DeckRepository.instance;
  final ThemeController _theme = ThemeController.instance;
  final LocaleController _locale = LocaleController.instance;

  /// Палитра из обоев — часть Material You, то есть Android 12+.
  bool get _dynamicColorAvailable => Platform.isAndroid;

  String _version = '';
  int _goal = 20;
  int _newPerDay = 12;
  int _maxReviews = 100;
  double _retention = 0.9;
  int _reviewEvents = 0;
  bool _customWeights = false;
  bool _optimizing = false;
  bool _reminderOn = false;
  bool _showVideoBanner = true;
  bool _posSplitAsk = true;
  bool _twoButtons = false;
  TimeOfDay _reminderTime = const TimeOfDay(hour: 20, minute: 0);

  /// Свёрнутые секции. Живут только пока экран открыт: свернул однажды —
  /// не значит спрятал навсегда.
  final Set<String> _collapsed = {};

  @override
  void initState() {
    super.initState();
    _loadInfo();
  }

  Future<void> _loadInfo() async {
    final goal = await _repo.dailyGoal();
    final newPerDay = await _repo.newPerDay();
    final maxReviews = await _repo.maxReviews();
    final on = await _repo.reminderEnabled();
    final h = await _repo.reminderHour();
    final m = await _repo.reminderMinute();
    final showBanner = await _repo.showVideoBanner();
    final posSplitAsk = await _repo.posSplitAsk();
    final twoButtons = await _repo.twoButtonRating();
    final retention = await _repo.requestRetention();
    final events = await _repo.reviewEventCount();
    final custom = (await _repo.fsrsWeights()) != null;
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
        _newPerDay = newPerDay;
        _maxReviews = maxReviews;
        _retention = retention;
        _reviewEvents = events;
        _customWeights = custom;
        _reminderOn = on;
        _showVideoBanner = showBanner;
        _posSplitAsk = posSplitAsk;
        _twoButtons = twoButtons;
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
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          _section(
            id: 'appearance',
            title: tr('appearance'),
            icon: Icons.palette_outlined,
            scheme: scheme,
            children: [
              _themeModeTile(scheme),
              _colorTile(scheme),
              // Готовые цветовые схемы — кружки из 4 тонов темы (как в системном
              // пикере Material You). В режиме «цвет из обоев» пресеты не нужны.
              if (!_theme.useDynamicColor) _paletteRow(scheme),
              // Цвет из обоев берётся из системной палитры Material You, а её
              // нет нигде, кроме Android 12+. На iOS тумблер стоял бы мёртвым.
              if (_dynamicColorAvailable)
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
            ],
          ),
          _section(
            id: 'study',
            title: tr('study'),
            icon: Icons.school_outlined,
            scheme: scheme,
            children: [
              _goalTile(scheme),
              _newPerDayTile(scheme),
              _maxReviewsTile(scheme),
              _retentionTile(scheme),
              _optimizeTile(scheme),
              _actionTile(
                icon: Icons.insights_rounded,
                title: tr('how_fern_decides'),
                subtitle: tr('how_fern_decides_sub'),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const ScheduleExplainScreen(),
                  ),
                ),
                scheme: scheme,
              ),
              _switchTile(
                icon: Icons.touch_app_outlined,
                title: tr('two_buttons'),
                subtitle: tr('two_buttons_sub'),
                value: _twoButtons,
                onChanged: (v) async {
                  await _repo.setTwoButtonRating(v);
                  if (mounted) setState(() => _twoButtons = v);
                },
                scheme: scheme,
              ),
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
              _switchTile(
                icon: Icons.category_outlined,
                title: tr('pos_split_ask'),
                subtitle: tr('pos_split_ask_sub'),
                value: _posSplitAsk,
                onChanged: (v) async {
                  setState(() => _posSplitAsk = v);
                  await _repo.setPosSplitAsk(v);
                },
                scheme: scheme,
              ),
            ],
          ),
          _section(
            id: 'home',
            title: tr('home_screen'),
            icon: Icons.home_outlined,
            scheme: scheme,
            children: [
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
            ],
          ),
          _section(
            id: 'reminders',
            title: tr('reminders'),
            icon: Icons.notifications_outlined,
            scheme: scheme,
            children: [
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
            ],
          ),
          _section(
            id: 'language',
            title: tr('language'),
            icon: Icons.translate_outlined,
            scheme: scheme,
            children: [_languageTile(scheme)],
          ),
          _section(
            id: 'data',
            title: tr('data'),
            icon: Icons.folder_outlined,
            scheme: scheme,
            children: [
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
              // Последним в секции и цветом ошибки: единственный пункт на
              // экране, который нельзя отменить.
              _actionTile(
                icon: Icons.delete_forever_rounded,
                title: tr('wipe_data'),
                subtitle: tr('wipe_data_sub'),
                onTap: _wipeAllData,
                scheme: scheme,
                color: scheme.error,
              ),
            ],
          ),
          _section(
            id: 'pro',
            title: tr('pro_title'),
            icon: Icons.workspace_premium_outlined,
            scheme: scheme,
            children: _proTiles(scheme),
          ),
          _donationCard(scheme),
          const SizedBox(height: 22),
          _section(
            id: 'about',
            title: tr('about'),
            icon: Icons.info_outline_rounded,
            scheme: scheme,
            children: [
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
              _actionTile(
                icon: Icons.description_outlined,
                title: tr('licenses'),
                onTap: _openLicenses,
                scheme: scheme,
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Лицензии на чужие материалы внутри приложения (шрифты OFL, словарь,
  /// пакеты). Для OFL-шрифтов это не вежливость, а требование лицензии.
  void _openLicenses() {
    showLicensePage(
      context: context,
      applicationName: 'Fern',
      applicationVersion: _version,
      applicationLegalese: '© 2026 THET1ME-1',
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
      padding: EdgeInsets.zero,
      child: Material(
        color: Colors.transparent,
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
          trailing: SeedSwatch(seed: _theme.seedColor, size: 30),
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

  /// Готовые цветовые схемы — кружки из 4 тонов темы. Тап меняет seed.
  Widget _paletteRow(ColorScheme scheme) => Padding(
        padding: EdgeInsets.zero,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final c in _kSeedPalettes)
                  SeedSwatch(
                    seed: c,
                    selected: _theme.seedColor.toARGB32() == c.toARGB32(),
                    onTap: () => _theme.setSeedColor(c),
                  ),
              ],
            ),
          ),
        ),
      );

  // ------------------------------- Обучение -------------------------------

  Widget _goalTile(ColorScheme scheme) => _stepperTile(
        scheme,
        icon: Icons.flag_rounded,
        label: tr('daily_goal'),
        value: _goal,
        min: 5,
        max: 100,
        step: 5,
        onChanged: (v) async {
          setState(() => _goal = v);
          await _repo.setDailyGoal(v);
        },
      );

  Widget _newPerDayTile(ColorScheme scheme) => _stepperTile(
        scheme,
        icon: Icons.fiber_new_rounded,
        label: tr('new_per_day'),
        sub: tr('new_per_day_sub'),
        value: _newPerDay,
        min: 0,
        max: 100,
        step: 2,
        onChanged: (v) async {
          setState(() => _newPerDay = v);
          await _repo.setNewPerDay(v);
        },
      );

  Widget _maxReviewsTile(ColorScheme scheme) => _stepperTile(
        scheme,
        icon: Icons.repeat_rounded,
        label: tr('max_reviews'),
        sub: tr('max_reviews_sub'),
        value: _maxReviews,
        min: 10,
        max: 500,
        step: 10,
        onChanged: (v) async {
          setState(() => _maxReviews = v);
          await _repo.setMaxReviews(v);
        },
      );

  /// Плитка-степпер: подпись слева, − N + справа. С необязательным подзаголовком.
  Widget _stepperTile(
    ColorScheme scheme, {
    required IconData icon,
    required String label,
    String? sub,
    required int value,
    required int min,
    required int max,
    required int step,
    required Future<void> Function(int) onChanged,
  }) {
    return Padding(
      padding: EdgeInsets.zero,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Icon(icon, color: scheme.onSurfaceVariant),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label),
                    if (sub != null)
                      Text(
                        sub,
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.remove_circle_outline_rounded),
                onPressed:
                    value > min ? () => onChanged((value - step).clamp(min, max)) : null,
              ),
              // Ширины в 40 логических точек хватало на две цифры: «100» и
              // «500» ломались на строку «10» и строку «0».
              SizedBox(
                width: 58,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    value == 0 ? '∞' : '$value',
                    maxLines: 1,
                    softWrap: false,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: AppTheme.displayFont,
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                      color: scheme.onSurface,
                    ),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add_circle_outline_rounded),
                onPressed:
                    value < max ? () => onChanged((value + step).clamp(min, max)) : null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Целевое удержание: ползунок 80–97%. Выше — повторов больше, помнишь лучше.
  Widget _retentionTile(ColorScheme scheme) {
    final pct = (_retention * 100).round();
    return Padding(
      padding: EdgeInsets.zero,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.track_changes_rounded,
                      color: scheme.onSurfaceVariant),
                  const SizedBox(width: 16),
                  Expanded(child: Text(tr('retention_target'))),
                  Text(
                    '$pct%',
                    style: TextStyle(
                      fontFamily: AppTheme.displayFont,
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                      color: scheme.onSurface,
                    ),
                  ),
                ],
              ),
              Slider(
                value: _retention.clamp(0.80, 0.97),
                min: 0.80,
                max: 0.97,
                divisions: 17,
                label: '$pct%',
                onChanged: (v) => setState(() => _retention = v),
                onChangeEnd: (v) => _repo.setRequestRetention(v),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 40, bottom: 6),
                child: Text(
                  tr('retention_sub'),
                  style:
                      TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Оптимизация персональных весов FSRS по накопленным повторам.
  Widget _optimizeTile(ColorScheme scheme) {
    final ready = _reviewEvents >= FsrsOptimizer.minTotal;
    return Padding(
      padding: EdgeInsets.zero,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Icon(Icons.tune_rounded, color: scheme.onSurfaceVariant),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr('optimize_fsrs')),
                    Text(
                      _customWeights
                          ? tr('optimize_active')
                          : trf('optimize_progress',
                              {'n': _reviewEvents, 'need': FsrsOptimizer.minTotal}),
                      style: TextStyle(
                          fontSize: 12, color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              if (_customWeights)
                TextButton(
                  onPressed: _optimizing ? null : _resetFsrs,
                  child: Text(tr('reset')),
                ),
              _optimizing
                  ? const Padding(
                      padding: EdgeInsets.all(8),
                      child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  : FilledButton.tonal(
                      onPressed: ready ? _optimizeFsrs : null,
                      child: Text(tr('optimize_run')),
                    ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _optimizeFsrs() async {
    setState(() => _optimizing = true);
    final events = await _repo.reviewEvents();
    final result = FsrsOptimizer.optimize(events);

    // Подогнанные веса применяем, только если на СОБСТВЕННОЙ истории они
    // предсказывают точнее дефолтных. Иначе «персонализация» — это подкрутка
    // вслепую, а расплачивается за неё расписание.
    final retention = Fsrs.instance.requestRetention;
    final before =
        ScheduleLab.evaluate(events, weights: null, retention: retention);
    final after = ScheduleLab.evaluate(
      events,
      weights: result.weights,
      retention: retention,
    );
    final gain = ScheduleLab.improvementPercent(before, after);
    final applied =
        result.enough && ScheduleLab.worthApplying(before, after);

    if (applied) await _repo.setFsrsWeights(result.weights);
    if (!mounted) return;
    setState(() {
      _optimizing = false;
      _customWeights = applied || _customWeights;
    });

    final String msg;
    if (applied) {
      msg = trf('optimize_done_gain', {
        'r': '${(result.measuredRetention * 100).round()}',
        'g': gain.toStringAsFixed(1),
      });
    } else if (result.enough) {
      msg = tr('optimize_no_gain');
    } else {
      msg = tr('optimize_need_more');
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _resetFsrs() async {
    await _repo.setFsrsWeights(null);
    if (!mounted) return;
    setState(() => _customWeights = false);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(tr('optimize_reset_done'))));
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
      final json = await BackupService.exportJson();
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
        ).showSnackBar(SnackBar(content: Text(tr('backup_failed'))));
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
          SnackBar(content: Text(tr('export_failed'))),
        );
      }
    }
  }

  /// Путь выбранного файла. `.single` бросает StateError на пустом списке
  /// (бывает при отмене на некоторых платформах) — берём безопасно.
  String? _pickedPath(FilePickerResult? result) {
    final files = result?.files ?? const <PlatformFile>[];
    return files.isEmpty ? null : files.first.path;
  }

  /// Блок доната: короткий текст и две крупные кнопки.
  ///
  /// Стоит НАД «О приложении» и ниже покупки Pro: сначала приложение
  /// предлагает то, за что просит денег, и только потом — помочь просто так.
  /// Перенесён из Kadr, ссылки те же (автор один).
  Widget _donationCard(ColorScheme scheme) {
    return Card(
      margin: EdgeInsets.zero,
      color: scheme.primaryContainer.withValues(alpha: 0.35),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.volunteer_activism_rounded,
                    color: scheme.primary, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    tr('support_authors'),
                    style: TextStyle(
                      fontFamily: AppTheme.displayFont,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      color: scheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              tr('support_intro'),
              style: TextStyle(
                fontSize: 13,
                height: 1.35,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => _openDonation(kBoostyUrl),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: const StadiumBorder(),
              ),
              icon: const Icon(Icons.favorite_rounded, size: 19),
              label: const Text('Boosty',
                  style: TextStyle(
                      fontFamily: AppTheme.displayFont,
                      fontWeight: FontWeight.w700,
                      fontSize: 15)),
            ),
            const SizedBox(height: 10),
            FilledButton.tonalIcon(
              onPressed: () => _openDonation(kDonationAlertsUrl),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: const StadiumBorder(),
              ),
              icon: const Icon(Icons.card_giftcard_rounded, size: 19),
              label: const Text('DonationAlerts',
                  style: TextStyle(
                      fontFamily: AppTheme.displayFont,
                      fontWeight: FontWeight.w700,
                      fontSize: 15)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openDonation(Uri url) async {
    HapticFeedback.selectionClick();
    try {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('open_link_failed'))),
      );
    }
  }

  /// Секция «Fern Pro»: статус покупки и то, чем её открыть.
  ///
  /// Куплено — показываем номер лицензии: по нему поддержка находит покупку,
  /// а человек видит, что приложение помнит его оплату.
  List<Widget> _proTiles(ColorScheme scheme) {
    final license = LicenseService.instance.info;
    if (Pro.active) {
      return [
        _infoTile(
          icon: Icons.verified_rounded,
          title: tr('pro_active'),
          // У именного ключа показываем, на кого он выдан: увидев свою почту
          // рядом с номером, человек понимает, что ключ его личный.
          subtitle: LicenseInfo.maskEmail(license?.email),
          trailing: license == null
              ? ''
              : trf('pro_license_num', {'id': '${license.id}'}),
          scheme: scheme,
        ),
        if (license != null)
          _actionTile(
            icon: Icons.link_off_rounded,
            title: tr('pro_remove_key'),
            onTap: () async {
              await LicenseService.instance.clear();
              if (mounted) setState(() {});
            },
            scheme: scheme,
          ),
      ];
    }
    return [
      _actionTile(
        icon: Icons.auto_awesome_rounded,
        title: tr('pro_title'),
        // Остаток видно заранее: прежде о лимите узнавали, только упёршись
        // в него, и это читалось как поломка.
        subtitle: Pro.freeSourcesLeft > 0
            ? trf('pro_free_left', {'n': Pro.freeSourcesLeft})
            : tr('pro_free_none'),
        onTap: () async {
          await ProSheet.show(context);
          if (mounted) setState(() {});
        },
        scheme: scheme,
      ),
      if (kPlayBuild)
        _actionTile(
          icon: Icons.restore_rounded,
          title: tr('pro_restore'),
          onTap: () => BillingService.instance.restore(),
          scheme: scheme,
        ),
    ];
  }

  /// Импорт колоды из Anki (.apkg) или текстового списка (CSV/TSV/TXT).
  Future<void> _importDeck() async {
    if (!await requirePro(context, ProFeature.deckImport)) return;
    if (!mounted) return;
    String? path;
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: DeckImport.supportedExtensions,
      );
      path = _pickedPath(result);
    } catch (_) {
      final result = await FilePicker.platform.pickFiles(type: FileType.any);
      path = _pickedPath(result);
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
  }

  /// Ручная проверка обновления: показывает меню обновления или сообщает, что
  /// установлена последняя версия.
  Future<void> _checkUpdates() async {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('checking_updates'))),
      );
    }
    final message = await StoreUpdate.checkManually(context);
    if (!mounted || message == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _restore() async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.any);
      final path = _pickedPath(result);
      if (path == null || !mounted) return;
      final merge = await _askRestoreMode();
      if (merge == null) return; // отменили выбор режима
      final raw = await File(path).readAsString();
      await BackupService.restore(raw, merge: merge);
      await _theme.load();
      await _locale.load();
      await LanguageRegistry.instance.load();
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

  /// Полное удаление данных (как свежая установка) — с подтверждением.
  Future<void> _wipeAllData() async {
    final scheme = Theme.of(context).colorScheme;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.warning_amber_rounded, color: scheme.error),
        title: Text(tr('wipe_data')),
        content: Text(tr('wipe_data_confirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: scheme.error,
              foregroundColor: scheme.onError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('wipe_data_btn')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    // Стираем библиотеку (файлы), затем БД+настройки, затем — как свежий старт.
    await SourceLibrary.instance.wipeAll();
    await _repo.wipeAllData();
    await LanguageRegistry.instance.load();
    await _repo.seedDemoIfNeeded();
    await _repo.applyFsrsSettings();
    await _theme.load();
    await _locale.load();
    await ReaderSettings.instance.load();
    await _loadInfo();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(tr('wipe_data_done'))));
    // На корень — экраны перечитают свежие данные.
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  /// Спрашивает стратегию восстановления. true — объединить, false — заменить
  /// всё, null — пользователь закрыл диалог.
  Future<bool?> _askRestoreMode() async {
    final scheme = Theme.of(context).colorScheme;
    return showModalBottomSheet<bool>(
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
            Text(tr('restore_mode_title'),
                style: Theme.of(ctx).textTheme.titleMedium),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.merge_rounded),
              title: Text(tr('restore_mode_merge')),
              subtitle: Text(tr('restore_mode_merge_sub')),
              onTap: () => Navigator.pop(ctx, true),
            ),
            ListTile(
              leading: const Icon(Icons.sync_rounded),
              title: Text(tr('restore_mode_replace')),
              subtitle: Text(tr('restore_mode_replace_sub')),
              onTap: () => Navigator.pop(ctx, false),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ------------------------------- Строительные блоки -------------------------------

  /// Секция настроек: заголовок с иконкой над общим блоком пунктов.
  ///
  /// До этого каждый пункт был отдельной карточкой, и экран рассыпался на два
  /// десятка плиток — глазу не за что зацепиться, а границы смысловых групп
  /// читались только по заголовкам. Теперь группа выглядит группой: один
  /// контейнер, пункты внутри разделены линиями.
  ///
  /// Секции сворачиваются: их восемь, и до «О приложении» приходилось
  /// пролистывать весь экран. Состояние живёт только пока экран открыт —
  /// запоминать его между заходами значит прятать от человека настройки,
  /// которые он свернул однажды и забыл.
  Widget _section({
    required String id,
    required String title,
    required IconData icon,
    required ColorScheme scheme,
    required List<Widget> children,
  }) {
    if (children.isEmpty) return const SizedBox.shrink();
    final collapsed = _collapsed.contains(id);

    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) {
        rows.add(Divider(
          height: 1,
          thickness: 1,
          // Отступ слева — под иконку пункта: линия отделяет тексты, а не
          // режет колонку иконок пополам.
          indent: 56,
          endIndent: 0,
          color: scheme.outlineVariant.withValues(alpha: .5),
        ));
      }
      rows.add(children[i]);
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() {
              collapsed ? _collapsed.remove(id) : _collapsed.add(id);
            }),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(6, 4, 6, 10),
              child: Row(
                children: [
                  Icon(icon, size: 20, color: scheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontFamily: AppTheme.displayFont,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                  AnimatedRotation(
                    turns: collapsed ? 0 : 0.5,
                    duration: const Duration(milliseconds: 180),
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // AnimatedSize, а не AnimatedCrossFade: тот держит в дереве обе
          // половины, и свёрнутые пункты остаются доступны — для поиска, для
          // скринридера и для тестов они никуда не делись.
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: collapsed
                ? const SizedBox(width: double.infinity)
                : Material(
                    color: scheme.surfaceContainer,
                    borderRadius: BorderRadius.circular(20),
                    clipBehavior: Clip.antiAlias,
                    child: Column(children: rows),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _switchTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    required ColorScheme scheme,
  }) {
    return Padding(
      padding: EdgeInsets.zero,
      child: Material(
        color: Colors.transparent,
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
    Color? color,
  }) {
    return Padding(
      padding: EdgeInsets.zero,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          leading: Icon(icon, color: color ?? scheme.onSurfaceVariant),
          title: Text(title,
              style: color == null ? null : TextStyle(color: color)),
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
    String? subtitle,
  }) {
    return Padding(
      padding: EdgeInsets.zero,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          leading: Icon(icon, color: scheme.onSurfaceVariant),
          title: Text(title),
          subtitle: subtitle == null ? null : Text(subtitle),
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
