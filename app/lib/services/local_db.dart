import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import '../models/deck.dart';
import '../models/pack.dart';
import '../models/review_event.dart';
import '../models/word_card.dart';

/// Локальная база данных Fern на SQLite (пакет `sqlite3` — он уже в зависимостях,
/// им же читаются импортируемые Anki `.apkg`).
///
/// Заменяет прежнее хранение ВСЕХ колод/карт одним списком строк в
/// SharedPreferences, где каждая оценка карты переписывала весь словарь на диск
/// (O(N) на свайп — растущие лаги и риск ANR на тысячах карт). Теперь запись
/// одной карты = один `UPDATE` одной строки.
///
/// **Модель хранения — «документ + проекция».** Полный JSON сущности лежит в
/// колонке `data` — единый источник правды, те же `toJson`/`fromJson`, что и
/// раньше, без риска рассинхронизации схемы при добавлении новых полей в модель.
/// Поля, по которым нужны выборки/индексы/синхронизация (`deck_id`, `due`,
/// `state`, `updated_at`), продублированы отдельными колонками и заполняются при
/// записи. Это даёт индекс по сроку повтора (быстрый «сколько карт к повтору»
/// без загрузки всего словаря — фундамент под домашний виджет и уведомления) и
/// пометку `updated_at` на каждую строку (фундамент под честный merge-синк).
///
/// **Порядок строк** сохраняется через `rowid`: `INSERT` назначает следующий,
/// upsert через `ON CONFLICT(id) DO UPDATE` его НЕ меняет (в отличие от
/// `INSERT OR REPLACE`, который удаляет+вставляет и «перекидывает» строку в
/// конец). Значит колоды/карты остаются ровно в том же порядке, что и в прежнем
/// списке.
class LocalDb {
  Database? _db;

  /// Явный путь к файлу БД (используется в тестах). На устройстве — null, тогда
  /// путь берётся из каталога документов приложения.
  final String? _overridePath;

  LocalDb({String? path}) : _overridePath = path;

  static int _now() => DateTime.now().millisecondsSinceEpoch;

  bool get isOpen => _db != null;

  Database get _handle {
    final db = _db;
    if (db == null) throw StateError('LocalDb используется до open()');
    return db;
  }

  /// Открывает БД и создаёт схему. Идемпотентно.
  Future<void> open() async {
    if (_db != null) return;
    final path = _overridePath ?? await _defaultPath();
    final db = sqlite3.open(path);
    // WAL — читатели не блокируют писателя; NORMAL — быстро и безопасно (данные
    // фиксируются на диск при чекпойнте, не теряются при падении процесса);
    // busy_timeout — не падать сразу, если файл занят.
    db.execute('PRAGMA journal_mode=WAL');
    db.execute('PRAGMA synchronous=NORMAL');
    db.execute('PRAGMA busy_timeout=5000');
    _createSchema(db);
    _db = db;
  }

  /// Убирает файл БД вместе с WAL-спутниками. Нужен, когда файл повреждён и
  /// `open()` бросает: без этого приложение не запустится вообще.
  /// Битую базу не удаляем, а отодвигаем в `.corrupt` — вдруг данные ещё вытащим.
  Future<void> quarantineFile() async {
    _db?.dispose();
    _db = null;
    final path = _overridePath ?? await _defaultPath();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    for (final suffix in const ['', '-wal', '-shm']) {
      final f = File('$path$suffix');
      if (!f.existsSync()) continue;
      try {
        f.renameSync('$path$suffix.corrupt-$stamp');
      } catch (_) {
        try {
          f.deleteSync();
        } catch (_) {
          // Файл не отдаётся — дальше open() снова бросит, покажем экран отказа.
        }
      }
    }
  }

