import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/strings.dart';
import '../models/deck.dart';
import '../models/fsrs.dart';
import '../models/pack.dart';
import '../models/review_event.dart';
import '../models/review_log.dart';
import '../models/word_card.dart';
import '../utils/day.dart';
import 'auto_grade.dart';
import 'billing_service.dart';
import 'card_images.dart';
import 'license_service.dart';
import 'link_propagation.dart';
import 'local_db.dart';
import 'pro.dart';
import 'pos.dart';
import 'starter_decks.dart';
import 'pos_dictionary.dart';

/// Единый слой доступа к данным Fern.
///
/// ДНК ScoreMaster (там это был `GameRepository`). Хранилище — **SQLite**
/// ([LocalDb]) для «тяжёлых» коллекций (колоды, паки, карточки) + **кэш в
/// памяти**, а мелкие одиночные значения (настройки, журнал по дням, рекорды,
/// статистика чтения) остаются в `SharedPreferencesAsync`:
///
/// * SQLite пишет ОДНУ карту одним `UPDATE` одной строки — прежде каждая оценка
///   переписывала весь словарь на диск (O(N) на свайп, лаги и риск ANR на
///   тысячах карт). Плюс индекс по сроку повтора и `updated_at` на строку —
///   фундамент под виджет/уведомления и будущий честный синк.
/// * `SharedPreferencesAsync` пишет НАДЁЖНО — метод завершается, когда запись
///   реально дошла до нативного стора (в отличие от старого `apply()`, который
///   стрелял «в фон»: смахнул приложение сразу после ввода слова — сброс не
///   успевал, слово пропадало).
/// * Кэш в памяти (`_decks`/`_cards`) — чтения мгновенные и консистентные, а
///   `notifyListeners()` больше не заставляет каждый экран заново парсить весь
///   JSON.
///
/// После каждой мутации зовём [notifyListeners]; экраны слушают репозиторий и
/// перезагружаются — данные на всех вкладках всегда актуальны.
class DeckRepository extends ChangeNotifier {
  DeckRepository._();
  static final DeckRepository instance = DeckRepository._();

  /// Путь к файлу БД, переопределяемый в тестах (изоляция между кейсами). На
  /// устройстве — null, [LocalDb] берёт каталог документов приложения.
  @visibleForTesting
  static String? debugDatabasePath;

  /// БД колод/паков/карт. Создаётся в [init].
  LocalDb? _db;

  static const String _kDecks = 'decks';
  static const String _kPacks = 'packs';
  static const String _kCards = 'cards';
  static const String _kSelectedLanguage = 'selectedLanguage';
  static const String _kCustomLanguages = 'customLanguages'; // JSON [{code,..}]
  static const String _kPinnedLanguages = 'pinnedLanguages'; // JSON [code,..]
  static const String _kSeededDemo = 'seededDemo';
  static const String _kSeedVersion = 'seedVersion';
  static const String _kReviewLog = 'reviewLog';
  static const String _kFrozenDays = 'frozenDays'; // дни под серией-щитом
  static const String _kStreakFreezes = 'streakFreezes'; // остаток щитов
  static const String _kFreezeGrant = 'freezeGrantLevel'; // сколько уже начислено
  static const String _kGoalCelebrated = 'goalCelebratedDate';
  static const int _maxFreezes = 5;
  static const int _startFreezes = 2;
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
  // Ключ Fern Pro. Пишет и читает его LicenseService; репозиторий знает имя
  // только чтобы класть ключ в бэкап и доставать обратно.
  static const String _kLicenseKey = 'licenseKey';

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
  // Флаг разовой миграции коллекций из prefs в SQLite.
  static const String _kMigratedSqliteV1 = 'migratedToSqliteV1';
  // Пере-определение части речи по офлайн-словарю (исправляет ошибки эвристик).
  // Заменяет прежние разовые чистки part-of-speech (posMigratedV2 и ранее).
  static const String _kPosMigratedV3 = 'posMigratedV3';
  // Момент последнего авто-бэкапа (мс) — см. BackupService.autoBackupIfDue.
  static const String _kLastAutoBackup = 'lastAutoBackupMs';
  // Разовая простановка ключей локализации встроенным колодам (см. миграцию).
  static const String _kBuiltInKeysV1 = 'builtinKeysV1';

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
  final Set<String> _frozenDays = {};
  bool _justFroze = false; // щит только что израсходован — показать уведомление 1 раз
  Map<String, int> _matchBest = {};
  int _readSeconds = 0;
  int _readWords = 0;
  int _reinforcedByReading = 0;
  bool _loaded = false;

  /// Один раз загружает данные в память (и мигрирует со старых сторов).
  /// Вызывать до `runApp`. Идемпотентно.
  Future<void> init() async {
    if (_loaded) return;
    // 1) старый apply()-стор → надёжный async-стор (как было).
    await _migrateLegacyIfNeeded();
    // 2) открываем SQLite и разово переносим в неё коллекции из prefs.
    _db = LocalDb(path: debugDatabasePath);
    await _db!.open();
    await _migratePrefsToSqliteIfNeeded();
    // 3) кэш в память из SQLite (мелкие значения — из prefs, как раньше).
    _decks
      ..clear()
      ..addAll(_db!.allDecks());
    _packs
      ..clear()
      ..addAll(_db!.allPacks());
    _cards
      ..clear()
      ..addAll(_db!.allCards());
    _log = _decodeLog(await _prefs.getString(_kReviewLog));
    _frozenDays
      ..clear()
      ..addAll(_decodeStringList(await _prefs.getString(_kFrozenDays)));
    _matchBest = _decodeMatchBest(await _prefs.getString(_kMatchBest));
    _decodeReading(await _prefs.getString(_kReadingStats));
    await _migratePosIfNeeded();
    await _migrateBuiltInKeysIfNeeded();
    _loaded = true;
  }

