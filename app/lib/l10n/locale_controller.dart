import 'package:flutter/material.dart';

import '../services/deck_repository.dart';

/// Один язык интерфейса: код и родное название (для списка выбора).
class AppLanguage {
  final String code;
  final String nativeName;
  const AppLanguage(this.code, this.nativeName);
}

/// Единый центр языков интерфейса. Хранит выбранный язык в [DeckRepository] и
/// оповещает слушателей; `MaterialApp` слушает контроллер и пересобирает дерево —
/// строки через [tr] сразу переключаются. Добавить язык = запись в [languages]
/// + карта переводов в `translations.dart`.
class LocaleController extends ChangeNotifier {
  LocaleController._();
  static final LocaleController instance = LocaleController._();

  final DeckRepository _repo = DeckRepository.instance;

  /// Поддерживаемые языки интерфейса (порядок = порядок в списке выбора).
  /// Базовые ru/en лежат в strings.dart, остальные — в translations.dart.
  static const List<AppLanguage> languages = [
    AppLanguage('ru', 'Русский'),
    AppLanguage('en', 'English'),
    AppLanguage('de', 'Deutsch'),
    AppLanguage('fr', 'Français'),
    AppLanguage('es', 'Español'),
    AppLanguage('it', 'Italiano'),
    AppLanguage('pt', 'Português'),
  ];

  static List<Locale> get supported =>
      [for (final l in languages) Locale(l.code)];

  static Set<String> get _codes => {for (final l in languages) l.code};

  String _code = 'ru';
  bool _loaded = false;

  String get code => _code;
  Locale get locale => Locale(_code);
  bool get isLoaded => _loaded;

  /// Сопоставление страны → вероятный язык (если язык телефона не поддержан).
  static const Map<String, String> _langByCountry = {
    'RU': 'ru', 'BY': 'ru', 'KZ': 'ru', 'KG': 'ru',
    'DE': 'de', 'AT': 'de', 'CH': 'de', 'LI': 'de',
    'FR': 'fr', 'BE': 'fr', 'LU': 'fr', 'MC': 'fr',
    'ES': 'es', 'MX': 'es', 'AR': 'es', 'CO': 'es', 'CL': 'es',
    'PE': 'es', 'VE': 'es', 'EC': 'es', 'GT': 'es',
    'IT': 'it', 'SM': 'it',
    'PT': 'pt', 'BR': 'pt', 'AO': 'pt', 'MZ': 'pt',
  };

  /// Определяет язык по системе: сперва по языку телефона, затем по стране,
  /// иначе — английский.
  String _detectSystem() {
    final disp = WidgetsBinding.instance.platformDispatcher;
    for (final l in disp.locales) {
      final lc = l.languageCode.toLowerCase();
      if (_codes.contains(lc)) return lc;
    }
    final country = (disp.locale.countryCode ?? '').toUpperCase();
    final byCountry = _langByCountry[country];
    if (byCountry != null && _codes.contains(byCountry)) return byCountry;
    return 'en';
  }

  /// Подгружает сохранённый язык. Вызывается один раз до `runApp`.
  Future<void> load() async {
    final stored = await _repo.languageCode();
    if (stored != null && _codes.contains(stored)) {
      _code = stored;
    } else {
      _code = _detectSystem();
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> setCode(String code) async {
    if (code == _code || !_codes.contains(code)) return;
    _code = code;
    notifyListeners();
    await _repo.setLanguageCode(code);
    // Встроенные колоды переводим следом: иначе, сменив язык, человек видел бы
    // испанские слова с русскими переводами (перевод выбирался при посеве).
    await _repo.relocalizeBuiltIns();
  }
}
