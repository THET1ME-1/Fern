import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/deck.dart';
import '../models/fsrs.dart';
import '../models/word_card.dart';

/// Единый слой доступа к данным Fern.
///
/// ДНК ScoreMaster (там это был `GameRepository`), но хранилище переведено на
/// **[SharedPreferencesAsync]** + **кэш в памяти**:
///
/// * `SharedPreferencesAsync` пишет НАДЁЖНО — метод завершается, когда запись
///   реально дошла до нативного стора (в отличие от старого `apply()`, который
///   стрелял «в фон»: если пользователь добавлял слово и сразу смахивал
///   приложение из недавних, асинхронный сброс на диск не успевал — слово
///   пропадало. Это и была причина «новые слова/папки не сохраняются»).
/// * Кэш в памяти (`_decks`/`_cards`) — чтения мгновенные и консистентные, а
///   `notifyListeners()` больше не заставляет каждый экран заново парсить весь
///   JSON.
///
/// После каждой мутации зовём [notifyListeners]; экраны слушают репозиторий и
/// перезагружаются — данные на всех вкладках всегда актуальны.
class DeckRepository extends ChangeNotifier {
  DeckRepository._();
  static final DeckRepository instance = DeckRepository._();

  static const String _kDecks = 'decks';
  static const String _kCards = 'cards';
  static const String _kSelectedLanguage = 'selectedLanguage';
  static const String _kSeededDemo = 'seededDemo';

  // Настройки (совместимы по смыслу с ScoreMaster).
  static const String _kSeedColor = 'seedColor';
  static const String _kThemeMode = 'themeMode'; // 0 свет,1 тёмн,2 систем,3 авто
  static const String _kIsDarkTheme = 'isDarkTheme';
  static const String _kDynamicColor = 'dynamicColor';
  static const String _kAmoled = 'amoled';
  static const String _kUiLanguage = 'uiLanguageCode';
  static const String _kDailyGoal = 'dailyGoal';

  // Флаг разовой миграции со старого (legacy) хранилища на async.
  static const String _kMigratedV1 = 'migratedToAsyncV1';

  // `SharedPreferencesAsync` — тонкая обёртка без собственного кэша (каждый
  // вызов идёт в нативный стор), поэтому создаём её по требованию. Это и лениво
  // (платформа к моменту вызова уже зарегистрирована), и корректно для тестов,
  // где mock-бэкенд подменяется между кейсами.
  SharedPreferencesAsync get _prefs => SharedPreferencesAsync();

  // ----------------------------- Кэш в памяти -----------------------------

  final List<Deck> _decks = [];
  final List<WordCard> _cards = [];
  bool _loaded = false;

  /// Один раз загружает данные в память (и мигрирует со старого стора).
  /// Вызывать до `runApp`. Идемпотентно.
  Future<void> init() async {
    if (_loaded) return;
    await _migrateLegacyIfNeeded();
    _decks
      ..clear()
      ..addAll(_decodeDecks(await _prefs.getStringList(_kDecks) ?? const []));
    _cards
      ..clear()
      ..addAll(_decodeCards(await _prefs.getStringList(_kCards) ?? const []));
    _loaded = true;
  }

  /// Гарантирует, что кэш загружен (на случай вызова методов до [init]).
  Future<void> _ensureLoaded() async {
    if (!_loaded) await init();
  }

  /// Сбрасывает состояние синглтона между тестами.
  @visibleForTesting
  void resetForTest() {
    _decks.clear();
    _cards.clear();
    _loaded = false;
  }