  /// Отодвигает повреждённый файл БД и открывает пустую на его месте.
  /// Единственный способ запустить приложение, когда `init()` упал на битой
  /// базе: иначе экран остаётся чёрным и данные не достать даже из бэкапа.
  Future<void> recoverFromCorruptedDatabase() async {
    _loaded = false;
    await LocalDb(path: debugDatabasePath).quarantineFile();
    _db = null;
    await init();
  }

  /// Разово переносит колоды/паки/карты из prefs в SQLite. Защита двойная:
  /// импорт идёт ТОЛЬКО в пустую БД (никогда не затираем уже перенесённые
  /// данные) и только один раз (флаг). Старые prefs-ключи не удаляем — остаются
  /// «холодным» запасом на одну версию (после переноса они больше не читаются).
  Future<void> _migratePrefsToSqliteIfNeeded() async {
    final db = _db!;
    if (await _prefs.getBool(_kMigratedSqliteV1) ?? false) return;
    if (db.deckCount() == 0 && db.cardCount() == 0) {
      final decks =
          _decodeDecks(await _prefs.getStringList(_kDecks) ?? const []);
      final packs =
          _decodePacks(await _prefs.getStringList(_kPacks) ?? const []);
      final cards =
          _decodeCards(await _prefs.getStringList(_kCards) ?? const []);
      if (decks.isNotEmpty || packs.isNotEmpty || cards.isNotEmpty) {
        db.replaceAllDecks(decks);
        db.replaceAllPacks(packs);
        db.replaceAllCards(cards);
      }
    }
    await _prefs.setBool(_kMigratedSqliteV1, true);
  }

  /// Пере-определяет часть речи по офлайн-словарю (Moby POS) — исправляет
  /// ошибки прежних эвристик (напр. `library`/`salary` были помечены как
  /// прилагательные) и заодно снимает вклеенную в слово метку. Перетегируем ВСЕ
  /// английские карты, но перезаписываем тег только при уверенном ответе
  /// словаря/эвристики (чтобы не стереть верные метки без покрытия).
  Future<void> _migratePosIfNeeded() async {
    if (await _prefs.getBool(_kPosMigratedV3) ?? false) return;
    if (_cards.isNotEmpty) {
      await PosDictionary.instance.ensureLoaded('en');
      final deckLang = {for (final d in _decks) d.id: d.languageCode};
      final changed = <WordCard>[];
      for (final c in _cards) {
        final lang = deckLang[c.deckId] ?? 'en';
        final stripped = PosDetect.strip(c.front);
        if (stripped.$2 != null) {
          c.front = stripped.$1;
          c.pos = stripped.$2!;
          changed.add(c);
          continue;
        }
        final detected = PosDetect.detect(c.front, languageCode: lang);
        if (detected.isNotEmpty && detected != c.pos) {
          c.pos = detected;
          changed.add(c);
        }
      }
      if (changed.isNotEmpty) _db!.upsertCards(changed);
    }
    await _prefs.setBool(_kPosMigratedV3, true);
  }

  /// Разово помечает уже созданные встроенные колоды ключом локализации.
  ///
  /// Колоды, посеянные прошлыми версиями, лежат в базе без ключа, поэтому
  /// переводить их было не по чему. Узнаём их по id: наборы по умолчанию —
  /// `seed_*`, стартовые — `starter_*` (у всех стартовых один ключ имени).
  Future<void> _migrateBuiltInKeysIfNeeded() async {
    if (await _prefs.getBool(_kBuiltInKeysV1) ?? false) return;
    final changed = <Deck>[];
    for (final d in _decks) {
      if (d.nameKey != null) continue;
      if (d.id.startsWith('seed_')) {
        d.nameKey = _seedNameKeyById[d.id];
      } else if (d.id.startsWith('starter_')) {
        d.nameKey = 'seed_deck_first_words';
      }
      if (d.nameKey != null) changed.add(d);
    }
    for (final d in changed) {
      _db!.upsertDeck(d);
    }
    await _prefs.setBool(_kBuiltInKeysV1, true);
  }

  /// Ключи имён наборов по умолчанию (совпадают с assets/seed/en.json).
  static const Map<String, String> _seedNameKeyById = {
    'seed_en_first': 'seed_deck_first_words',
    'seed_en_verbs': 'seed_deck_verbs',
    'seed_en_food': 'seed_deck_food',
    'seed_en_clothes': 'seed_deck_clothes',
  };

  // ------------------- Локализация встроенных колод -------------------

