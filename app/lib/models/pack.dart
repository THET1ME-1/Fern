import 'package:flutter/material.dart';

/// Пак — «папка» из нескольких колод одного изучаемого языка. Уровень над
/// колодой: на главном экране пак показывается отдельной, визуально непохожей
/// на колоду плиткой (стопка обложек + счётчик). Вложенности пак-в-пак нет —
/// чтобы не было «папки в папке, которая в папке».
class Pack {
  final String id;

  /// Код изучаемого языка — пак показывается, когда в баннере выбран этот язык.
  final String languageCode;

  /// Название пака («Английский A1», «Сериалы», «Бизнес-лексика»…).
  String name;

  /// Акцентный цвет пака (ARGB).
  int colorValue;

  /// Момент создания (мс от эпохи) — для сортировки.
  final int createdAt;

  Pack({
    required this.id,
    required this.languageCode,
    required this.name,
    required this.colorValue,
    required this.createdAt,
  });

  Color get color => Color(colorValue);

  Map<String, dynamic> toJson() => {
        'id': id,
        'lang': languageCode,
        'name': name,
        'color': colorValue,
        'createdAt': createdAt,
      };

  factory Pack.fromJson(Map<String, dynamic> j) => Pack(
        id: j['id'] as String,
        languageCode: j['lang'] as String? ?? 'en',
        name: j['name'] as String? ?? '',
        colorValue: (j['color'] as num?)?.toInt() ?? 0xFF3F6FB0,
        createdAt: (j['createdAt'] as num?)?.toInt() ?? 0,
      );
}
