import 'package:flutter/material.dart';

/// Колода (пак слов для изучения). Аналог «плитки игрока» в ScoreMaster:
/// у неё своя форма-обложка и цвет. Принадлежит одному изучаемому языку.
class Deck {
  final String id;

  /// Код изучаемого языка (см. [StudyLanguage]) — колода показывается на
  /// главном экране, когда в баннере выбран этот язык.
  final String languageCode;

  /// Название колоды («Топ-1000 слов», «Еда», «Глаголы»…).
  String name;

  /// Цвет обложки (ARGB).
  int colorValue;

  /// Индекс формы-обложки (см. `kDeckShapes`).
  int shapeIndex;

  /// Направление изучения: 0 — прямое (слово→перевод), 1 — обратное
  /// (перевод→слово), 2 — в обе стороны. См. [StudyDirection] в study_models.
  int directionIndex;

  /// Момент создания (мс от эпохи) — для сортировки.
  final int createdAt;

  /// Id пака, в который вложена колода (см. [Pack]), либо null — колода лежит
  /// на верхнем уровне главного экрана. Пак — это «папка» из нескольких колод.
  String? packId;

  /// Ключ локализации имени — есть только у встроенных колод (стартовые наборы
  /// и колоды по умолчанию). По нему имя и переводы карточек пересобираются при
  /// смене языка интерфейса; у колод пользователя он null, их никто не трогает.
  String? nameKey;

  Deck({
    required this.id,
    required this.languageCode,
    required this.name,
    required this.colorValue,
    required this.shapeIndex,
    required this.createdAt,
    this.directionIndex = 0,
    this.packId,
    this.nameKey,
  });

  /// Встроенная колода (стартовый набор / набор по умолчанию).
  bool get isBuiltIn => nameKey != null && nameKey!.isNotEmpty;

  Color get color => Color(colorValue);

  Map<String, dynamic> toJson() => {
        'id': id,
        'lang': languageCode,
        'name': name,
        'color': colorValue,
        'shape': shapeIndex,
        'dir': directionIndex,
        'createdAt': createdAt,
        // Пишем только когда колода в паке — не раздуваем JSON обычных колод.
        if (packId != null) 'pack': packId,
        if (nameKey != null) 'nameKey': nameKey,
      };

  factory Deck.fromJson(Map<String, dynamic> j) => Deck(
        id: j['id'] as String,
        languageCode: j['lang'] as String? ?? 'en',
        name: j['name'] as String? ?? '',
        colorValue: (j['color'] as num?)?.toInt() ?? 0xFF2E7D5B,
        shapeIndex: (j['shape'] as num?)?.toInt() ?? 0,
        directionIndex: (j['dir'] as num?)?.toInt() ?? 0,
        createdAt: (j['createdAt'] as num?)?.toInt() ?? 0,
        packId: j['pack'] as String?,
        nameKey: j['nameKey'] as String?,
      );
}
