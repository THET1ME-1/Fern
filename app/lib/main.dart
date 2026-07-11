import 'dart:async' show unawaited;
import 'dart:io' show Platform;

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'decks_screen.dart';
import 'l10n/locale_controller.dart';
import 'l10n/strings.dart';
import 'library_screen.dart';
import 'onboarding_screen.dart';
import 'progress_screen.dart';
import 'services/backup_service.dart';
import 'services/deck_repository.dart';
import 'services/language_registry.dart';
import 'services/pos_dictionary.dart';
import 'services/notification_service.dart';
import 'services/translation/translation_manager.dart';
import 'services/update_service.dart';
import 'share/share_import.dart';
import 'settings_screen.dart';
import 'study/reader_settings.dart';
import 'theme/app_theme.dart';
import 'theme/theme_controller.dart';
import 'utils/app_version.dart';
import 'widgets/update_sheet.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  await DeckRepository.instance.init();
  await DeckRepository.instance.applyFsrsSettings();
  await ThemeController.instance.load();
  await LocaleController.instance.load();
  await LanguageRegistry.instance.load();
  await TranslationManager.instance.load();
  await ReaderSettings.instance.load();
  await DeckRepository.instance.seedDemoIfNeeded();
  await DeckRepository.instance.protectStreakIfNeeded();
  await _rescheduleReminderIfEnabled();
  final onboarded = await DeckRepository.instance.onboarded();
  runApp(FernApp(onboarded: onboarded));
  // Тихий авто-бэкап раз в сутки — после первого кадра, не задерживая запуск.
  unawaited(BackupService.autoBackupIfDue());
  // Фоновая загрузка словаря частей речи (чтобы теги новых слов были точными).
  unawaited(PosDictionary.instance.ensureLoaded('en'));
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
  const FernApp({super.key, this.onboarded = true});

  @override
  Widget build(BuildContext context) {
    final theme = ThemeController.instance;
    final locale = LocaleController.instance;
    return ListenableBuilder(
      listenable: Listenable.merge([theme, locale]),
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
            home: _RootGate(onboarded: onboarded),
          );
        },
      ),
    );
  }
}

/// Показывает онбординг на первом запуске, иначе — главный экран.
class _RootGate extends StatefulWidget {
  final bool onboarded;
  const _RootGate({required this.onboarded});

  @override
  State<_RootGate> createState() => _RootGateState();
}

class _RootGateState extends State<_RootGate> {
  late bool _onboarded = widget.onboarded;

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

  /// Тихая проверка обновления на GitHub при запуске. Если есть версия новее —
  /// показываем нижнее меню с предложением обновиться.
  Future<void> _checkForUpdate() async {
    // Только на реальных мобильных (не в тестах/на десктопе).
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) return;
    final current = await appVersionName();
    if (current.isEmpty) return;
    final info = await UpdateService.checkForUpdate(current);
    if (!mounted || info == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) UpdateSheet.show(context, info, current);
    });
  }

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
