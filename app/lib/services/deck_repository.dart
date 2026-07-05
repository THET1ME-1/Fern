import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/deck.dart';
import '../models/fsrs.dart';
import '../models/pack.dart';
import '../models/review_log.dart';
import '../models/word_card.dart';
import 'pos.dart';

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
  static const String _kPacks = 'packs';
  static const String _kCards = 'cards';
  static const String _kSelectedLanguage = 'selectedLanguage';
  static const String _kSeededDemo = 'seededDemo';
  static const String _kSeedVersion = 'seedVersion';
  static const String _kReviewLog = 'reviewLog';
  static const String _kMatchBest = 'matchBest'; // deckId -> лучшее время, мс
  static const String _kReadingStats = 'readingStats'; // {s: секунды, w: слова}

  // Настройки (совместимы по смыслу с ScoreMaster).
  static const String _kSeedColor = 'seedColor';
  static const String _kThemeMode =
      'themeMode'; // 0 свет,1 тёмн,2 систем,3 авто
  static const String _kIsDarkTheme = 'isDarkTheme';
  static const String _kDynamicColor = 'dynamicColor';
  static const String _kAmoled = 'amoled';
  static const String _kUiLanguage = 'uiLanguageCode';
  static const String _kDailyGoal = 'dailyGoal';
  static const String _kReminderOn = 'reminderEnabled';
  static const String _kReminderHour = 'reminderHour';
  static const String _kReminderMinute = 'reminderMinute';
  static const String _kOnboarded = 'onboarded';

  // Перевод: список пользовательских серверов (JSON) и id активного провайдера.
  static const String _kTransEndpoints = 'translationEndpoints';
  static const String _kTransActive = 'translationActive';
  // Разбор видео: режим добавления слов и последняя целевая колода.
  static const String _kAddWordMode = 'addWordMode'; // auto|manual|remember
  static const String _kLastVideoDeck = 'lastVideoDeckId';
  // Главный экран: показывать ли баннер «Разобрать видео».
  static const String _kShowVideoBanner = 'showVideoBanner';

  // Флаг разовой миграции со старого (legacy) хранилища на async.
  static const String _kMigratedV1 = 'migratedToAsyncV1';
  // Разовая чистка вклеенной части речи + определение части речи → тег pos.
  static const String _kPosMigrated = 'posMigratedV2';

  // `SharedPreferencesAsync` — тонкая обёртка без собственного кэша (каждый
  // вызов идёт в нативный стор), поэтому создаём её по требованию. Это и лениво
  // (платформа к моменту вызова уже зарегистрирована), и корректно для тестов,
  // где mock-бэкенд подменяется между кейсами.
  SharedPreferencesAsync get _prefs => SharedPreferencesAsync();

  // ----------------------------- Кэш в памяти -----------------------------

  final List<Deck> _decks = [];
  final List<Pack> _packs = [];
  final List<WordCard> _cards = [];
  ReviewLog _log = ReviewLog.empty();
  Map<String, int> _matchBest = {};
  int _readSeconds = 0;
  int _readWords = 0;
  bool _loaded = false;

  /// Один раз загружает данные в память (и мигрирует со старого стора).
  /// Вызывать до `runApp`. Идемпотентно.
  Future<void> init() async {
    if (_loaded) return;
    await _migrateLegacyIfNeeded();
    _decks
      ..clear()
      ..addAll(_decodeDecks(await _prefs.getStringList(_kDecks) ?? const []));
    _packs
      ..clear()
      ..addAll(_decodePacks(await _prefs.getStringList(_kPacks) ?? const []));
    _cards
      ..clear()
      ..addAll(_decodeCards(await _prefs.getStringList(_kCards) ?? const []));
    _log = _decodeLog(await _prefs.getString(_kReviewLog));
    _matchBest = _decodeMatchBest(await _prefs.getString(_kMatchBest));
    _decodeReading(await _prefs.getString(_kReadingStats));
    await _migratePosIfNeeded();
    _loaded = true;
  }

  /// Разово (1) вычищает вклеенную в слово часть речи («the артикль» → «the»)
  /// и (2) определяет часть речи по слову → тег [WordCard.pos]. Так теги
  /// появляются и у старых колод, и у слов без явной метки.
  Future<void> _migratePosIfNeeded() async {
    if (await _prefs.getBool(_kPosMigrated) ?? false) return;
    final deckLang = {for (final d in _decks) d.id: d.languageCode};
    var changed = false;
    for (final c in _cards) {
      if (c.pos.isNotEmpty) continue;
      final lang = deckLang[c.deckId] ?? 'en';
      final stripped = PosDetect.strip(c.front);
      if (stripped.$2 != null) {
        c.front = stripped.$1;
        c.pos = stripped.$2!;
        changed = true;
      } else {
        final d = PosDetect.detect(c.front, languageCode: lang);
        if (d.isNotEmpty) {
          c.pos = d;
          changed = true;
        }
      }
    }
    if (changed) await _persistCards();
    await _prefs.setBool(_kPosMigrated, true);
  }

  void _decodeReading(String? raw) {
    _readSeconds = 0;
    _readWords = 0;
    if (raw == null || raw.isEmpty) return;
    try {
      final m = (jsonDecode(raw) as Map).cast<String, dynamic>();
      _readSeconds = (m['s'] as num?)?.toInt() ?? 0;
      _readWords = (m['w'] as num?)?.toInt() ?? 0;
    } catch (_) {
      /* битая запись — оставляем нули */
    }
  }

  Map<String, int> _decodeMatchBest(String? raw) {
    if (raw == null || raw.isEmpty) return {};
    try {
      final m = (jsonDecode(raw) as Map).cast<String, dynamic>();
      return {for (final e in m.entries) e.key: (e.value as num).toInt()};
    } catch (_) {
      return {};
    }
  }

  ReviewLog _decodeLog(String? raw) {
    if (raw == null || raw.isEmpty) return ReviewLog.empty();
    try {
      return ReviewLog.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return ReviewLog.empty();
    }
  }

  /// Гарантирует, что кэш загружен (на случай вызова методов до [init]).
  Future<void> _ensureLoaded() async {
    if (!_loaded) await init();
  }

  /// Сбрасывает состояние синглтона между тестами.
  @visibleForTesting
  void resetForTest() {
    _decks.clear();
    _packs.clear();
    _cards.clear();
    _log = ReviewLog.empty();
    _matchBest = {};
    _readSeconds = 0;
    _readWords = 0;
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
      await copyString(_kReviewLog);
      await copyString(_kMatchBest);
      await copyString(_kSelectedLanguage);
      await copyBool(_kSeededDemo);
      await copyInt(_kSeedColor);
      await copyInt(_kThemeMode);
      await copyBool(_kIsDarkTheme);
      await copyBool(_kDynamicColor);
      await copyBool(_kAmoled);
      await copyString(_kUiLanguage);
      await copyInt(_kDailyGoal);
      await copyBool(_kReminderOn);
      await copyInt(_kReminderHour);
      await copyInt(_kReminderMinute);
      await copyBool(_kOnboarded);
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
      } catch (_) {
        /* пропускаем битую запись */
      }
    }
    return out;
  }

  List<Pack> _decodePacks(List<String> raw) {
    final out = <Pack>[];
    for (final e in raw) {
      try {
        out.add(Pack.fromJson(jsonDecode(e) as Map<String, dynamic>));
      } catch (_) {
        /* пропускаем битую запись */
      }
    }
    return out;
  }

  List<WordCard> _decodeCards(List<String> raw) {
    final out = <WordCard>[];
    for (final e in raw) {
      try {
        out.add(WordCard.fromJson(jsonDecode(e) as Map<String, dynamic>));
      } catch (_) {
        /* пропускаем битую запись */
      }
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

  // ----------------------------- Паки -----------------------------

  /// Синхронный доступ к кэшу паков (после [init]).
  List<Pack> get packs => List<Pack>.unmodifiable(_packs);

  Future<List<Pack>> loadPacks() async {
    await _ensureLoaded();
    return List<Pack>.from(_packs);
  }

  Future<void> _persistPacks() async {
    await _prefs.setStringList(
      _kPacks,
      _packs.map((p) => jsonEncode(p.toJson())).toList(),
    );
  }

  Future<void> upsertPack(Pack pack) async {
    await _ensureLoaded();
    final idx = _packs.indexWhere((p) => p.id == pack.id);
    if (idx >= 0) {
      _packs[idx] = pack;
    } else {
      _packs.add(pack);
    }
    await _persistPacks();
    notifyListeners();
  }

  /// Удаляет пак. Колоды внутри НЕ удаляются — они «выпадают» на верхний
  /// уровень (packId сбрасывается), чтобы случайно не потерять карточки.
  Future<void> deletePack(String packId) async {
    await _ensureLoaded();
    _packs.removeWhere((p) => p.id == packId);
    for (final d in _decks) {
      if (d.packId == packId) d.packId = null;
    }
    await _persistPacks();
    await _persistDecks();
    notifyListeners();
  }

  /// Кладёт колоду в пак (или вынимает, если [packId] == null).
  Future<void> setDeckPack(String deckId, String? packId) async {
    await _ensureLoaded();
    final idx = _decks.indexWhere((d) => d.id == deckId);
    if (idx < 0) return;
    _decks[idx].packId = packId;
    await _persistDecks();
    notifyListeners();
  }

  // ----------------------------- Сверка слов (дедуп по всей базе) --------------

  /// Множество «передов» всех карточек выбранного языка (в нижнем регистре) —
  /// чтобы отметить в разборе видео/книги слова, которые УЖЕ есть в любой
  /// колоде (системной или пользовательской).
  Set<String> knownFrontsForLanguage(String languageCode) {
    final deckIds = _decks
        .where((d) => d.languageCode == languageCode)
        .map((d) => d.id)
        .toSet();
    final out = <String>{};
    for (final c in _cards) {
      if (deckIds.contains(c.deckId)) {
        final f = c.front.trim().toLowerCase();
        if (f.isNotEmpty) out.add(f);
      }
    }
    return out;
  }

  /// Карты языка, сгруппированные по «переду» (нижний регистр) → карта с самым
  /// крепким запоминанием. Нужно анализу книги: по слову из текста мгновенно
  /// узнать, есть ли оно в словаре и насколько прочно закреплено (FSRS).
  Map<String, WordCard> cardsByFrontForLanguage(String languageCode) {
    final deckIds = _decks
        .where((d) => d.languageCode == languageCode)
        .map((d) => d.id)
        .toSet();
    final out = <String, WordCard>{};
    for (final c in _cards) {
      if (!deckIds.contains(c.deckId)) continue;
      final f = c.front.trim().toLowerCase();
      if (f.isEmpty) continue;
      final existing = out[f];
      // Если слово встречается в нескольких колодах — берём самую «выученную».
      if (existing == null || c.review.stability > existing.review.stability) {
        out[f] = c;
      }
    }
    return out;
  }

  /// Есть ли слово [front] уже в какой-либо колоде языка [languageCode].
  bool hasWordInLanguage(String front, String languageCode) {
    final f = front.trim().toLowerCase();
    if (f.isEmpty) return false;
    final deckIds = _decks
        .where((d) => d.languageCode == languageCode)
        .map((d) => d.id)
        .toSet();
    for (final c in _cards) {
      if (deckIds.contains(c.deckId) &&
          c.front.trim().toLowerCase() == f) {
        return true;
      }
    }
    return false;
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

  /// Все карты пака (из всех его колод) — для обучения по всему паку сразу.
  Future<List<WordCard>> cardsForPack(String packId) async {
    await _ensureLoaded();
    final deckIds =
        _decks.where((d) => d.packId == packId).map((d) => d.id).toSet();
    return _cards.where((c) => deckIds.contains(c.deckId)).toList();
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

  /// Переносит карты в другую колоду (напр. при разбивке по частям речи).
  Future<void> moveCards(Iterable<String> cardIds, String newDeckId) async {
    await _ensureLoaded();
    final ids = cardIds.toSet();
    if (ids.isEmpty) return;
    for (final c in _cards) {
      if (ids.contains(c.id)) c.deckId = newDeckId;
    }
    await _persistCards();
    notifyListeners();
  }

  /// Применяет оценку к карточке (FSRS) и сохраняет новое состояние повторения.
  Future<void> rateCard(WordCard card, Rating rating, DateTime now) async {
    card.review = Fsrs.instance.review(card.review, rating, now);
    await upsertCard(card);
  }

  // ----------------------------- Журнал занятий -----------------------------

  /// Журнал по дням (для стрика, кольца цели и статистики).
  ReviewLog get reviewLogSync => _log;
  Future<ReviewLog> reviewLog() async {
    await _ensureLoaded();
    return _log;
  }

  /// Записывает итог одной сессии в журнал за сегодня. Одна запись на диск.
  Future<void> logSession({
    required int reviews,
    required int correct,
    DateTime? at,
  }) async {
    if (reviews <= 0) return;
    await _ensureLoaded();
    final now = at ?? DateTime.now();
    final key = ReviewLog.keyFor(now);
    final days = Map<String, DayStat>.from(_log.days);
    days[key] = (days[key] ?? const DayStat()).plus(
      reviews: reviews,
      correct: correct,
    );
    // Держим журнал ограниченным (последние ~2 года), чтобы не рос вечно.
    if (days.length > 800) {
      final cutoff = ReviewLog.keyFor(now.subtract(const Duration(days: 730)));
      days.removeWhere((k, _) => k.compareTo(cutoff) < 0);
    }
    _log = ReviewLog(days);
    await _prefs.setString(_kReviewLog, jsonEncode(_log.toJson()));
    notifyListeners();
  }

  // ----------------------------- Рекорды «Подбор» -----------------------------

  /// Лучшее время игры «Подбор» для колоды (мс) или null.
  int? bestMatchMillis(String deckId) => _matchBest[deckId];

  /// Записывает результат игры «Подбор». Возвращает true, если это новый рекорд.
  Future<bool> recordMatchMillis(String deckId, int millis) async {
    await _ensureLoaded();
    final prev = _matchBest[deckId];
    if (prev != null && prev <= millis) return false;
    _matchBest = Map<String, int>.from(_matchBest)..[deckId] = millis;
    await _prefs.setString(_kMatchBest, jsonEncode(_matchBest));
    notifyListeners();
    return true;
  }

  // ----------------------------- Статистика чтения -----------------------------

  /// Всего секунд, проведённых в читалке.
  int get readingSeconds => _readSeconds;

  /// Оценка прочитанных слов (по продвижению позиции чтения).
  int get readingWords => _readWords;

  /// Прибавляет время/слова чтения (в конце сессии чтения).
  Future<void> addReading({int seconds = 0, int words = 0}) async {
    if (seconds <= 0 && words <= 0) return;
    await _ensureLoaded();
    _readSeconds += seconds < 0 ? 0 : seconds;
    _readWords += words < 0 ? 0 : words;
    await _prefs.setString(
      _kReadingStats,
      jsonEncode({'s': _readSeconds, 'w': _readWords}),
    );
    notifyListeners();
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

  Future<bool> amoledEnabled() async => await _prefs.getBool(_kAmoled) ?? false;
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

  // Ежедневное напоминание.
  Future<bool> reminderEnabled() async =>
      await _prefs.getBool(_kReminderOn) ?? false;
  Future<void> setReminderEnabled(bool value) async =>
      _prefs.setBool(_kReminderOn, value);

  Future<int> reminderHour() async => await _prefs.getInt(_kReminderHour) ?? 20;
  Future<int> reminderMinute() async =>
      await _prefs.getInt(_kReminderMinute) ?? 0;
  Future<void> setReminderTime(int hour, int minute) async {
    await _prefs.setInt(_kReminderHour, hour);
    await _prefs.setInt(_kReminderMinute, minute);
  }

  // Онбординг (первый запуск).
  Future<bool> onboarded() async => await _prefs.getBool(_kOnboarded) ?? false;
  Future<void> setOnboarded(bool value) async =>
      _prefs.setBool(_kOnboarded, value);

  // ----------------------------- Перевод / провайдеры -----------------------------

  Future<String?> translationConfigJson() async =>
      _prefs.getString(_kTransEndpoints);
  Future<void> setTranslationConfigJson(String value) async =>
      _prefs.setString(_kTransEndpoints, value);

  Future<String?> activeProviderId() async => _prefs.getString(_kTransActive);
  Future<void> setActiveProviderId(String value) async =>
      _prefs.setString(_kTransActive, value);

  // ----------------------------- Добавление слов из видео -----------------------------

  Future<String> addWordMode() async =>
      await _prefs.getString(_kAddWordMode) ?? 'manual';
  Future<void> setAddWordMode(String value) async =>
      _prefs.setString(_kAddWordMode, value);

  Future<String?> lastVideoDeckId() async =>
      _prefs.getString(_kLastVideoDeck);
  Future<void> setLastVideoDeckId(String value) async =>
      _prefs.setString(_kLastVideoDeck, value);

  /// Показывать ли баннер «Разобрать видео» на главном экране (по умолч. да).
  /// Даже если выключен — вход в разбор остаётся в иконке на верхней панели.
  Future<bool> showVideoBanner() async =>
      await _prefs.getBool(_kShowVideoBanner) ?? true;
  Future<void> setShowVideoBanner(bool value) async {
    await _prefs.setBool(_kShowVideoBanner, value);
    notifyListeners();
  }

  /// Спрашивать ли подтверждение перед разбивкой колоды по частям речи (на
  /// отдельные колоды). По умолчанию ДА — папки не создаются молча; можно
  /// отключить предупреждение галочкой «больше не спрашивать».
  static const String _kPosSplitAsk = 'posSplitAsk';
  Future<bool> posSplitAsk() async =>
      await _prefs.getBool(_kPosSplitAsk) ?? true;
  Future<void> setPosSplitAsk(bool value) async {
    await _prefs.setBool(_kPosSplitAsk, value);
    notifyListeners();
  }

  // ----------------------------- Бэкап -----------------------------

  /// Полный снимок данных (колоды + карты + настройки) как JSON-строка.
  Future<String> exportJson() async {
    await _ensureLoaded();
    return const JsonEncoder.withIndent('  ').convert({
      'version': 1,
      'decks': [for (final d in _decks) d.toJson()],
      'packs': [for (final p in _packs) p.toJson()],
      'cards': [for (final c in _cards) c.toJson()],
      'reviewLog': _log.toJson(),
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
    final packs = (data['packs'] as List? ?? [])
        .map((e) => Pack.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
    final cards = (data['cards'] as List? ?? [])
        .map((e) => WordCard.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
    _decks
      ..clear()
      ..addAll(decks);
    _packs
      ..clear()
      ..addAll(packs);
    _cards
      ..clear()
      ..addAll(cards);
    await _persistDecks();
    await _persistPacks();
    await _persistCards();
    if (data['reviewLog'] is Map) {
      _log = ReviewLog.fromJson(
        (data['reviewLog'] as Map).cast<String, dynamic>(),
      );
      await _prefs.setString(_kReviewLog, jsonEncode(_log.toJson()));
    }
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
    if (s['amoled'] is bool) {
      await _prefs.setBool(_kAmoled, s['amoled'] as bool);
    }
    if (s['uiLanguageCode'] is String) {
      await _prefs.setString(_kUiLanguage, s['uiLanguageCode'] as String);
    }
    if (s['selectedLanguage'] is String) {
      await _prefs.setString(
        _kSelectedLanguage,
        s['selectedLanguage'] as String,
      );
    }
    if (s['dailyGoal'] is num) {
      await _prefs.setInt(_kDailyGoal, (s['dailyGoal'] as num).toInt());
    }
    notifyListeners();
  }

  // ----------------------------- Колоды по умолчанию -----------------------------

  /// Версия набора колод по умолчанию. Повышаем, когда меняем стартовый контент,
  /// чтобы аккуратно обновить его у тех, кто ещё не трогал авто-колоды.
  static const int _seedVersion = 2;

  /// Сеет колоды по умолчанию (Первые слова / Глаголы / Еда и напитки / Одежда)
  /// при первом запуске. Данные лежат в ассете `assets/seed/en.json`.
  ///
  /// Для тех, у кого стоит старый мини-набор (`demo_en_*`) и он не тронут,
  /// набор тихо обновляется до нового — без потери собственных колод.
  Future<void> seedDemoIfNeeded() async {
    await _ensureLoaded();
    final storedVer = await _prefs.getInt(_kSeedVersion) ?? 0;
    final seededFlag = await _prefs.getBool(_kSeededDemo) ?? false;

    // Первый запуск — сеем свежие колоды по умолчанию.
    if (!seededFlag && _decks.isEmpty) {
      await _seedDefaults();
      return;
    }

    // Апгрейд старого авто-набора (5+4 слова) до нового, если он не изменён.
    final onlyOldAuto =
        _decks.isNotEmpty && _decks.every((d) => d.id.startsWith('demo_en_'));
    if (storedVer < _seedVersion && onlyOldAuto) {
      _decks.removeWhere((d) => d.id.startsWith('demo_en_'));
      _cards.removeWhere((c) => c.deckId.startsWith('demo_en_'));
      await _seedDefaults();
      // Уже работавший пользователь — онбординг не показываем.
      await _prefs.setBool(_kOnboarded, true);
      return;
    }

    // Иначе просто фиксируем флаги (существующий пользователь).
    await _prefs.setBool(_kSeededDemo, true);
    await _prefs.setInt(_kSeedVersion, _seedVersion);
    await _prefs.setBool(_kOnboarded, true);
  }

  Future<void> _seedDefaults() async {
    final loaded = await _loadSeedDecks();
    if (loaded.isEmpty) return; // ассет не загрузился — ничего не портим
    for (final entry in loaded) {
      _decks.add(entry.$1);
      _cards.addAll(entry.$2);
    }
    await _persistDecks();
    await _persistCards();
    await _prefs.setBool(_kSeededDemo, true);
    await _prefs.setInt(_kSeedVersion, _seedVersion);
    notifyListeners();
  }

  /// Разбирает `assets/seed/en.json` в список (колода, карточки).
  Future<List<(Deck, List<WordCard>)>> _loadSeedDecks() async {
    String raw;
    try {
      raw = await rootBundle.loadString('assets/seed/en.json');
    } catch (_) {
      return const [];
    }
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final lang = data['lang'] as String? ?? 'en';
      final out = <(Deck, List<WordCard>)>[];
      var order = 0;
      for (final d in (data['decks'] as List? ?? const [])) {
        final m = (d as Map).cast<String, dynamic>();
        final deckId = m['id'] as String? ?? 'seed_en_$order';
        final deck = Deck(
          id: deckId,
          languageCode: lang,
          name: m['name'] as String? ?? '—',
          colorValue: (m['color'] as num?)?.toInt() ?? 0xFF2E7D5B,
          shapeIndex: (m['shape'] as num?)?.toInt() ?? 0,
          createdAt: order,
        );
        final cards = <WordCard>[];
        var i = 0;
        for (final c in (m['cards'] as List? ?? const [])) {
          final cm = (c as Map).cast<String, dynamic>();
          final front = (cm['front'] as String? ?? '').trim();
          final back = (cm['back'] as String? ?? '').trim();
          if (front.isEmpty || back.isEmpty) continue;
          cards.add(
            WordCard(
              id: '${deckId}_$i',
              deckId: deckId,
              front: front,
              back: back,
              example: (cm['example'] as String? ?? '').trim(),
            ),
          );
          i++;
        }
        out.add((deck, cards));
        order++;
      }
      return out;
    } catch (_) {
      return const [];
    }
  }
}
