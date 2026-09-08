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
import 'services/fern_account.dart';
import 'services/license_service.dart';
import 'services/revocation_feed.dart';
import 'services/pro.dart';
import 'services/subscription_service.dart';
import 'services/source_library.dart';
import 'services/deck_repository.dart';
import 'services/language_registry.dart';
import 'services/licenses.dart';
import 'services/pos_dictionary.dart';
import 'services/store_update.dart';
import 'services/notification_service.dart';
import 'services/translation/translation_manager.dart';
import 'services/quick_review.dart';
import 'services/process_text.dart';
import 'share/share_import.dart';
import 'settings_screen.dart';
import 'startup.dart';
import 'study/reader_settings.dart';
import 'study/session_screen.dart';
import 'study/study_models.dart';
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
  // Отозванные номера с прошлой загрузки — до проверки ключа, иначе отозванный
  // ключ прожил бы ещё один запуск.
  await _optional(StartupStep.license, () async {
    await RevocationFeed.applyStored();
    await LicenseService.instance.load();
  });
  await _optional(StartupStep.billing, BillingService.instance.load);
  // Аккаунт и подписка: сессия с диска и последний известный срок нужны до
  // первого кадра, иначе у подписчика мигнёт замок. За свежим талоном идём
  // фоном — сеть не должна задерживать запуск.
  await _optional(StartupStep.license, () async {
    await FernAccount.instance.init();
    await SubscriptionService.instance.load();
  });
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
  // Раз в трое суток забираем список отозванных лицензий. Ответа не ждём:
  // нет сети — остаётся тот список, что уже лежит на устройстве.
  unawaited(RevocationFeed.refresh());
  // Свежий талон подписки: раз в двадцать часов, не чаще.
  unawaited(SubscriptionService.instance.refreshIfStale());
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

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  static const int _tabCount = 4;
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkForUpdate();
    ShareImport.start(context); // приём «Поделиться» из других приложений
    // Fern в системном меню выделения текста: слово из чужого приложения
    // приходит сюда же, но за один тап вместо листа «Поделиться».
    ProcessText.start(context);
    // Ответы, данные из шторки, пока приложение было закрыто.
    unawaited(QuickReview.applyPending());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ShareImport.dispose();
    super.dispose();
  }

  /// Микроповтор кладётся в шторку, когда человек УХОДИТ из приложения, и
  /// снимается, когда возвращается.
  ///
  /// Так фича живёт без фоновых задач и точных будильников: карточка ждёт в
  /// шторке до следующего раза, и ответ на неё сохраняет серию в тот день,
  /// когда приложение не открывали вовсе.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
        unawaited(_postQuickReview());
      case AppLifecycleState.resumed:
        unawaited(NotificationService.instance.cancelQuickReview());
        unawaited(QuickReview.applyPending());
        // Человек мог уйти платить в браузер и вернуться: спрашиваем сервер,
        // не появилась ли подписка. Ходим не чаще раза в двадцать часов, а
        // сразу после оплаты лист сам опрашивает чаще.
        unawaited(SubscriptionService.instance.refreshIfStale());
      case AppLifecycleState.detached:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        break;
    }
  }

  Future<void> _postQuickReview() async {
    final repo = DeckRepository.instance;
    if (!await repo.quickReviewEnabled()) return;
    final lang = await repo.selectedLanguageCode() ?? 'en';
    final now = DateTime.now();
    // Берём самую просроченную карточку языка: спрашивать в шторке имеет смысл
    // то, что и так пора повторить.
    final due = [
      for (final c in repo.cardsForLanguageSync(lang))
        if (!c.review.isNew && !c.isRule && c.isDue(now)) c,
    ]..sort((a, b) => (a.review.due ?? now).compareTo(b.review.due ?? now));
    if (due.isEmpty) return;
    final card = due.first;
    await NotificationService.instance.showQuickReview(
      cardId: card.id,
      word: card.front,
      meaning: card.back,
    );
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

  /// Запуск повторов из дока: карточки берутся по всем колодам языка.
  ///
  /// Колода нужна сессии ради языка и направления, поэтому берём первую
  /// колоду языка; принадлежность карточки к своей колоде хранится в ней
  /// самой, и статистика от этого не съезжает.
  Future<void> _studyEverything() async {
    final repo = DeckRepository.instance;
    final lang = await repo.selectedLanguageCode() ?? 'en';
    final decks = repo.decks.where((d) => d.languageCode == lang).toList();
    if (decks.isEmpty) {
      _onItemTapped(0);
      return;
    }
    final cards = repo.cardsForLanguageSync(lang);
    if (cards.isEmpty) {
      _onItemTapped(0);
      return;
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SessionScreen(
          deck: decks.first,
          mode: StudyMode.learn,
          cards: cards,
          reload: () async => repo.cardsForLanguageSync(lang),
        ),
      ),
    );
    if (mounted) setState(() {});
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
      // Док висит над содержимым, а не отрезает его полосой: список виден до
      // самого низа. Панель разделов — таблетка, действие рядом квадратом.
      extendBody: true,
      bottomNavigationBar: _FernDock(
        selectedIndex: _selectedIndex,
        onTap: _onItemTapped,
        onStudy: _studyEverything,
        items: [
          _NavItem(Icons.style_outlined, Icons.style_rounded, tr('tab_decks')),
          _NavItem(Icons.auto_stories_outlined, Icons.auto_stories_rounded,
              tr('library_title')),
          _NavItem(Icons.insights_outlined, Icons.insights_rounded,
              tr('progress_title')),
          _NavItem(Icons.settings_outlined, Icons.settings_rounded,
              tr('settings_title')),
        ],
      ),
    );
  }
}

