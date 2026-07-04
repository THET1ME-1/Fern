import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Тема оформления читалки (независима от темы приложения): цвет страницы,
/// цвет текста и акцент для подсветки известных слов.
class ReaderTheme {
  final String id;
  final String labelRu;
  final String labelEn;
  final Color background;
  final Color text;
  final Color faint; // приглушённый (номера, вторичное)
  final Color accent; // слова, уже имеющиеся в базе (известные)
  final Color added; // слова, добавленные в этой сессии (другой цвет)

  const ReaderTheme({
    required this.id,
    required this.labelRu,
    required this.labelEn,
    required this.background,
    required this.text,
    required this.faint,
    required this.accent,
    required this.added,
  });
}

/// Пресеты тем чтения (день / сепия / серая / ночь / чёрная).
const List<ReaderTheme> kReaderThemes = [
  ReaderTheme(
    id: 'day',
    labelRu: 'День',
    labelEn: 'Day',
    background: Color(0xFFFBFAF7),
    text: Color(0xFF1B1B1A),
    faint: Color(0xFF8A8A85),
    accent: Color(0xFF2E7D5B),
    added: Color(0xFFB5622E),
  ),
  ReaderTheme(
    id: 'sepia',
    labelRu: 'Сепия',
    labelEn: 'Sepia',
    background: Color(0xFFF3E9D2),
    text: Color(0xFF4E3D28),
    faint: Color(0xFF9C8A6B),
    accent: Color(0xFF9A5B20),
    added: Color(0xFF4F7A34),
  ),
  ReaderTheme(
    id: 'gray',
    labelRu: 'Серая',
    labelEn: 'Gray',
    background: Color(0xFFE7E7E4),
    text: Color(0xFF2A2A2A),
    faint: Color(0xFF7C7C79),
    accent: Color(0xFF2E7D5B),
    added: Color(0xFFB5622E),
  ),
  ReaderTheme(
    id: 'night',
    labelRu: 'Ночь',
    labelEn: 'Night',
    background: Color(0xFF23272B),
    text: Color(0xFFCBD0D6),
    faint: Color(0xFF7E858C),
    accent: Color(0xFF6BC49A),
    added: Color(0xFFE0A45A),
  ),
  ReaderTheme(
    id: 'black',
    labelRu: 'Чёрная',
    labelEn: 'Black',
    background: Color(0xFF000000),
    text: Color(0xFFB7BCC2),
    faint: Color(0xFF6A6F75),
    accent: Color(0xFF6BC49A),
    added: Color(0xFFE0A45A),
  ),
];

/// Глобальные настройки читалки (общие для всех книг): тема, размер шрифта,
/// межстрочный интервал, семейство шрифта. Синглтон-[ChangeNotifier].
class ReaderSettings extends ChangeNotifier {
  ReaderSettings._();
  static final ReaderSettings instance = ReaderSettings._();

  static const String _kTheme = 'readerThemeId';
  static const String _kFontScale = 'readerFontScale';
  static const String _kLineHeight = 'readerLineHeight';
  static const String _kFont = 'readerFont';
  static const String _kPaging = 'readerPaging';

  SharedPreferencesAsync get _prefs => SharedPreferencesAsync();

  int _themeIndex = 1; // сепия по умолчанию — приятна для чтения
  double _fontScale = 1.0;
  double _lineHeight = 1.55;
  String _font = 'serif'; // 'serif' | 'sans' | 'Onest'
  bool _horizontalPaging = false; // false = прокрутка, true = листание страниц
  bool _loaded = false;

  int get themeIndex => _themeIndex;
  ReaderTheme get theme => kReaderThemes[_themeIndex % kReaderThemes.length];
  double get fontScale => _fontScale;
  double get lineHeight => _lineHeight;
  String get font => _font;
  bool get horizontalPaging => _horizontalPaging;

  /// Семейство шрифта для [TextStyle] (null = системный).
  String? get fontFamily => switch (_font) {
        'serif' => 'serif',
        'Onest' => 'Onest',
        _ => null,
      };

  Future<void> load() async {
    if (_loaded) return;
    final id = await _prefs.getString(_kTheme);
    if (id != null) {
      final i = kReaderThemes.indexWhere((t) => t.id == id);
      if (i >= 0) _themeIndex = i;
    }
    _fontScale = await _prefs.getDouble(_kFontScale) ?? 1.0;
    _lineHeight = await _prefs.getDouble(_kLineHeight) ?? 1.55;
    _font = await _prefs.getString(_kFont) ?? 'serif';
    _horizontalPaging = await _prefs.getBool(_kPaging) ?? false;
    _loaded = true;
    notifyListeners();
  }

  Future<void> setHorizontalPaging(bool v) async {
    _horizontalPaging = v;
    await _prefs.setBool(_kPaging, v);
    notifyListeners();
  }

  Future<void> setThemeIndex(int i) async {
    _themeIndex = i % kReaderThemes.length;
    await _prefs.setString(_kTheme, theme.id);
    notifyListeners();
  }

  Future<void> setFontScale(double v) async {
    _fontScale = v.clamp(0.8, 1.9);
    await _prefs.setDouble(_kFontScale, _fontScale);
    notifyListeners();
  }

  Future<void> setLineHeight(double v) async {
    _lineHeight = v.clamp(1.2, 2.2);
    await _prefs.setDouble(_kLineHeight, _lineHeight);
    notifyListeners();
  }

  Future<void> setFont(String v) async {
    _font = v;
    await _prefs.setString(_kFont, v);
    notifyListeners();
  }
}