  /// Переносит данные из старого `SharedPreferences` (`apply()`-стор) в новый
  /// надёжный async-стор — единожды, чтобы не потерять уже сохранённые колоды,
  /// карты и настройки при обновлении приложения.
  Future<void> _migrateLegacyIfNeeded() async {
    if (await _prefs.getBool(_kMigratedV1) ?? false) return;
    try {
      final legacy = await SharedPreferences.getInstance();
      Future<void> copyStringList(String k) async {
        final v = legacy.getStringList(k);
        if (v != null) await _prefs.setStringList(k, v);
      }

      Future<void> copyString(String k) async {
        final v = legacy.getString(k);
        if (v != null) await _prefs.setString(k, v);
      }

      Future<void> copyInt(String k) async {
        final v = legacy.getInt(k);
        if (v != null) await _prefs.setInt(k, v);
      }

      Future<void> copyBool(String k) async {
        final v = legacy.getBool(k);
        if (v != null) await _prefs.setBool(k, v);
      }

      await copyStringList(_kDecks);
      await copyStringList(_kCards);
      await copyString(_kSelectedLanguage);
      await copyBool(_kSeededDemo);
      await copyInt(_kSeedColor);
      await copyInt(_kThemeMode);
      await copyBool(_kIsDarkTheme);
      await copyBool(_kDynamicColor);
      await copyBool(_kAmoled);
      await copyString(_kUiLanguage);
      await copyInt(_kDailyGoal);
    } catch (_) {
      // Legacy-стор недоступен — не критично, продолжаем на чистом async.
    }
    await _prefs.setBool(_kMigratedV1, true);
  }

  List<Deck> _decodeDecks(List<String> raw) {
    final out = <Deck>[];
    for (final e in raw) {
      try {
        out.add(Deck.fromJson(jsonDecode(e) as Map<String, dynamic>));
      } catch (_) {/* пропускаем битую запись */}
    }
    return out;
  }

  List<WordCard> _decodeCards(List<String> raw) {
    final out = <WordCard>[];
    for (final e in raw) {
      try {
        out.add(WordCard.fromJson(jsonDecode(e) as Map<String, dynamic>));
      } catch (_) {/* пропускаем битую запись */}
    }
    return out;
  }

  // ----------------------------- Колоды -----------------------------

  Future<List<Deck>> loadDecks() async {
    await _ensureLoaded();
    return List<Deck>.from(_decks);
  }

  /// Синхронный доступ к кэшу колод (после [init]).
  List<Deck> get decks => List<Deck>.unmodifiable(_decks);

  Future<void> saveDecks(List<Deck> decks) async {
    await _ensureLoaded();
    _decks
      ..clear()
      ..addAll(decks);
    await _persistDecks();
    notifyListeners();
  }

  Future<void> _persistDecks() async {
    await _prefs.setStringList(
      _kDecks,
      _decks.map((d) => jsonEncode(d.toJson())).toList(),
    );
  }

  Future<void> upsertDeck(Deck deck) async {
    await _ensureLoaded();
    final idx = _decks.indexWhere((d) => d.id == deck.id);
    if (idx >= 0) {
      _decks[idx] = deck;
    } else {
      _decks.add(deck);
    }
    await _persistDecks();
    notifyListeners();
  }

  /// Удаляет колоду и все её карточки.
  Future<void> deleteDeck(String deckId) async {
    await _ensureLoaded();
    _decks.removeWhere((d) => d.id == deckId);
    _cards.removeWhere((c) => c.deckId == deckId);
    await _persistDecks();
    await _persistCards();
    notifyListeners();
  }

  // ----------------------------- Карточки -----------------------------

  Future<List<WordCard>> loadCards() async {
    await _ensureLoaded();
    return List<WordCard>.from(_cards);
  }

  Future<void> saveCards(List<WordCard> cards) async {
    await _ensureLoaded();
    _cards
      ..clear()
      ..addAll(cards);
    await _persistCards();
    notifyListeners();
  }

  Future<void> _persistCards() async {
    await _prefs.setStringList(
      _kCards,
      _cards.map((c) => jsonEncode(c.toJson())).toList(),
    );
  }

  Future<List<WordCard>> cardsForDeck(String deckId) async {
    await _ensureLoaded();
    return _cards.where((c) => c.deckId == deckId).toList();
  }