/// Описание пункта нижней навигации: иконка-контур, иконка-заливка и подпись.
class _NavItem {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  const _NavItem(this.icon, this.selectedIcon, this.label);
}

/// Док: таблетка разделов и квадратная кнопка повторов рядом.
///
/// Панель во всю ширину кончалась стеной — список обрывался ровной полосой.
/// Здесь док висит над содержимым, разделы держат ряд целиком, а действие
/// стоит отдельным квадратом в высоту ряда: ширина разделов больше не зависит
/// от длины слова на кнопке.
class _FernDock extends StatefulWidget {
  final int selectedIndex;
  final ValueChanged<int> onTap;
  final Future<void> Function() onStudy;
  final List<_NavItem> items;

  const _FernDock({
    required this.selectedIndex,
    required this.onTap,
    required this.onStudy,
    required this.items,
  });

  /// Высота ряда. Прежние 72 держали подпись под каждой иконкой; здесь
  /// подпись есть только у выбранного, и 64 хватает — ниже 56 палец начинает
  /// промахиваться.
  static const double height = 64;

  @override
  State<_FernDock> createState() => _FernDockState();
}

class _FernDockState extends State<_FernDock> {
  int _due = 0;

  @override
  void initState() {
    super.initState();
    DeckRepository.instance.addListener(_recount);
    _recount();
  }

  @override
  void dispose() {
    DeckRepository.instance.removeListener(_recount);
    super.dispose();
  }

  /// Сколько карточек Fern отдаст прямо сейчас: просроченные повторы плюс
  /// новые в пределах дневного лимита. Та же арифметика, что на главном
  /// экране, — два разных числа в двух местах человек читает как ошибку.
  Future<void> _recount() async {
    final repo = DeckRepository.instance;
    final lang = await repo.selectedLanguageCode() ?? 'en';
    final allowed = await repo.newAllowedNow();
    final now = DateTime.now();
    var due = 0, fresh = 0;
    for (final c in repo.cardsForLanguageSync(lang)) {
      if (c.review.isNew) {
        fresh++;
      } else if (c.isDue(now)) {
        due++;
      }
    }
    final total = due + (fresh < allowed ? fresh : allowed);
    if (!mounted || total == _due) return;
    setState(() => _due = total);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ready = _due > 0;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: SizedBox(
          height: _FernDock.height,
          child: Row(
            children: [
              Expanded(
                child: Material(
                  color: scheme.surfaceContainerHigh,
                  // Таблетка: край скруглён целиком, как у кнопок приложения.
                  borderRadius: BorderRadius.circular(_FernDock.height / 2),
                  clipBehavior: Clip.antiAlias,
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: LayoutBuilder(
                      builder: (context, c) {
                        final width = c.maxWidth / widget.items.length;
                        return Stack(
                          children: [
                            // Метка ЕДЕТ к выбранному разделу, а не гаснет и
                            // зажигается: движение читается одним предметом.
                            AnimatedPositioned(
                              duration: const Duration(milliseconds: 440),
                              curve: AppTheme.emphasized,
                              left: width * widget.selectedIndex,
                              top: 0,
                              bottom: 0,
                              width: width,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: scheme.secondaryContainer,
                                  borderRadius: BorderRadius.circular(18),
                                ),
                              ),
                            ),
                            Row(
                              children: [
                                for (var i = 0; i < widget.items.length; i++)
                                  Expanded(
                                    child: _DockTab(
                                      item: widget.items[i],
                                      selected: i == widget.selectedIndex,
                                      onTap: () => widget.onTap(i),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Квадрат со скруглёнными углами: у действия своя форма, и оно
              // не читается пятым разделом.
              SizedBox(
                width: _FernDock.height,
                child: Material(
                  color: ready ? scheme.primary : scheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(22),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      widget.onStudy();
                    },
                    child: Stack(
                      children: [
                        Center(
                          child: Icon(
                            ready
                                ? Icons.play_arrow_rounded
                                : Icons.check_rounded,
                            size: 28,
                            color: ready
                                ? scheme.onPrimary
                                : scheme.onSecondaryContainer,
                          ),
                        ),
                        // Число висит значком на кнопке: объём видно, а ширины
                        // разделов это не стоит.
                        if (ready)
                          Positioned(
                            top: 6,
                            right: 6,
                            child: Container(
                              constraints: const BoxConstraints(minWidth: 20),
                              height: 20,
                              padding: const EdgeInsets.symmetric(horizontal: 5),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: scheme.surface,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                _due > 99 ? '99+' : '$_due',
                                style: TextStyle(
                                  fontFamily: AppTheme.bodyFont,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 11,
                                  height: 1,
                                  color: scheme.primary,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
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

/// Раздел внутри таблетки: иконка и подпись под ней.
class _DockTab extends StatelessWidget {
  final _NavItem item;
  final bool selected;
  final VoidCallback onTap;

  const _DockTab({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color =
        selected ? scheme.onSecondaryContainer : scheme.onSurfaceVariant;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(selected ? item.selectedIcon : item.icon, size: 22, color: color),
          const SizedBox(height: 2),
          // Подпись не переносится: длинная обрезается, а иконка остаётся на
          // месте — на 320 dp разделу достаётся около семидесяти точек.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Text(
              item.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: AppTheme.bodyFont,
                fontWeight: FontWeight.w600,
                fontSize: 9.5,
                height: 1.1,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
