import 'dart:async' show unawaited;

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'decks_screen.dart';
import 'l10n/locale_controller.dart';
import 'l10n/strings.dart';
import 'library_screen.dart';
import 'onboarding_screen.dart';
import 'progress_screen.dart';
import 'recovery_screen.dart';
import 'services/backup_service.dart';
import 'services/billing_service.dart';
import 'services/card_images.dart';
import 'services/license_service.dart';
import 'services/pro.dart';
import 'services/source_library.dart';
import 'services/deck_repository.dart';
import 'services/language_registry.dart';
import 'services/licenses.dart';
import 'services/pos_dictionary.dart';
import 'services/store_update.dart';
import 'services/notification_service.dart';
import 'services/translation/translation_manager.dart';
import 'share/share_import.dart';
import 'settings_screen.dart';
import 'startup.dart';
import 'study/reader_settings.dart';
import 'theme/app_theme.dart';
import 'theme/theme_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  try {
    await startFern();
  } on StartupError catch (e) {
    // Битый файл БД или переполненный диск роняли запуск ДО runApp — приложение
    // навсегда оставалось чёрным экраном, и данные было не достать даже из
    // бэкапа. Показываем экран восстановления вместо пустоты.
    runApp(RecoveryApp(failure: e));
  } catch (e) {
    runApp(RecoveryApp(failure: StartupError(StartupStep.storage, e)));
  }
}

/// Полная инициализация и запуск приложения. Вынесена, чтобы экран
/// восстановления мог повторить её после починки хранилища.
Future<void> startFern() async {
  registerAssetLicenses();
  // Словарь — единственный шаг, без которого запускаться незачем. Всё
  // остальное приложение переживает: тема откатится к дефолтной, язык — к
  // системному, напоминания просто не встанут. Раньше любой из этих шагов
  // ронял запуск целиком и человеку предлагали стереть словарь.
  try {
    await DeckRepository.instance.init();
    await DeckRepository.instance.applyFsrsSettings();
  } catch (e) {
    throw StartupError(StartupStep.storage, e);
  }

  await _optional(StartupStep.theme, ThemeController.instance.load);
  await _optional(StartupStep.locale, LocaleController.instance.load);
  await _optional(StartupStep.languages, LanguageRegistry.instance.load);
  await _optional(StartupStep.translation, TranslationManager.instance.load);
  await _optional(StartupStep.reader, ReaderSettings.instance.load);
  // Каталог картинок карточек — до первого кадра, чтобы экраны строили путь
  // к файлу синхронно, без мигания пустого места.
  await _optional(StartupStep.cardImages, CardImages.init);
  // Pro: ключ проверяется на устройстве, покупка в магазине подтягивается
  // фоном — оба источника должны быть известны до первого кадра, иначе
  // библиотека мигнёт замком у того, кто уже заплатил.
  await _optional(StartupStep.license, LicenseService.instance.load);
  await _optional(StartupStep.billing, BillingService.instance.load);
  await _optional(StartupStep.seed, () async {
    // Разовый перенос: у тех, кто разобрал свою книгу до появления счётчика
    // бесплатных разборов, он пуст — обновление не должно дарить лишнюю книгу.
    await Pro.migrateFromLibrary((await SourceLibrary.instance.list()).length);
    await DeckRepository.instance.seedDemoIfNeeded();
    // Чинит колоды, посеянные на другом языке интерфейса (в т.ч. у тех, кто
    // менял язык в прошлых версиях, где переводы фиксировались намертво).
    await DeckRepository.instance.relocalizeBuiltIns();
    await DeckRepository.instance.protectStreakIfNeeded();
  });
  await _optional(StartupStep.reminders, _rescheduleReminderIfEnabled);

  var onboarded = true;
  try {
    onboarded = await DeckRepository.instance.onboarded();
  } catch (e) {
    debugPrint('Не прочитали флаг онбординга: $e');
  }
  runApp(FernApp(onboarded: onboarded, issues: _startupIssues));
  // Тихий авто-бэкап раз в сутки — после первого кадра, не задерживая запуск.
  unawaited(BackupService.autoBackupIfDue());
  // Фоновая загрузка словаря частей речи (чтобы теги новых слов были точными).
  unawaited(PosDictionary.instance.ensureLoaded('en'));
}

/// Шаги запуска, которые не поднялись. Приложение работает и без них, но
/// человек должен знать, что именно недосчиталось: «пропали настройки» без
/// объяснения выглядит как потеря данных.
final List<StartupError> _startupIssues = [];

/// Выполняет необязательный шаг запуска. Отказ записывается и не мешает
/// остальным: одна не поднявшаяся мелочь не стоит чёрного экрана.
Future<void> _optional(StartupStep step, Future<void> Function() run) async {
  try {
    await run();
  } catch (e) {
    _startupIssues.add(StartupError(step, e));
    debugPrint('Шаг запуска «${step.name}» не поднялся: $e');
  }
}

/// Перепланирует ежедневное напоминание на старте (на случай обновления
/// приложения/смены языка). Тихо пропускается, если напоминание выключено или
/// платформа не поддерживает уведомления.
Future<void> _rescheduleReminderIfEnabled() async {
  final repo = DeckRepository.instance;
  if (!await repo.reminderEnabled()) return;
  await NotificationService.instance.scheduleDaily(
    hour: await repo.reminderHour(),
    minute: await repo.reminderMinute(),
    title: tr('reminder_push_title'),
    body: tr('reminder_push_body'),
  );
}

class FernApp extends StatelessWidget {
  final bool onboarded;