  Future<String> _defaultPath() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      return '${dir.path}/fern.db';
    } catch (_) {
      // Тест/десктоп без path_provider — файл на процесс, чтобы параллельные
      // тест-процессы не делили один файл.
      return '${Directory.systemTemp.path}/fern_fallback_$pid.db';
    }
  }

  void _createSchema(Database db) {
    db.execute('''
      CREATE TABLE IF NOT EXISTS decks (
        id         TEXT PRIMARY KEY,
        data       TEXT NOT NULL,
        updated_at INTEGER NOT NULL DEFAULT 0
      );
    ''');
    db.execute('''
      CREATE TABLE IF NOT EXISTS packs (
        id         TEXT PRIMARY KEY,
        data       TEXT NOT NULL,
        updated_at INTEGER NOT NULL DEFAULT 0
      );
    ''');
    db.execute('''
      CREATE TABLE IF NOT EXISTS cards (
        id         TEXT PRIMARY KEY,
        deck_id    TEXT NOT NULL,
        due        INTEGER,
        state      INTEGER NOT NULL DEFAULT 0,
        data       TEXT NOT NULL,
        updated_at INTEGER NOT NULL DEFAULT 0
      );
    ''');
    db.execute('CREATE INDEX IF NOT EXISTS idx_cards_deck ON cards(deck_id)');
    db.execute('CREATE INDEX IF NOT EXISTS idx_cards_due ON cards(due)');
    // Сырой журнал повторов — под персональный оптимизатор FSRS (кривая
    // забывания конкретного пользователя). Пишется на каждую оценку.
    db.execute('''
      CREATE TABLE IF NOT EXISTS review_events (
        id           INTEGER PRIMARY KEY AUTOINCREMENT,
        card_id      TEXT NOT NULL,
        ts           INTEGER NOT NULL,
        grade        INTEGER NOT NULL,
        elapsed_days REAL NOT NULL,
        state_before INTEGER NOT NULL,
        answer_ms    INTEGER,
        kind         INTEGER
      );
    ''');
    db.execute(
        'CREATE INDEX IF NOT EXISTS idx_revlog_card ON review_events(card_id, ts)');
    _migrate(db);
    // Версию только ПОДНИМАЕМ. База, побывавшая под более новой сборкой (человек
    // откатил приложение), уже несёт колонки будущей схемы; понизив отметку, мы
    // заставили бы следующий апгрейд мигрировать заново — по колонкам, которые
    // на месте, то есть с падением на «duplicate column».
    final current = db.select('PRAGMA user_version').first.values.first as int;
    if (current < _schemaVersion) {
      db.execute('PRAGMA user_version=$_schemaVersion');
    }
  }

  /// Версия схемы. Растёт вместе с каждой миграцией ниже.
  static const int _schemaVersion = 4;

  /// Догоняет схему на базах, созданных прежними версиями приложения.
  /// `CREATE TABLE IF NOT EXISTS` новые КОЛОНКИ не добавляет — только ALTER.
  ///
  /// Шаг `ALTER` и отметка `user_version` — разные автокоммиты, и между ними
  /// система может убить процесс (первый запуск после обновления — обычное для
  /// этого место). Следующий запуск повторит миграцию, поэтому каждый шаг
  /// смотрит на фактические колонки, а не на номер версии. Падение здесь стоит
  /// дорого: `open()` бросает, приложение уходит на аварийный экран, а обе его
  /// кнопки отправляют исправную базу в карантин.
  void _migrate(Database db) {
    final from = db.select('PRAGMA user_version').first.values.first as int;
    if (from == 0 || from >= _schemaVersion) return; // пустая или уже свежая
    _addColumnIfMissing(db, 'review_events', 'answer_ms', 'INTEGER');
    _addColumnIfMissing(db, 'review_events', 'kind', 'INTEGER');
  }

  void _addColumnIfMissing(
      Database db, String table, String column, String type) {
    final has = db
        .select('PRAGMA table_info($table)')
        .any((r) => (r['name'] as String).toLowerCase() == column);
    if (!has) db.execute('ALTER TABLE $table ADD COLUMN $column $type');
  }

  /// Закрывает соединение (данные остаются на диске). Следующий [open] поднимет
  /// их заново.
  void close() {
    _db?.dispose();
    _db = null;
  }

  // ----------------------------- Транзакция -----------------------------

  void _tx(void Function(Database db) body) {
    final db = _handle;
    db.execute('BEGIN');
    try {
      body(db);
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  // ----------------------------- Чтение -----------------------------

  List<Deck> allDecks() =>
      _decode(_handle.select('SELECT data FROM decks ORDER BY rowid'),
          Deck.fromJson);

  List<Pack> allPacks() =>
      _decode(_handle.select('SELECT data FROM packs ORDER BY rowid'),
          Pack.fromJson);

  List<WordCard> allCards() =>
      _decode(_handle.select('SELECT data FROM cards ORDER BY rowid'),
          WordCard.fromJson);

  List<T> _decode<T>(ResultSet rows, T Function(Map<String, dynamic>) fromJson) {
    final out = <T>[];
    for (final row in rows) {
      try {
        out.add(
          fromJson(jsonDecode(row['data'] as String) as Map<String, dynamic>),
        );
      } catch (_) {
        /* битая строка — пропускаем, как делал прежний декодер */
      }
    }
    return out;
  }

  int deckCount() =>
      _handle.select('SELECT COUNT(*) AS c FROM decks').first['c'] as int;

  int cardCount() =>
      _handle.select('SELECT COUNT(*) AS c FROM cards').first['c'] as int;

  /// Сколько карт «к повтору» на момент [nowMs] (новые карты = `due IS NULL`).
  /// Считает индексом по `due`, не загружая словарь в память — основа для
  /// домашнего виджета и умных уведомлений.
  int countDue(int nowMs) => _handle.select(
        'SELECT COUNT(*) AS c FROM cards WHERE due IS NULL OR due <= ?',
        [nowMs],
      ).first['c'] as int;

  // ----------------------------- Колоды -----------------------------

  static const String _kUpsertDeck =
      'INSERT INTO decks(id,data,updated_at) VALUES(?,?,?) '
      'ON CONFLICT(id) DO UPDATE SET data=excluded.data, '
      'updated_at=excluded.updated_at';

  void upsertDeck(Deck d) =>
      _handle.execute(_kUpsertDeck, [d.id, jsonEncode(d.toJson()), _now()]);

  void deleteDeck(String id) =>
      _handle.execute('DELETE FROM decks WHERE id=?', [id]);

  void replaceAllDecks(List<Deck> decks) => _tx((db) {
        db.execute('DELETE FROM decks');
        final stmt = db.prepare(
            'INSERT INTO decks(id,data,updated_at) VALUES(?,?,?)');
        final now = _now();
        for (final d in decks) {
          stmt.execute([d.id, jsonEncode(d.toJson()), now]);
        }
        stmt.dispose();
      });

  // ----------------------------- Паки -----------------------------

  static const String _kUpsertPack =
      'INSERT INTO packs(id,data,updated_at) VALUES(?,?,?) '
      'ON CONFLICT(id) DO UPDATE SET data=excluded.data, '
      'updated_at=excluded.updated_at';

  void upsertPack(Pack p) =>
      _handle.execute(_kUpsertPack, [p.id, jsonEncode(p.toJson()), _now()]);

  void deletePack(String id) =>
      _handle.execute('DELETE FROM packs WHERE id=?', [id]);

  void replaceAllPacks(List<Pack> packs) => _tx((db) {
        db.execute('DELETE FROM packs');
        final stmt = db.prepare(
            'INSERT INTO packs(id,data,updated_at) VALUES(?,?,?)');
        final now = _now();
        for (final p in packs) {
          stmt.execute([p.id, jsonEncode(p.toJson()), now]);
        }
        stmt.dispose();
      });

  // ----------------------------- Карточки -----------------------------

  static const String _kUpsertCard =
      'INSERT INTO cards(id,deck_id,due,state,data,updated_at) VALUES(?,?,?,?,?,?) '
      'ON CONFLICT(id) DO UPDATE SET deck_id=excluded.deck_id, due=excluded.due, '
      'state=excluded.state, data=excluded.data, updated_at=excluded.updated_at';

  List<Object?> _cardRow(WordCard c, int now) => [
        c.id,
        c.deckId,
        c.review.due?.millisecondsSinceEpoch,
        c.review.state.index,
        jsonEncode(c.toJson()),
        now,
      ];

  void upsertCard(WordCard c) =>
      _handle.execute(_kUpsertCard, _cardRow(c, _now()));

  /// Пачка карт за одну транзакцию (быстрое добавление/перенос) — один общий
  /// prepared-statement, одна фиксация на диск.
  void upsertCards(Iterable<WordCard> cards) => _tx((db) {
        final stmt = db.prepare(_kUpsertCard);
        final now = _now();
        for (final c in cards) {
          stmt.execute(_cardRow(c, now));
        }
        stmt.dispose();
      });

  void deleteCard(String id) =>
      _handle.execute('DELETE FROM cards WHERE id=?', [id]);

  void deleteCardsForDeck(String deckId) =>
      _handle.execute('DELETE FROM cards WHERE deck_id=?', [deckId]);

  void replaceAllCards(List<WordCard> cards) => _tx((db) {
        db.execute('DELETE FROM cards');
        final stmt = db.prepare(_kUpsertCard);
        final now = _now();
        for (final c in cards) {
          stmt.execute(_cardRow(c, now));
        }
        stmt.dispose();
      });

  // ------------------------- Журнал повторов (revlog) -------------------------

  void logReview(ReviewEvent e) => _handle.execute(
        'INSERT INTO review_events'
        '(card_id,ts,grade,elapsed_days,state_before,answer_ms,kind) '
        'VALUES(?,?,?,?,?,?,?)',
        [
          e.cardId,
          e.ts,
          e.grade,
          e.elapsedDays,
          e.stateBefore,
          e.answerMs,
          e.kind,
        ],
      );

  int reviewEventCount() =>
      _handle.select('SELECT COUNT(*) AS c FROM review_events').first['c']
          as int;

  /// Все события повтора по возрастанию времени (для оптимизатора).
  List<ReviewEvent> allReviewEvents() {
    final rows = _handle.select(
        'SELECT card_id,ts,grade,elapsed_days,state_before,answer_ms,kind '
        'FROM review_events ORDER BY card_id, ts');
    return [
      for (final r in rows)
        ReviewEvent(
          cardId: r['card_id'] as String,
          ts: r['ts'] as int,
          grade: r['grade'] as int,
          elapsedDays: (r['elapsed_days'] as num).toDouble(),
          stateBefore: r['state_before'] as int,
          answerMs: r['answer_ms'] as int?,
          kind: r['kind'] as int?,
        ),
    ];
  }

  /// Времена последних верных ответов (мс) вместе с видом упражнения, свежие
  /// первыми. Вид обязателен: без него замер не с чем сравнивать.
  ///
  /// Отдельный запрос вместо загрузки всего журнала: медианы нужны на каждом
  /// старте сессии, а журнал за год — это десятки тысяч строк.
  ///
  /// Лимит с запасом, потому что выборок теперь две, а печатают заметно реже,
  /// чем тапают: на трёхстах свежих ответах набранных могло не набраться на
  /// собственную медиану.
  List<({int kind, int ms})> recentAnswerTimes({int limit = 600}) {
    final rows = _handle.select(
      'SELECT answer_ms, kind FROM review_events '
      'WHERE answer_ms IS NOT NULL AND answer_ms > 0 AND grade > 1 '
      'AND kind IS NOT NULL '
      'ORDER BY ts DESC LIMIT ?',
      [limit],
    );
    return [
      for (final r in rows) (kind: r['kind'] as int, ms: r['answer_ms'] as int)
    ];
  }

  void clearReviewEvents() => _handle.execute('DELETE FROM review_events');

  /// Полностью очищает БД (удаление всех данных пользователя).
  void wipeAll() => _tx((db) {
        db.execute('DELETE FROM cards');
        db.execute('DELETE FROM decks');
        db.execute('DELETE FROM packs');
        db.execute('DELETE FROM review_events');
      });
}