  /// Переводит встроенные колоды (стартовые наборы и наборы по умолчанию) на
  /// текущий язык интерфейса.
  ///
  /// Раньше перевод выбирался ОДИН раз — в момент посева — и намертво писался в
  /// базу: сменив язык приложения, человек продолжал видеть «hola → привет» с
  /// английским интерфейсом. Теперь имя колоды берётся из ключа, а перевод
  /// карточки — из ассета, где лежат все семь языков.
  ///
  /// Правки пользователя неприкосновенны: карточка обновляется, только если её
  /// текущий перевод совпадает с одним из наших (значит, её не меняли руками).
  Future<void> relocalizeBuiltIns() async {
    if (_decks.every((d) => !d.isBuiltIn)) return;

    // Ассеты: язык → перёд карточки → карта переводов.
    final assets = <String, Map<String, Map>>{};
    Future<void> loadAsset(String path) async {
      try {
        final raw = await rootBundle.loadString(path);
        final data = jsonDecode(raw) as Map<String, dynamic>;
        final lang = data['lang'] as String? ?? 'en';
        final byFront = assets.putIfAbsent(lang, () => {});
        for (final d in (data['decks'] as List? ?? const [])) {
          for (final c in ((d as Map)['cards'] as List? ?? const [])) {
            final cm = (c as Map);
            final front = (cm['front'] as String? ?? '').trim();
            final back = cm['back'];
            if (front.isNotEmpty && back is Map) byFront[front] = back;
          }
        }
      } catch (_) {
        // Ассета нет или он битый — просто не трогаем эти карточки.
      }
    }

    await loadAsset('assets/seed/en.json');
    for (final code in StarterDecks.availableLanguages) {
      await loadAsset('assets/starter/$code.json');
    }
    if (assets.isEmpty) return;

    final changedDecks = <Deck>[];
    final changedCards = <WordCard>[];

    for (final deck in _decks) {
      if (!deck.isBuiltIn) continue;

      final title = localizedDeckName(nameKey: deck.nameKey, name: deck.name);
      if (title.isNotEmpty && title != deck.name) {
        deck.name = title;
        changedDecks.add(deck);
      }

      final byFront = assets[deck.languageCode];
      if (byFront == null) continue;
      for (final card in _cards.where((c) => c.deckId == deck.id)) {
        final variants = byFront[card.front];
        if (variants == null) continue;
        final ours = variants.values.whereType<String>();
        // Перевод не наш → человек правил карточку сам, не вмешиваемся.
        if (!ours.contains(card.back)) continue;
        final fresh = localizedBack(variants).trim();
        if (fresh.isNotEmpty && fresh != card.back) {
          card.back = fresh;
          changedCards.add(card);
        }
      }
    }

    if (changedDecks.isEmpty && changedCards.isEmpty) return;
    for (final d in changedDecks) {
      _db!.upsertDeck(d);
    }
    if (changedCards.isNotEmpty) _db!.upsertCards(changedCards);
    notifyListeners();
  }