  /// Шаги запуска, которые не поднялись (обычно пусто).
  final List<StartupError> issues;

  const FernApp({super.key, this.onboarded = true, this.issues = const []});

  @override
  Widget build(BuildContext context) {
    final theme = ThemeController.instance;
    final locale = LocaleController.instance;
    return ListenableBuilder(
      listenable: Listenable.merge([theme, locale, Pro.changes]),
      builder: (context, _) => DynamicColorBuilder(
        builder: (lightDynamic, darkDynamic) {
          final useDyn =
              theme.useDynamicColor &&
              lightDynamic != null &&
              darkDynamic != null;
          final seed = useDyn ? lightDynamic.primary : theme.seedColor;
          return MaterialApp(
            title: 'Fern',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(seed),
            darkTheme: AppTheme.dark(seed, amoled: theme.amoled),
            themeMode: theme.themeMode,
            locale: locale.locale,
            supportedLocales: LocaleController.supported,
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: _RootGate(onboarded: onboarded, issues: issues),
          );
        },
      ),
    );
  }
}

/// Показывает онбординг на первом запуске, иначе — главный экран.
class _RootGate extends StatefulWidget {
  final bool onboarded;
  final List<StartupError> issues;
  const _RootGate({required this.onboarded, this.issues = const []});

  @override
  State<_RootGate> createState() => _RootGateState();
}

class _RootGateState extends State<_RootGate> {
  late bool _onboarded = widget.onboarded;

  @override
  void initState() {
    super.initState();
    if (widget.issues.isEmpty) return;
    // Молча стартовать с половиной настроек нечестно: человек решит, что
    // настройки слетели сами. Называем, что именно не поднялось.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ru = LocaleController.instance.code == 'ru';
      final parts =
          widget.issues.map((e) => e.step.title(ru: ru)).toSet().join(', ');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(trf('startup_failed_parts', {'list': parts})),
        duration: const Duration(seconds: 8),
        action: SnackBarAction(
          label: tr('details'),
          onPressed: () => showDialog<void>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text(tr('startup_failed_title')),
              content: SingleChildScrollView(
                child: SelectableText(
                  widget.issues
                      .map((e) => '${e.step.title(ru: ru)}\n${e.cause}')
                      .join('\n\n'),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(tr('close')),
                ),
              ],
            ),
          ),
        ),
      ));
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_onboarded) return const MainScreen();
    return OnboardingScreen(
      onDone: () => setState(() => _onboarded = true),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  static const int _tabCount = 4;
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _checkForUpdate();
    ShareImport.start(context); // приём «Поделиться» из других приложений
  }

  @override
  void dispose() {
    ShareImport.dispose();
    super.dispose();
  }

  /// Тихая проверка обновления при запуске. Канал зависит от сборки: GitHub —
  /// свой апдейтер, Google Play — обновление силами магазина.
  Future<void> _checkForUpdate() => StoreUpdate.checkOnStart(context);

  Widget _screenFor(int index) {
    switch (index) {
      case 1:
        return const LibraryScreen();
      case 2:
        return const ProgressScreen();
      case 3:
        return const SettingsScreen();
      case 0:
      default:
        return const DecksScreen();
    }
  }

  void _onItemTapped(int index) {
    if (index >= 0 && index < _tabCount) {
      HapticFeedback.selectionClick();
      setState(() => _selectedIndex = index);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screenFor(_selectedIndex),
      bottomNavigationBar: _CircleNavBar(
        selectedIndex: _selectedIndex,
        onTap: _onItemTapped,
        items: const [
          _NavItem(Icons.style_outlined, Icons.style_rounded),
          _NavItem(Icons.auto_stories_outlined, Icons.auto_stories_rounded),
          _NavItem(Icons.insights_outlined, Icons.insights_rounded),
          _NavItem(Icons.settings_outlined, Icons.settings_rounded),
        ],
      ),
    );
  }
}

/// Описание пункта нижней навигации: иконка-контур и иконка-заливка.
class _NavItem {
  final IconData icon;
  final IconData selectedIcon;
  const _NavItem(this.icon, this.selectedIcon);
}

/// Нижняя навигация в духе M3, но индикатор активного пункта — РОВНЫЙ КРУГ
/// (а не «таблетка»). Круг плавно «переезжает», иконка контур→заливка.
class _CircleNavBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onTap;
  final List<_NavItem> items;

  const _CircleNavBar({
    required this.selectedIndex,
    required this.onTap,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainer,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 72,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (var i = 0; i < items.length; i++)
                Expanded(
                  child: _CircleNavButton(
                    item: items[i],
                    selected: i == selectedIndex,
                    onTap: () => onTap(i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CircleNavButton extends StatelessWidget {
  final _NavItem item;
  final bool selected;
  final VoidCallback onTap;

  const _CircleNavButton({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const double d = 54;
    return InkResponse(
      onTap: onTap,
      radius: 40,
      containedInkWell: true,
      customBorder: const CircleBorder(),
      child: Center(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          width: d,
          height: d,
          decoration: BoxDecoration(
            color: selected ? scheme.primaryContainer : Colors.transparent,
            shape: BoxShape.circle,
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            transitionBuilder: (child, anim) => ScaleTransition(
              scale: Tween<double>(begin: 0.7, end: 1).animate(anim),
              child: FadeTransition(opacity: anim, child: child),
            ),
            child: Icon(
              selected ? item.selectedIcon : item.icon,
              key: ValueKey(selected),
              size: 28,
              color: selected
                  ? scheme.onPrimaryContainer
                  : scheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}