  Future<void> upsertCard(WordCard card) async {
    await _ensureLoaded();
    final idx = _cards.indexWhere((c) => c.id == card.id);
    if (idx >= 0) {
      _cards[idx] = card;
    } else {
      _cards.add(card);
    }
    await _persistCards();
    notifyListeners();
  }

  /// Добавляет пачку карточек за одну запись на диск (быстрое добавление).
  Future<void> addCards(Iterable<WordCard> cards) async {
    await _ensureLoaded();
    _cards.addAll(cards);
    await _persistCards();
    notifyListeners();
  }

  Future<void> deleteCard(String cardId) async {
    await _ensureLoaded();
    _cards.removeWhere((c) => c.id == cardId);
    await _persistCards();
    notifyListeners();
  }

  /// Применяет оценку к карточке (FSRS) и сохраняет новое состояние повторения.
  Future<void> rateCard(WordCard card, Rating rating, DateTime now) async {
    card.review = Fsrs.instance.review(card.review, rating, now);
    await upsertCard(card);
  }

  // ----------------------------- Выбранный язык -----------------------------

  Future<String?> selectedLanguageCode() async =>
      _prefs.getString(_kSelectedLanguage);

  Future<void> setSelectedLanguageCode(String code) async {
    await _prefs.setString(_kSelectedLanguage, code);
    notifyListeners();
  }

  // ----------------------------- Настройки темы/языка -----------------------------

  Future<int?> seedColorValue() async => _prefs.getInt(_kSeedColor);
  Future<void> setSeedColorValue(int value) async =>
      _prefs.setInt(_kSeedColor, value);

  Future<int?> themeModeRaw() async => _prefs.getInt(_kThemeMode);
  Future<void> setThemeModeRaw(int value) async =>
      _prefs.setInt(_kThemeMode, value);

  Future<bool> isDarkTheme() async =>
      await _prefs.getBool(_kIsDarkTheme) ?? true;
  Future<void> setDarkTheme(bool value) async =>
      _prefs.setBool(_kIsDarkTheme, value);

  Future<bool> dynamicColorEnabled() async =>
      await _prefs.getBool(_kDynamicColor) ?? false;
  Future<void> setDynamicColorEnabled(bool value) async =>
      _prefs.setBool(_kDynamicColor, value);

  Future<bool> amoledEnabled() async =>
      await _prefs.getBool(_kAmoled) ?? false;
  Future<void> setAmoledEnabled(bool value) async =>
      _prefs.setBool(_kAmoled, value);

  Future<String?> languageCode() async => _prefs.getString(_kUiLanguage);
  Future<void> setLanguageCode(String code) async =>
      _prefs.setString(_kUiLanguage, code);

  Future<int> dailyGoal() async => await _prefs.getInt(_kDailyGoal) ?? 20;
  Future<void> setDailyGoal(int value) async {
    await _prefs.setInt(_kDailyGoal, value);
    notifyListeners();
  }

  // ----------------------------- Бэкап -----------------------------

  /// Полный снимок данных (колоды + карты + настройки) как JSON-строка.
  Future<String> exportJson() async {
    await _ensureLoaded();
    return const JsonEncoder.withIndent('  ').convert({
      'version': 1,
      'decks': [for (final d in _decks) d.toJson()],
      'cards': [for (final c in _cards) c.toJson()],
      'settings': {
        'seedColor': await _prefs.getInt(_kSeedColor),
        'themeMode': await _prefs.getInt(_kThemeMode),
        'dynamicColor': await _prefs.getBool(_kDynamicColor),
        'amoled': await _prefs.getBool(_kAmoled),
        'uiLanguageCode': await _prefs.getString(_kUiLanguage),
        'selectedLanguage': await _prefs.getString(_kSelectedLanguage),
        'dailyGoal': await _prefs.getInt(_kDailyGoal),
      },
    });
  }

