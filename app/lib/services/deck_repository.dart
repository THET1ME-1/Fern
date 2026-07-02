import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/deck.dart';
import '../models/fsrs.dart';
import '../models/word_card.dart';

/// Единый слой доступа к данным Fern поверх [SharedPreferences]
/// (ДНК ScoreMaster — там это был `GameRepository`).
///
/// Хранит колоды, карточки, выбранный язык и настройки как JSON. После каждой
/// мутации зовёт [notifyListeners], а экраны слушают репозиторий и
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

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  // ----------------------------- Колоды -----------------------------

  Future<List<Deck>> loadDecks() async {
    final prefs = await _prefs;
    final raw = prefs.getStringList(_kDecks) ?? [];
    final decks = <Deck>[];
    for (final e in raw) {
      try {
        decks.add(Deck.fromJson(jsonDecode(e) as Map<String, dynamic>));
      } catch (_) {/* пропускаем битую запись */}
    }
    return decks;
  }

  Future<void> saveDecks(List<Deck> decks) async {
    final prefs = await _prefs;
    await prefs.setStringList(
      _kDecks,
      decks.map((d) => jsonEncode(d.toJson())).toList(),
    );
    notifyListeners();
  }

  Future<void> upsertDeck(Deck deck) async {
    final decks = await loadDecks();
    final idx = decks.indexWhere((d) => d.id == deck.id);
    if (idx >= 0) {
      decks[idx] = deck;
    } else {
      decks.add(deck);
    }
    await saveDecks(decks);
  }

  /// Удаляет колоду и все её карточки.
  Future<void> deleteDeck(String deckId) async {
    final decks = await loadDecks()
      ..removeWhere((d) => d.id == deckId);
    await saveDecks(decks);
    final cards = await loadCards()
      ..removeWhere((c) => c.deckId == deckId);
    await saveCards(cards);
  }

  // ----------------------------- Карточки -----------------------------

  Future<List<WordCard>> loadCards() async {
    final prefs = await _prefs;
    final raw = prefs.getStringList(_kCards) ?? [];
    final cards = <WordCard>[];
    for (final e in raw) {
      try {
        cards.add(WordCard.fromJson(jsonDecode(e) as Map<String, dynamic>));
      } catch (_) {/* пропускаем битую запись */}
    }
    return cards;
  }

  Future<void> saveCards(List<WordCard> cards) async {
    final prefs = await _prefs;
    await prefs.setStringList(
      _kCards,
      cards.map((c) => jsonEncode(c.toJson())).toList(),
    );
    notifyListeners();
  }

  Future<List<WordCard>> cardsForDeck(String deckId) async {
    final all = await loadCards();
    return all.where((c) => c.deckId == deckId).toList();
  }

  Future<void> upsertCard(WordCard card) async {
    final cards = await loadCards();
    final idx = cards.indexWhere((c) => c.id == card.id);
    if (idx >= 0) {
      cards[idx] = card;
    } else {
      cards.add(card);
    }
    await saveCards(cards);
  }

  Future<void> deleteCard(String cardId) async {
    final cards = await loadCards()
      ..removeWhere((c) => c.id == cardId);
    await saveCards(cards);
  }

  /// Применяет оценку к карточке (FSRS) и сохраняет новое состояние повторения.
  Future<void> rateCard(WordCard card, Rating rating, DateTime now) async {
    card.review = Fsrs.instance.review(card.review, rating, now);
    await upsertCard(card);
  }

  // ----------------------------- Выбранный язык -----------------------------

  Future<String?> selectedLanguageCode() async {
    final prefs = await _prefs;
    return prefs.getString(_kSelectedLanguage);
  }

  Future<void> setSelectedLanguageCode(String code) async {
    final prefs = await _prefs;
    await prefs.setString(_kSelectedLanguage, code);
    notifyListeners();
  }

  // ----------------------------- Настройки темы/языка -----------------------------

  Future<int?> seedColorValue() async => (await _prefs).getInt(_kSeedColor);
  Future<void> setSeedColorValue(int value) async =>
      (await _prefs).setInt(_kSeedColor, value);

  Future<int?> themeModeRaw() async => (await _prefs).getInt(_kThemeMode);
  Future<void> setThemeModeRaw(int value) async =>
      (await _prefs).setInt(_kThemeMode, value);

  Future<bool> isDarkTheme() async =>
      (await _prefs).getBool(_kIsDarkTheme) ?? true;
  Future<void> setDarkTheme(bool value) async =>
      (await _prefs).setBool(_kIsDarkTheme, value);

  Future<bool> dynamicColorEnabled() async =>
      (await _prefs).getBool(_kDynamicColor) ?? false;
  Future<void> setDynamicColorEnabled(bool value) async =>
      (await _prefs).setBool(_kDynamicColor, value);

  Future<bool> amoledEnabled() async => (await _prefs).getBool(_kAmoled) ?? false;
  Future<void> setAmoledEnabled(bool value) async =>
      (await _prefs).setBool(_kAmoled, value);

  Future<String?> languageCode() async => (await _prefs).getString(_kUiLanguage);
  Future<void> setLanguageCode(String code) async =>
      (await _prefs).setString(_kUiLanguage, code);

  Future<int> dailyGoal() async => (await _prefs).getInt(_kDailyGoal) ?? 20;
  Future<void> setDailyGoal(int value) async {
    await (await _prefs).setInt(_kDailyGoal, value);
    notifyListeners();
  }

  // ----------------------------- Бэкап -----------------------------

  /// Полный снимок данных (колоды + карты + настройки) как JSON-строка.
  Future<String> exportJson() async {
    final decks = await loadDecks();
    final cards = await loadCards();
    final prefs = await _prefs;
    return const JsonEncoder.withIndent('  ').convert({
      'version': 1,
      'decks': [for (final d in decks) d.toJson()],
      'cards': [for (final c in cards) c.toJson()],
      'settings': {
        'seedColor': prefs.getInt(_kSeedColor),
        'themeMode': prefs.getInt(_kThemeMode),
        'dynamicColor': prefs.getBool(_kDynamicColor),
        'amoled': prefs.getBool(_kAmoled),
        'uiLanguageCode': prefs.getString(_kUiLanguage),
        'selectedLanguage': prefs.getString(_kSelectedLanguage),
        'dailyGoal': prefs.getInt(_kDailyGoal),
      },
    });
  }

  /// Восстанавливает данные из JSON-снимка (перезаписывает текущие).
  Future<void> importJson(String raw) async {
    final data = jsonDecode(raw) as Map<String, dynamic>;
    final decks = (data['decks'] as List? ?? [])
        .map((e) => Deck.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
    final cards = (data['cards'] as List? ?? [])
        .map((e) => WordCard.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
    await saveDecks(decks);
    await saveCards(cards);
    final s = (data['settings'] as Map?)?.cast<String, dynamic>() ?? {};
    final prefs = await _prefs;
    if (s['seedColor'] is num) await prefs.setInt(_kSeedColor, s['seedColor']);
    if (s['themeMode'] is num) await prefs.setInt(_kThemeMode, s['themeMode']);
    if (s['dynamicColor'] is bool) {
      await prefs.setBool(_kDynamicColor, s['dynamicColor']);
    }
    if (s['amoled'] is bool) await prefs.setBool(_kAmoled, s['amoled']);
    if (s['uiLanguageCode'] is String) {
      await prefs.setString(_kUiLanguage, s['uiLanguageCode']);
    }
    if (s['selectedLanguage'] is String) {
      await prefs.setString(_kSelectedLanguage, s['selectedLanguage']);
    }
    if (s['dailyGoal'] is num) await prefs.setInt(_kDailyGoal, s['dailyGoal']);
    notifyListeners();
  }

  // ----------------------------- Демо-колоды -----------------------------

  /// Кладёт пару колод-примеров при первом запуске (ноль настройки, чтобы
  /// сразу было что учить). Идея из README §2.6.
  Future<void> seedDemoIfNeeded() async {
    final prefs = await _prefs;
    if (prefs.getBool(_kSeededDemo) ?? false) return;
    final existing = await loadDecks();
    if (existing.isNotEmpty) {
      await prefs.setBool(_kSeededDemo, true);
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
    await saveDecks(decks);
    await saveCards(cards);
    await prefs.setBool(_kSeededDemo, true);
  }

  static WordCard _card(
          String id, String deck, String front, String back, String ex) =>
      WordCard(id: id, deckId: deck, front: front, back: back, example: ex);
}
