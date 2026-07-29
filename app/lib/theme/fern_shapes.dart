import 'package:material_new_shapes/material_new_shapes.dart' as ms;

/// Роли форм M3 в Fern: где какой силуэт и что он значит.
///
/// Формы держим в одном месте по той же причине, что и цвета: силуэт работает
/// языком, только когда одна фигура значит одно и то же на всех экранах.
///
/// ВАЖНО: пакет импортируется с префиксом. Его `Cubic` сталкивается с `Cubic`
/// из `flutter/animation`, и без префикса файл не собирается.
abstract final class FernShapes {
  /// Обложки колод и паков. Порядок менять нельзя: он записан в `Deck.shape`,
  /// и перестановка сменит обложки у всех существующих колод.
  static final List<ms.RoundedPolygon> deckCovers = [
    ms.MaterialShapes.pentagon,
    ms.MaterialShapes.clamShell,
    ms.MaterialShapes.puffyDiamond,
    ms.MaterialShapes.cookie9Sided,
    ms.MaterialShapes.flower,
    ms.MaterialShapes.arch,
  ];

  /// Обложка по индексу, циклически.
  static ms.RoundedPolygon deckCover(int index) =>
      deckCovers[index.abs() % deckCovers.length];

  /// Круг занятия: обложка собирается в него на старте сессии.
  static final ms.RoundedPolygon session = ms.MaterialShapes.circle;

  /// Круг активного пункта навигации: на прилёте распускается в «печеньку».
  static final ms.RoundedPolygon navIdle = ms.MaterialShapes.circle;
  static final ms.RoundedPolygon navActive = ms.MaterialShapes.cookie6Sided;

  /// Кольцо дневной цели: круг, пока цель не взята, «печенька» после.
  static final ms.RoundedPolygon goalIdle = ms.MaterialShapes.circle;
  static final ms.RoundedPolygon goalDone = ms.MaterialShapes.cookie6Sided;

  /// Кольцо покрытия книги: чем больше текста понятно, тем больше вершин.
  static final ms.RoundedPolygon coverageLow = ms.MaterialShapes.circle;
  static final ms.RoundedPolygon coverageHigh = ms.MaterialShapes.cookie12Sided;

  /// Ниже этой доли текста кольцо остаётся кругом.
  static const double coverageFloor = 0.5;

  /// Доля, с которой чтение считается комфортным (полный силуэт).
  static const double coverageComfort = 0.95;

  /// Прогресс морфа кольца покрытия: 0 — круг, 1 — двенадцатигранник.
  static double coverageMorph(double known) {
    if (known.isNaN) return 0;
    if (known <= coverageFloor) return 0;
    if (known >= coverageComfort) return 1;
    return (known - coverageFloor) / (coverageComfort - coverageFloor);
  }

  /// Вехи серии: 0 — меньше недели, 1 — неделя, 2 — месяц, 3 — сто дней.
  static const List<int> streakMilestones = [7, 30, 100];

  static int streakStep(int days) {
    var step = 0;
    for (final m in streakMilestones) {
      if (days >= m) step += 1;
    }
    return step;
  }

  static final List<ms.RoundedPolygon> _streak = [
    ms.MaterialShapes.circle,
    ms.MaterialShapes.diamond,
    ms.MaterialShapes.cookie7Sided,
    ms.MaterialShapes.clover4Leaf,
  ];

  /// Форма вехи по ступени.
  static ms.RoundedPolygon streakShape(int step) =>
      _streak[step.clamp(0, _streak.length - 1)];

  /// Кольцо ожидания: спокойные силуэты, по которым перетекает индикатор.
  ///
  /// Колючие `sunny` и `burst` сюда не берём — ожидание не должно тревожить.
  static final List<ms.RoundedPolygon> waitingRing = [
    ms.MaterialShapes.cookie12Sided,
    ms.MaterialShapes.gem,
    ms.MaterialShapes.pentagon,
    ms.MaterialShapes.oval,
  ];

  /// Засечки короткой сессии: пройденная карточка наливается «печенькой».
  static final ms.RoundedPolygon segmentTodo = ms.MaterialShapes.square;
  static final ms.RoundedPolygon segmentDone = ms.MaterialShapes.cookie4Sided;

  /// Пустое состояние: фигура под иконкой раздела.
  static final ms.RoundedPolygon empty = ms.MaterialShapes.cookie9Sided;

  /// Образец цветовой схемы в настройках.
  static final ms.RoundedPolygon swatchIdle = ms.MaterialShapes.circle;
  static final ms.RoundedPolygon swatchPicked = ms.MaterialShapes.cookie12Sided;
}
