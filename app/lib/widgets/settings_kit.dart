import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../theme/app_theme.dart';

/// Кирпичи экрана настроек: круглый чип-иконка, блок пункта и появление
/// каскадом.
///
/// Раньше секция была одной карточкой, внутри которой пункты разделялись
/// линией, а иконки стояли голыми. Линия режет колонку иконок, а голая иконка
/// теряется на длинном списке: глазу не за что зацепиться при прокрутке.
/// Теперь каждый пункт — свой блок с зазором, иконка сидит в цветном круге, и
/// секция читается набором предметов, а не простынёй.
///
/// Приём перенесён из Togetherly (`settings_scaffold.dart`) вместе с его
/// правилами: форму блока задаёт место в группе, а появление считается по
/// прокрутке — без единого таймера, иначе виджет-тесты падают на «pending
/// timers».

/// Круглая подложка под иконку пункта.
class SettingsIconChip extends StatelessWidget {
  final IconData icon;
  final Color? background;
  final Color? foreground;

  /// Размер круга. Сорок четыре точки — столько же, сколько у чипа Togetherly:
  /// меньше сорока круг перестаёт читаться как предмет, больше — начинает
  /// спорить с заголовком.
  static const double size = 44;

  const SettingsIconChip(this.icon,
      {super.key, this.background, this.foreground});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background ?? scheme.primaryContainer,
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: 22, color: foreground ?? scheme.onPrimaryContainer),
    );
  }
}

/// Радиусы и зазоры группы пунктов.
abstract final class SettingsShape {
  /// Внешние углы группы — те же, что были у прежней карточки секции.
  static const double outer = 24;

  /// Углы внутри группы: блоки читаются одним разделом, а не россыпью.
  static const double inner = 8;

  /// Зазор между блоками. Он заменил разделительную линию.
  static const double gap = 4;

  /// Форма блока по его месту в группе.
  static BorderRadius radius(int index, int count) => BorderRadius.vertical(
        top: Radius.circular(index == 0 ? outer : inner),
        bottom: Radius.circular(index == count - 1 ? outer : inner),
      );
}

/// Блок встаёт на место, когда экран доезжает до него.
///
/// Ни одного таймера: положение считается по прокрутке и по анимации маршрута.
/// `Future.delayed` пережил бы конец виджет-теста и уронил бы чужие прогоны.
class AppearInList extends StatefulWidget {
  const AppearInList({
    super.key,
    required this.child,
    this.index = 0,
    this.offset = 20,
  });

  final Widget child;

  /// Место в группе: по нему считается задержка каскада.
  final int index;

  /// Путь снизу вверх, в логических точках.
  final double offset;

  @override
  State<AppearInList> createState() => _AppearInListState();
}