  void _decodeReading(String? raw) {
    _readSeconds = 0;
    _readWords = 0;
    _reinforcedByReading = 0;
    if (raw == null || raw.isEmpty) return;
    try {
      final m = (jsonDecode(raw) as Map).cast<String, dynamic>();
      _readSeconds = (m['s'] as num?)?.toInt() ?? 0;
      _readWords = (m['w'] as num?)?.toInt() ?? 0;
      _reinforcedByReading = (m['r'] as num?)?.toInt() ?? 0;
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

  List<String> _decodeStringList(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      return [
        for (final e in (jsonDecode(raw) as List))
          if (e is String && e.isNotEmpty) e,
      ];
    } catch (_) {
      return const [];
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
    // Закрываем соединение (данные остаются в файле — как «убитое» приложение):
    // следующий init() поднимет их заново. Файл БД чистится в тестовой обвязке.
    _db?.close();
    _db = null;
    _decks.clear();
    _packs.clear();
    _cards.clear();
    _log = ReviewLog.empty();
    _frozenDays.clear();
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
    _db!.replaceAllDecks(_decks);
    notifyListeners();
  }

  Future<void> upsertDeck(Deck deck) async {
    await _ensureLoaded();
    final idx = _decks.indexWhere((d) => d.id == deck.id);
    if (idx >= 0) {
      _decks[idx] = deck;
    } else {
      _decks.add(deck);
    }
    _db!.upsertDeck(deck);
    notifyListeners();
  }

  /// Удаляет колоду и все её карточки.
  Future<void> deleteDeck(String deckId) async {
    await _ensureLoaded();
    _decks.removeWhere((d) => d.id == deckId);
    for (final c in _cards.where((c) => c.deckId == deckId)) {
      if (c.image.isNotEmpty) await CardImages.deleteFor(c.id);
    }
    _cards.removeWhere((c) => c.deckId == deckId);
    _db!.deleteDeck(deckId);
    _db!.deleteCardsForDeck(deckId);
    notifyListeners();
  }

  // ----------------------------- Паки -----------------------------

  /// Синхронный доступ к кэшу паков (после [init]).
  List<Pack> get packs => List<Pack>.unmodifiable(_packs);

  Future<List<Pack>> loadPacks() async {
    await _ensureLoaded();
    return List<Pack>.from(_packs);
  }

  Future<void> upsertPack(Pack pack) async {
    await _ensureLoaded();
    final idx = _packs.indexWhere((p) => p.id == pack.id);
    if (idx >= 0) {
      _packs[idx] = pack;
    } else {
      _packs.add(pack);
    }
    _db!.upsertPack(pack);
    notifyListeners();
  }

  /// Удаляет пак. Колоды внутри НЕ удаляются — они «выпадают» на верхний
  /// уровень (packId сбрасывается), чтобы случайно не потерять карточки.
  Future<void> deletePack(String packId) async {
    await _ensureLoaded();
    _packs.removeWhere((p) => p.id == packId);
    final touched = <Deck>[];
    for (final d in _decks) {
      if (d.packId == packId) {
        d.packId = null;
        touched.add(d);
      }
    }
    _db!.deletePack(packId);
    for (final d in touched) {
      _db!.upsertDeck(d);
    }
    notifyListeners();
  }

  /// Кладёт колоду в пак (или вынимает, если [packId] == null).
  Future<void> setDeckPack(String deckId, String? packId) async {
    await _ensureLoaded();
    final idx = _decks.indexWhere((d) => d.id == deckId);
    if (idx < 0) return;
    _decks[idx].packId = packId;
    _db!.upsertDeck(_decks[idx]);
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

  /// ЗАМЕНЯЕТ ВЕСЬ словарь переданным списком.
  ///
  /// Годится только там, где на руках действительно все карточки: посев,
  /// восстановление из бэкапа. Вызов с частичным списком стирает остальное
  /// безвозвратно — для правки нескольких карточек есть [updateCards].
  Future<void> saveCards(List<WordCard> cards) async {
    await _ensureLoaded();
    _cards
      ..clear()
      ..addAll(cards);
    _db!.replaceAllCards(_cards);
    notifyListeners();
  }

  /// Точечно обновляет перечисленные карточки, остальные не трогает.
  Future<void> updateCards(List<WordCard> cards) async {
    if (cards.isEmpty) return;
    await _ensureLoaded();
    for (final card in cards) {
      final at = _cards.indexWhere((c) => c.id == card.id);
      if (at >= 0) {
        _cards[at] = card;
      } else {
        _cards.add(card);
      }
    }
    _db!.upsertCards(cards);
    notifyListeners();
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
    // Одна строка на диск — раньше здесь переписывался весь словарь.
    _db!.upsertCard(card);
    notifyListeners();
  }

  /// Добавляет пачку карточек за одну транзакцию (быстрое добавление).
  Future<void> addCards(Iterable<WordCard> cards) async {
    await _ensureLoaded();
    final list = cards.toList();
    _cards.addAll(list);
    _db!.upsertCards(list);
    notifyListeners();
  }

  Future<void> deleteCard(String cardId) async {
    await _ensureLoaded();
    _cards.removeWhere((c) => c.id == cardId);
    _db!.deleteCard(cardId);
    // Картинка карточки — тоже её данные: уходит вместе с ней, иначе каталог
    // копит файлы-сироты.
    await CardImages.deleteFor(cardId);
    notifyListeners();
  }

  /// Переносит карты в другую колоду (напр. при разбивке по частям речи).
  Future<void> moveCards(Iterable<String> cardIds, String newDeckId) async {
    await _ensureLoaded();
    final ids = cardIds.toSet();
    if (ids.isEmpty) return;
    final moved = <WordCard>[];
    for (final c in _cards) {
      if (ids.contains(c.id)) {
        c.deckId = newDeckId;
        moved.add(c);
      }
    }
    if (moved.isNotEmpty) _db!.upsertCards(moved);
    notifyListeners();
  }

  /// Применяет оценку к карточке (FSRS), пишет событие в журнал повторов и
  /// сохраняет новое состояние.
  Future<void> rateCard(
    WordCard card,
    Rating rating,
    DateTime now, {
    int? answerMs,
    int? kind,
  }) async {
    final prev = card.review;
    final wasNew = prev.isNew;
    final elapsedDays = prev.lastReview == null
        ? 0.0
        : (now.difference(prev.lastReview!).inSeconds / 86400.0)
            .clamp(0.0, double.infinity);
    final stateBefore = prev.state.index;

    // Ключ разброса — id карточки: иначе слова, введённые за один вечер,
    // получают одну и ту же дату повтора.
    card.review = Fsrs.instance.review(prev, rating, now, fuzzKey: card.id);
    await upsertCard(card);
    // Сырое событие — фундамент под персональный оптимизатор FSRS.
    _db!.logReview(ReviewEvent(
      cardId: card.id,
      ts: now.millisecondsSinceEpoch,
      grade: rating.grade,
      elapsedDays: elapsedDays.toDouble(),
      stateBefore: stateBefore,
      answerMs: answerMs,
      kind: kind,
    ));
    // Новая карта впервые показана → расходуем дневной лимит новых.
    if (wasNew) await markNewIntroduced(1, now);

    // Настоящий срыв на зрелой карте — повод спросить пораньше её соседей по
    // смыслу: слова одного гнезда осыпаются вместе.
    if (rating == Rating.again && stateBefore == FsrsState.review.index) {
      await _spreadLapse(card, now);
    }
  }

  Future<void> _spreadLapse(WordCard card, DateTime now) async {
    final deck = _decks.where((d) => d.id == card.deckId).firstOrNull;
    if (deck == null) return;
    final pool = await cardsForLanguage(deck.languageCode);
    final touched = LinkPropagation.afterLapse(
      card,
      pool,
      deck.languageCode,
      now: now,
    );
    if (touched.isNotEmpty) await updateCards(touched);
  }

  // ----------------------------- Журнал занятий -----------------------------

  /// Журнал по дням (для стрика, кольца цели и статистики). Отдаём копию с
  /// учётом замороженных щитом дней (внутренний [_log] — только реальные занятия).
  ReviewLog get reviewLogSync => ReviewLog(_log.days, frozen: _frozenDays);
  Future<ReviewLog> reviewLog() async {
    await _ensureLoaded();
    return ReviewLog(_log.days, frozen: _frozenDays);
  }

  // ----------------------------- Серия-щит (заморозка) -----------------------------

  /// Остаток «щитов» серии (по умолчанию — небольшой стартовый запас).
  Future<int> streakFreezes() async {
    await _ensureLoaded();
    return await _prefs.getInt(_kStreakFreezes) ?? _startFreezes;
  }

  Future<void> _setStreakFreezes(int n) async =>
      _prefs.setInt(_kStreakFreezes, n.clamp(0, _maxFreezes));

  /// Начисляет +1 щит за каждые 7 дней занятий (до потолка). Идемпотентно —
  /// уровень уже начисленного хранится отдельно.
  Future<void> _maybeGrantFreeze() async {
    final level = await _prefs.getInt(_kFreezeGrant) ?? 0;
    final earned = _log.daysStudied ~/ 7;
    if (earned > level) {
      final cur = await _prefs.getInt(_kStreakFreezes) ?? _startFreezes;
      await _setStreakFreezes(cur + (earned - level));
      await _prefs.setInt(_kFreezeGrant, earned);
    }
  }

  /// Если вчера пропущено, а серия была — тратит один щит, «замораживая» вчера,
  /// чтобы серия не оборвалась. Возвращает true, если щит израсходован.
  /// Вызывается на старте приложения.
  Future<bool> protectStreakIfNeeded([DateTime? at]) async {
    await _ensureLoaded();
    final now = at ?? DateTime.now();
    final today = startOfDay(now);
    final yest = addDays(today, -1);
    final before = addDays(today, -2);
    final log = reviewLogSync;
    if (log.activeOn(today) || log.activeOn(yest)) return false; // ничего не рвётся
    if (!log.activeOn(before)) return false; // серии для спасения нет
    final tokens = await streakFreezes();
    if (tokens <= 0) return false;
    _frozenDays.add(ReviewLog.keyFor(yest));
    await _prefs.setString(_kFrozenDays, jsonEncode(_frozenDays.toList()));
    await _setStreakFreezes(tokens - 1);
    _justFroze = true;
    notifyListeners();
    return true;
  }

  /// Разово сообщает, что щит только что спас серию (для уведомления на UI).
  bool consumeFreezeNotice() {
    final v = _justFroze;
    _justFroze = false;
    return v;
  }

  /// true — если дневная цель достигнута сегодня и ещё не праздновалась (тогда
  /// помечает, чтобы салют показать один раз в день).
  Future<bool> consumeDailyGoalCelebration([DateTime? at]) async {
    await _ensureLoaded();
    final now = at ?? DateTime.now();
    final goal = await dailyGoal();
    if (goal <= 0 || _log.reviewsOn(now) < goal) return false;
    final key = ReviewLog.keyFor(now);
    if (await _prefs.getString(_kGoalCelebrated) == key) return false;
    await _prefs.setString(_kGoalCelebrated, key);
    return true;
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
      final cutoff = ReviewLog.keyFor(addDays(now, -730));
      days.removeWhere((k, _) => k.compareTo(cutoff) < 0);
    }
    _log = ReviewLog(days);
    await _prefs.setString(_kReviewLog, jsonEncode(_log.toJson()));
    await _maybeGrantFreeze(); // начислить щит за пройденные рубежи дней
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

  /// Сколько раз слова подкрепились встречей в тексте.
  int get reinforcedByReading => _reinforcedByReading;

  /// Прибавляет время/слова чтения (в конце сессии чтения).
  Future<void> addReading({int seconds = 0, int words = 0}) async {
    if (seconds <= 0 && words <= 0) return;
    await _ensureLoaded();
    _readSeconds += seconds < 0 ? 0 : seconds;
    _readWords += words < 0 ? 0 : words;
    await _persistReading();
    notifyListeners();
  }

  /// Отмечает, что [n] карточек подкрепились чтением.
  Future<void> addReinforcedByReading(int n) async {
    if (n <= 0) return;
    await _ensureLoaded();
    _reinforcedByReading += n;
    await _persistReading();
    notifyListeners();
  }

  Future<void> _persistReading() => _prefs.setString(
        _kReadingStats,
        jsonEncode({
          's': _readSeconds,
          'w': _readWords,
          'r': _reinforcedByReading,
        }),
      );

  /// Все карты языка (по колодам этого языка).
  Future<List<WordCard>> cardsForLanguage(String languageCode) async {
    await _ensureLoaded();
    final deckIds = _decks
        .where((d) => d.languageCode == languageCode)
        .map((d) => d.id)
        .toSet();
    return _cards.where((c) => deckIds.contains(c.deckId)).toList();
  }

  // ----------------------------- Выбранный язык -----------------------------

  Future<String?> selectedLanguageCode() async =>
      _prefs.getString(_kSelectedLanguage);

  Future<void> setSelectedLanguageCode(String code) async {
    await _prefs.setString(_kSelectedLanguage, code);
    notifyListeners();
  }

  // Свои изучаемые языки и закрепления (управляет LanguageRegistry).
  Future<String?> customLanguagesRaw() async =>
      _prefs.getString(_kCustomLanguages);
  Future<void> setCustomLanguagesRaw(String json) async =>
      _prefs.setString(_kCustomLanguages, json);
  Future<String?> pinnedLanguagesRaw() async =>
      _prefs.getString(_kPinnedLanguages);
  Future<void> setPinnedLanguagesRaw(String json) async =>
      _prefs.setString(_kPinnedLanguages, json);

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

  // ------------------------- Лимиты подачи (SRS) -------------------------
  // Раздельные лимиты в духе Anki (а не один «goal»): новые вводятся стабильно
  // (не «0 новых в тяжёлый день»), а поток повторов ограничен (не «лавина» на
  // 300 карт после перерыва).
  static const String _kNewPerDay = 'newPerDay';
  static const String _kMaxReviews = 'maxReviewsPerSession';
  static const String _kNewIntroDate = 'newIntroDate';
  static const String _kNewIntroCount = 'newIntroCount';

  /// Сколько НОВЫХ карт вводить в день (по умолч. 12). 0 — не ограничивать.
  Future<int> newPerDay() async => await _prefs.getInt(_kNewPerDay) ?? 12;
  Future<void> setNewPerDay(int value) async {
    await _prefs.setInt(_kNewPerDay, value.clamp(0, 999));
    notifyListeners();
  }

  /// Потолок повторов на одну сессию (по умолч. 100) — защита от «лавины».
  /// Остальные просроченные подхватит следующая сессия («Ещё сессия»).
  Future<int> maxReviews() async => await _prefs.getInt(_kMaxReviews) ?? 100;
  Future<void> setMaxReviews(int value) async {
    await _prefs.setInt(_kMaxReviews, value.clamp(10, 999));
    notifyListeners();
  }

  // ------------------------- Персонализация FSRS -------------------------
  static const String _kRetention = 'requestRetention';
  static const String _kFsrsWeights = 'fsrsWeights';

  /// Целевой уровень удержания (0.85..0.97). Выше — интервалы короче, повторов
  /// больше, но помнишь лучше. По умолчанию 0.9.
  Future<double> requestRetention() async =>
      await _prefs.getDouble(_kRetention) ?? 0.9;
  Future<void> setRequestRetention(double v) async {
    await _prefs.setDouble(_kRetention, v.clamp(0.80, 0.97));
    Fsrs.instance.requestRetention = v.clamp(0.80, 0.97);
    notifyListeners();
  }

  /// Персональные веса FSRS (или null — дефолтные).
  Future<List<double>?> fsrsWeights() async {
    final raw = await _prefs.getString(_kFsrsWeights);
    if (raw == null || raw.isEmpty) return null;
    try {
      return [for (final v in jsonDecode(raw) as List) (v as num).toDouble()];
    } catch (_) {
      return null;
    }
  }

  Future<void> setFsrsWeights(List<double>? weights) async {
    if (weights == null) {
      await _prefs.remove(_kFsrsWeights);
      Fsrs.instance.setWeights(null);
    } else {
      await _prefs.setString(_kFsrsWeights, jsonEncode(weights));
      Fsrs.instance.setWeights(weights);
    }
    notifyListeners();
  }

  /// Загружает персональные настройки FSRS в планировщик (зовётся на старте).
  Future<void> applyFsrsSettings() async {
    Fsrs.instance.requestRetention = await requestRetention();
    Fsrs.instance.setWeights(await fsrsWeights());
  }

  /// Число накопленных событий повтора (для готовности оптимизатора).
  Future<int> reviewEventCount() async {
    await _ensureLoaded();
    return _db!.reviewEventCount();
  }

  /// Все события повтора (для оптимизатора).
  Future<List<ReviewEvent>> reviewEvents() async {
    await _ensureLoaded();
    return _db!.allReviewEvents();
  }

  /// Сколько новых карт уже введено СЕГОДНЯ (для остатка дневного лимита).
  Future<int> newIntroducedToday([DateTime? now]) async {
    final today = ReviewLog.keyFor(now ?? DateTime.now());
    final date = await _prefs.getString(_kNewIntroDate);
    if (date != today) return 0;
    return await _prefs.getInt(_kNewIntroCount) ?? 0;
  }

  /// Отмечает [delta] введённых сегодня новых карт (обнуляет счётчик при смене
  /// дня). Зовётся, когда новая карта впервые оценивается.
  Future<void> markNewIntroduced([int delta = 1, DateTime? now]) async {
    final today = ReviewLog.keyFor(now ?? DateTime.now());
    final date = await _prefs.getString(_kNewIntroDate);
    final base = date == today ? (await _prefs.getInt(_kNewIntroCount) ?? 0) : 0;
    await _prefs.setString(_kNewIntroDate, today);
    await _prefs.setInt(_kNewIntroCount, base + delta);
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

  /// Режим двух кнопок: вместо четырёх ступеней — «Не помню / Помню», а
  /// ступень подбирает [AutoGrade] по времени ответа. По умолчанию выключен:
  /// кто привык к четырём кнопкам, тот их и увидит.
  static const String _kTwoButtonRating = 'twoButtonRating';
  Future<bool> twoButtonRating() async =>
      await _prefs.getBool(_kTwoButtonRating) ?? false;
  Future<void> setTwoButtonRating(bool value) async {
    await _prefs.setBool(_kTwoButtonRating, value);
    notifyListeners();
  }

  /// Личный темп ответа — основа автооценки. Берём последние ответы, а не всю
  /// историю: темп человека меняется, да и грузить весь журнал на каждой сессии
  /// незачем.
  Future<AutoGrade> autoGrade() async {
    await _ensureLoaded();
    return AutoGrade.fromSamples(_db!.recentAnswerTimes());
  }

  // ----------------------------- Удаление всех данных -----------------------------

  /// Полностью стирает данные приложения (как свежая установка): БД
  /// (колоды/паки/карты/журнал повторов), ВСЕ настройки и флаги, кэш в памяти и
  /// персонализацию FSRS. Библиотеку книг/видео очищает вызывающая сторона
  /// (`SourceLibrary.wipeAll` — у неё файлы на диске). Необратимо.
  Future<void> wipeAllData() async {
    await _ensureLoaded();
    _db!.wipeAll();
    await CardImages.wipeAll();
    // Счётчик израсходованных бесплатных разборов переживает стирание:
    // «удалить все данные» — про свои колоды и книги, а не про покупку.
    // Иначе кнопка в настройках возвращала бы бесплатную книгу без конца.
    final freeUsed = await Pro.usedSources();
    // Покупка переживает стирание по той же причине, только цена ошибки выше.
    // `_prefs.clear()` уносил и ключ Pro, и флаг покупки из магазина: человек
    // оставался без оплаченного, а вернуть ключ можно было только из переписки
    // с ботом. Экран при этом ещё показывал «Pro активен» — статус живёт в
    // памяти сервисов и расходится с диском до перезапуска.
    final licenseKey = LicenseService.instance.key;
    final purchased = BillingService.instance.owned;
    // Чистим оба prefs-стора (async + legacy) целиком, включая флаги миграций.
    await _prefs.clear();
    try {
      await (await SharedPreferences.getInstance()).clear();
    } catch (_) {
      /* legacy-стор недоступен — не критично */
    }
    await Pro.restoreUsedSources(freeUsed);
    if (licenseKey != null && licenseKey.isNotEmpty) {
      await LicenseService.instance.apply(licenseKey);
    }
    if (purchased) await BillingService.instance.persistOwned();
    _decks.clear();
    _packs.clear();
    _cards.clear();
    _log = ReviewLog.empty();
    _frozenDays.clear();
    _matchBest = {};
    _readSeconds = 0;
    _readWords = 0;
    _reinforcedByReading = 0;
    // Возвращаем планировщик к дефолтам (снятая персонализация).
    Fsrs.instance.requestRetention = 0.9;
    Fsrs.instance.setWeights(null);
    notifyListeners();
  }

  // ----------------------------- Бэкап -----------------------------

  /// Момент последнего авто-бэкапа (мс) — см. `BackupService.autoBackupIfDue`.
  Future<int> lastAutoBackupMs() async =>
      await _prefs.getInt(_kLastAutoBackup) ?? 0;
  Future<void> setLastAutoBackupMs(int value) async =>
      _prefs.setInt(_kLastAutoBackup, value);

  /// Полный снимок данных как карта (колоды + паки + карты + журнал + ВСЕ
  /// настройки + рекорды/статистика чтения + конфиг перевода). Библиотека
  /// книг/видео добавляется поверх в `BackupService` (у неё «тяжёлый» контент
  /// на диске). Формат версии 2.
  Future<Map<String, dynamic>> exportMap() async {
    await _ensureLoaded();
    return {
      'version': 2,
      'decks': [for (final d in _decks) d.toJson()],
      'packs': [for (final p in _packs) p.toJson()],
      'cards': [for (final c in _cards) c.toJson()],
      'reviewLog': _log.toJson(),
      'matchBest': _matchBest,
      'reading': {'s': _readSeconds, 'w': _readWords},
      'translation': {
        'endpoints': await _prefs.getString(_kTransEndpoints),
        'active': await _prefs.getString(_kTransActive),
      },
      'requestRetention': await _prefs.getDouble(_kRetention),
      'fsrsWeights': await fsrsWeights(),
      'customLanguages': await _prefs.getString(_kCustomLanguages),
      'pinnedLanguages': await _prefs.getString(_kPinnedLanguages),
      'frozenDays': jsonEncode(_frozenDays.toList()),
      'streakFreezes': await _prefs.getInt(_kStreakFreezes),
      'freezeGrantLevel': await _prefs.getInt(_kFreezeGrant),
      'settings': {
        'seedColor': await _prefs.getInt(_kSeedColor),
        'themeMode': await _prefs.getInt(_kThemeMode),
        'isDarkTheme': await _prefs.getBool(_kIsDarkTheme),
        'dynamicColor': await _prefs.getBool(_kDynamicColor),
        'amoled': await _prefs.getBool(_kAmoled),
        'uiLanguageCode': await _prefs.getString(_kUiLanguage),
        'selectedLanguage': await _prefs.getString(_kSelectedLanguage),
        'dailyGoal': await _prefs.getInt(_kDailyGoal),
        'newPerDay': await _prefs.getInt(_kNewPerDay),
        'maxReviews': await _prefs.getInt(_kMaxReviews),
        'reminderEnabled': await _prefs.getBool(_kReminderOn),
        'reminderHour': await _prefs.getInt(_kReminderHour),
        'reminderMinute': await _prefs.getInt(_kReminderMinute),
        // Ключ Pro: без него человек после смены телефона восстанавливает
        // словарь и прогресс, а покупка пропадает. Новой дыры это не делает —
        // ключ и так копируемая строка, не привязанная к устройству.
        'licenseKey': await _prefs.getString(_kLicenseKey),
      },
    };
  }

  /// Полный снимок как JSON-строка (обёртка над [exportMap]).
  Future<String> exportJson() async =>
      const JsonEncoder.withIndent('  ').convert(await exportMap());

  /// Восстанавливает данные из снимка.
  ///
  /// [merge] == false (по умолчанию) — полная замена: текущие колоды/карты
  /// вытесняются данными из снимка, применяются настройки.
  ///
  /// [merge] == true — объединение: добавляются ТОЛЬКО отсутствующие сущности
  /// (по id), существующие не трогаются (чтобы не потерять текущий прогресс
  /// повторов); журнал и настройки при слиянии остаются как есть. Это безопасное
  /// «слить две библиотеки», а не last-write-wins.
  Future<void> importMap(Map<String, dynamic> data, {bool merge = false}) async {
    await _ensureLoaded();
    final decks = [
      for (final e in (data['decks'] as List? ?? const []))
        if (e is Map) Deck.fromJson(e.cast<String, dynamic>()),
    ];
    final packs = [
      for (final e in (data['packs'] as List? ?? const []))
        if (e is Map) Pack.fromJson(e.cast<String, dynamic>()),
    ];
    final cards = [
      for (final e in (data['cards'] as List? ?? const []))
        if (e is Map) WordCard.fromJson(e.cast<String, dynamic>()),
    ];

    if (merge) {
      final haveDeck = _decks.map((d) => d.id).toSet();
      for (final d in decks) {
        if (haveDeck.add(d.id)) {
          _decks.add(d);
          _db!.upsertDeck(d);
        }
      }
      final havePack = _packs.map((p) => p.id).toSet();
      for (final p in packs) {
        if (havePack.add(p.id)) {
          _packs.add(p);
          _db!.upsertPack(p);
        }
      }
      final haveCard = _cards.map((c) => c.id).toSet();
      final newCards = [for (final c in cards) if (haveCard.add(c.id)) c];
      if (newCards.isNotEmpty) {
        _cards.addAll(newCards);
        _db!.upsertCards(newCards);
      }
      notifyListeners();
      return;
    }

    // Полная замена.
    _decks
      ..clear()
      ..addAll(decks);
    _packs
      ..clear()
      ..addAll(packs);
    _cards
      ..clear()
      ..addAll(cards);
    _db!.replaceAllDecks(_decks);
    _db!.replaceAllPacks(_packs);
    _db!.replaceAllCards(_cards);

    if (data['reviewLog'] is Map) {
      _log = ReviewLog.fromJson((data['reviewLog'] as Map).cast<String, dynamic>());
      await _prefs.setString(_kReviewLog, jsonEncode(_log.toJson()));
    }
    if (data['matchBest'] is Map) {
      _matchBest = {
        for (final e in (data['matchBest'] as Map).entries)
          if (e.value is num) '${e.key}': (e.value as num).toInt(),
      };
      await _prefs.setString(_kMatchBest, jsonEncode(_matchBest));
    }
    if (data['reading'] is Map) {
      final r = (data['reading'] as Map).cast<String, dynamic>();
      _readSeconds = (r['s'] as num?)?.toInt() ?? _readSeconds;
      _readWords = (r['w'] as num?)?.toInt() ?? _readWords;
      await _prefs.setString(
        _kReadingStats,
        jsonEncode({'s': _readSeconds, 'w': _readWords}),
      );
    }
    if (data['translation'] is Map) {
      final t = (data['translation'] as Map).cast<String, dynamic>();
      if (t['endpoints'] is String) {
        await _prefs.setString(_kTransEndpoints, t['endpoints'] as String);
      }
      if (t['active'] is String) {
        await _prefs.setString(_kTransActive, t['active'] as String);
      }
    }
    if (data['customLanguages'] is String) {
      await _prefs.setString(_kCustomLanguages, data['customLanguages'] as String);
    }
    if (data['pinnedLanguages'] is String) {
      await _prefs.setString(_kPinnedLanguages, data['pinnedLanguages'] as String);
    }
    if (data['frozenDays'] is String) {
      await _prefs.setString(_kFrozenDays, data['frozenDays'] as String);
      _frozenDays
        ..clear()
        ..addAll(_decodeStringList(data['frozenDays'] as String));
    }
    if (data['streakFreezes'] is num) {
      await _prefs.setInt(_kStreakFreezes, (data['streakFreezes'] as num).toInt());
    }
    if (data['freezeGrantLevel'] is num) {
      await _prefs.setInt(_kFreezeGrant, (data['freezeGrantLevel'] as num).toInt());
    }
    await _applySettings((data['settings'] as Map?)?.cast<String, dynamic>());
    // Персонализация FSRS (целевое удержание + личные веса).
    if (data['requestRetention'] is num) {
      await setRequestRetention((data['requestRetention'] as num).toDouble());
    }
    if (data['fsrsWeights'] is List) {
      await setFsrsWeights([
        for (final v in data['fsrsWeights'] as List)
          if (v is num) v.toDouble(),
      ]);
    }
    notifyListeners();
  }

  /// Применяет блок настроек из снимка (что задано — то и пишем).
  Future<void> _applySettings(Map<String, dynamic>? s) async {
    if (s == null) return;
    Future<void> setInt(String key, String prefKey) async {
      if (s[key] is num) await _prefs.setInt(prefKey, (s[key] as num).toInt());
    }

    Future<void> setBool(String key, String prefKey) async {
      if (s[key] is bool) await _prefs.setBool(prefKey, s[key] as bool);
    }

    Future<void> setStr(String key, String prefKey) async {
      if (s[key] is String) await _prefs.setString(prefKey, s[key] as String);
    }

    await setStr('licenseKey', _kLicenseKey);
    await setInt('seedColor', _kSeedColor);
    await setInt('themeMode', _kThemeMode);
    await setBool('isDarkTheme', _kIsDarkTheme);
    await setBool('dynamicColor', _kDynamicColor);
    await setBool('amoled', _kAmoled);
    await setStr('uiLanguageCode', _kUiLanguage);
    await setStr('selectedLanguage', _kSelectedLanguage);
    await setInt('dailyGoal', _kDailyGoal);
    await setInt('newPerDay', _kNewPerDay);
    await setInt('maxReviews', _kMaxReviews);
    await setBool('reminderEnabled', _kReminderOn);
    await setInt('reminderHour', _kReminderHour);
    await setInt('reminderMinute', _kReminderMinute);
  }

  /// Восстанавливает из JSON-строки (обёртка над [importMap]).
  Future<void> importJson(String raw, {bool merge = false}) async =>
      importMap(jsonDecode(raw) as Map<String, dynamic>, merge: merge);

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
    // Сеется на первом запуске / апгрейде старого авто-набора — редко, поэтому
    // сохраняем весь текущий кэш целиком (память — источник правды на этот шаг).
    _db!.replaceAllDecks(_decks);
    _db!.replaceAllCards(_cards);
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
          name: localizedDeckName(
            nameKey: m['nameKey'] as String?,
            name: m['name'] as String?,
          ),
          colorValue: (m['color'] as num?)?.toInt() ?? 0xFF2E7D5B,
          shapeIndex: (m['shape'] as num?)?.toInt() ?? 0,
          createdAt: order,
          // Помним ключ: по нему колоду переведём заново, если сменят язык.
          nameKey: m['nameKey'] as String?,
        );
        final cards = <WordCard>[];
        var i = 0;
        for (final c in (m['cards'] as List? ?? const [])) {
          final cm = (c as Map).cast<String, dynamic>();
          final front = (cm['front'] as String? ?? '').trim();
          final back = localizedBack(cm['back']).trim();
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