  /// Восстанавливает данные из JSON-снимка (перезаписывает текущие).
  Future<void> importJson(String raw) async {
    await _ensureLoaded();
    final data = jsonDecode(raw) as Map<String, dynamic>;
    final decks = (data['decks'] as List? ?? [])
        .map((e) => Deck.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
    final cards = (data['cards'] as List? ?? [])
        .map((e) => WordCard.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
    _decks
      ..clear()
      ..addAll(decks);
    _cards
      ..clear()
      ..addAll(cards);
    await _persistDecks();
    await _persistCards();
    final s = (data['settings'] as Map?)?.cast<String, dynamic>() ?? {};
    if (s['seedColor'] is num) {
      await _prefs.setInt(_kSeedColor, (s['seedColor'] as num).toInt());
    }
    if (s['themeMode'] is num) {
      await _prefs.setInt(_kThemeMode, (s['themeMode'] as num).toInt());
    }
    if (s['dynamicColor'] is bool) {
      await _prefs.setBool(_kDynamicColor, s['dynamicColor'] as bool);
    }
    if (s['amoled'] is bool) await _prefs.setBool(_kAmoled, s['amoled'] as bool);
    if (s['uiLanguageCode'] is String) {
      await _prefs.setString(_kUiLanguage, s['uiLanguageCode'] as String);
    }
    if (s['selectedLanguage'] is String) {
      await _prefs.setString(_kSelectedLanguage, s['selectedLanguage'] as String);
    }
    if (s['dailyGoal'] is num) {
      await _prefs.setInt(_kDailyGoal, (s['dailyGoal'] as num).toInt());
    }
    notifyListeners();
  }

  // ----------------------------- Демо-колоды -----------------------------

  /// Кладёт пару колод-примеров при первом запуске (ноль настройки, чтобы
  /// сразу было что учить). Идея из README §2.6.
  Future<void> seedDemoIfNeeded() async {
    await _ensureLoaded();
    if (await _prefs.getBool(_kSeededDemo) ?? false) return;
    if (_decks.isNotEmpty) {
      await _prefs.setBool(_kSeededDemo, true);
      return;
    }
    const now = 0;
    final decks = <Deck>[
      Deck(
        id: 'demo_en_basics',
        languageCode: 'en',
        name: 'Первые слова',
        colorValue: 0xFF2E7D5B,
        shapeIndex: 0,
        createdAt: now,
      ),
      Deck(
        id: 'demo_en_verbs',
        languageCode: 'en',
        name: 'Глаголы',
        colorValue: 0xFF3F6FB0,
        shapeIndex: 2,
        createdAt: now + 1,
      ),
    ];
    final cards = <WordCard>[
      _card('c1', 'demo_en_basics', 'hello', 'привет', 'Hello, how are you?'),
      _card('c2', 'demo_en_basics', 'thank you', 'спасибо', 'Thank you very much.'),
      _card('c3', 'demo_en_basics', 'water', 'вода', 'A glass of water, please.'),
      _card('c4', 'demo_en_basics', 'friend', 'друг', 'She is my best friend.'),
      _card('c5', 'demo_en_basics', 'house', 'дом', 'We live in a small house.'),
      _card('v1', 'demo_en_verbs', 'to go', 'идти, ехать', 'I go to school.'),
      _card('v2', 'demo_en_verbs', 'to eat', 'есть, кушать', 'They eat breakfast.'),
      _card('v3', 'demo_en_verbs', 'to speak', 'говорить', 'Do you speak English?'),
      _card('v4', 'demo_en_verbs', 'to learn', 'учить, изучать', 'I learn new words.'),
    ];
    _decks
      ..clear()
      ..addAll(decks);
    _cards
      ..clear()
      ..addAll(cards);
    await _persistDecks();
    await _persistCards();
    await _prefs.setBool(_kSeededDemo, true);
    notifyListeners();
  }

  static WordCard _card(
          String id, String deck, String front, String back, String ex) =>
      WordCard(id: id, deckId: deck, front: front, back: back, example: ex);
}