class _AppearInListState extends State<AppearInList>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  bool _started = false;
  ScrollPosition? _position;
  Animation<double>? _routeAnim;
  late final DateTime _born;

  /// Пружина движения: та же, что у прочих появлений в приложении.
  static final SpringDescription _spring =
      SpringDescription.withDampingRatio(mass: 1, stiffness: 320, ratio: 0.92);

  /// Насколько «ниже нуля» стартует соседний блок. Отрицательное значение и
  /// есть задержка каскада, только без таймера.
  static const double _staggerStep = 0.13;

  /// Дальше пятого блока каскад не растёт: иначе низ списка ждал бы секунду.
  static const int _staggerCap = 5;

  /// После этого окна появление считается прокруткой, а не заходом на экран.
  static const Duration _window = Duration(milliseconds: 400);

  @override
  void initState() {
    super.initState();
    _born = DateTime.now();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
      // Ниже нуля — пауза каскада, выше единицы — перелёт пружины.
      lowerBound: -_staggerStep * _staggerCap,
      upperBound: 1.06,
      value: 0,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _position?.removeListener(_check);
    _position = Scrollable.maybeOf(context)?.position;
    _position?.addListener(_check);
    _routeAnim?.removeListener(_check);
    _routeAnim = ModalRoute.of(context)?.animation;
    _routeAnim?.addListener(_check);
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  @override
  void dispose() {
    _position?.removeListener(_check);
    _routeAnim?.removeListener(_check);
    _ctrl.dispose();
    super.dispose();
  }

  void _check() {
    if (_started || !mounted) return;
    // Ни прокрутки, ни анимации маршрута — ждать нечего: показываем сразу.
    // Иначе блок остался бы прозрачным навсегда, а нажатия при этом проходят.
    if (_position == null && _routeAnim == null) {
      _started = true;
      _run(0);
      return;
    }
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final top = box.localToGlobal(Offset.zero).dy;
    final bottom = top + box.size.height;
    final screen = MediaQuery.sizeOf(context).height;
    if (screen > 0 && (top >= screen || bottom <= 0)) return;

    _started = true;
    _position?.removeListener(_check);
    _routeAnim?.removeListener(_check);
    // Каскад достаётся только тому, что было на экране с самого начала:
    // долистанный снизу блок появляется без ожидания, иначе прокрутка
    // выглядит залипающей.
    final scrolled = DateTime.now().difference(_born) > _window;
    final steps = scrolled ? 0 : widget.index.clamp(0, _staggerCap);
    _run(-_staggerStep * steps);
  }

  void _run(double from) {
    if (!mounted) return;
    // Системный запрет анимаций уважаем: блок просто оказывается на месте.
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _ctrl.value = 1;
      return;
    }
    _ctrl.animateWith(SpringSimulation(_spring, from, 1, 0));
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, child) {
          final t = _ctrl.value < 0 ? 0.0 : _ctrl.value;
          return Opacity(
            // Прозрачность догоняет раньше движения: на перелёте блок уже
            // непрозрачен, иначе он мигал бы у самой точки остановки.
            opacity: t < 0.55 ? (t / 0.55).clamp(0.0, 1.0) : 1.0,
            child: Transform.translate(
              offset: Offset(0, widget.offset * (1 - t)),
              child: child,
            ),
          );
        },
        child: widget.child,
      ),
    );
  }
}

/// Цвет чипов внутри секции.
///
/// Секции различаются тоном круга: глаз цепляется за цвет раньше, чем читает
/// подпись, и «Оформление» отличается от «Данных» до всякого чтения. Цвет
/// приходит от секции, поэтому вызовы плиток не меняются.
class SettingsTone extends InheritedWidget {
  final Color background;
  final Color foreground;

  const SettingsTone({
    super.key,
    required this.background,
    required this.foreground,
    required super.child,
  });

  static SettingsTone? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SettingsTone>();

  @override
  bool updateShouldNotify(SettingsTone old) =>
      background != old.background || foreground != old.foreground;

  /// Тон секции по её имени. Незнакомая секция получает акцент — так новый
  /// раздел выглядит своим ещё до того, как ему подберут цвет.
  static (Color, Color) forSection(String id, ColorScheme scheme) =>
      switch (id) {
        'appearance' => (scheme.tertiaryContainer, scheme.onTertiaryContainer),
        'study' => (scheme.primaryContainer, scheme.onPrimaryContainer),
        'home' => (scheme.secondaryContainer, scheme.onSecondaryContainer),
        'reminders' => (scheme.tertiaryContainer, scheme.onTertiaryContainer),
        'language' => (scheme.secondaryContainer, scheme.onSecondaryContainer),
        'data' => (scheme.surfaceContainerHighest, scheme.onSurfaceVariant),
        'pro' => (scheme.primaryContainer, scheme.onPrimaryContainer),
        'about' => (scheme.surfaceContainerHighest, scheme.onSurfaceVariant),
        _ => (scheme.primaryContainer, scheme.onPrimaryContainer),
      };
}

/// Заголовок пункта: шрифт заголовков, чуть крупнее прежнего.
TextStyle settingsTitleStyle(ColorScheme scheme, {Color? color}) => TextStyle(
      fontFamily: AppTheme.bodyFont,
      fontWeight: FontWeight.w600,
      fontSize: 15,
      height: 1.25,
      color: color ?? scheme.onSurface,
    );

/// Подпись под заголовком.
TextStyle settingsSubtitleStyle(ColorScheme scheme) => TextStyle(
      fontFamily: AppTheme.bodyFont,
      fontSize: 12.5,
      height: 1.35,
      color: scheme.onSurfaceVariant,
    );
