import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:fern/services/local_db.dart';

import 'test_helpers.dart';

/// Миграция схемы должна переживать повторный запуск.
///
/// Шаг `ALTER TABLE` и запись версии — разные автокоммиты. Если система убьёт
/// процесс между ними (обычное дело при первом старте после обновления),
/// следующий запуск повторит миграцию. Падение здесь стоит дорого: открытие
/// базы срывается, приложение уходит на аварийный экран, а обе его кнопки
/// отправляют исправную базу в карантин.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(resetStorage);

  String dbPath() =>
      '${Directory.systemTemp.path}/fern_migrate_${DateTime.now().microsecondsSinceEpoch}.db';

  test('Повторная миграция не роняет открытие базы', () async {
    final path = dbPath();

    // База предыдущей версии: журнал повторов без колонки времени ответа.
    final legacy = sqlite3.open(path);
    legacy.execute('''
      CREATE TABLE review_events (
        id           INTEGER PRIMARY KEY AUTOINCREMENT,
        card_id      TEXT NOT NULL,
        ts           INTEGER NOT NULL,
        grade        INTEGER NOT NULL,
        elapsed_days REAL NOT NULL,
        state_before INTEGER NOT NULL
      );
    ''');
    legacy.execute('PRAGMA user_version=2');
    legacy.dispose();

    // Первый запуск: миграция проходит.
    final db = LocalDb(path: path);
    await db.open();
    db.close();

    // Версию «не успели» записать — процесс умер сразу после ALTER.
    final broken = sqlite3.open(path);
    broken.execute('PRAGMA user_version=2');
    broken.dispose();

    // Второй запуск обязан пройти молча, а не упасть на «duplicate column».
    final again = LocalDb(path: path);
    await expectLater(again.open(), completes);
    again.close();
  });

  test('Старая база догоняет схему целиком', () async {
    final path = dbPath();
    final legacy = sqlite3.open(path);
    legacy.execute('''
      CREATE TABLE review_events (
        id           INTEGER PRIMARY KEY AUTOINCREMENT,
        card_id      TEXT NOT NULL,
        ts           INTEGER NOT NULL,
        grade        INTEGER NOT NULL,
        elapsed_days REAL NOT NULL,
        state_before INTEGER NOT NULL
      );
    ''');
    legacy.execute('PRAGMA user_version=2');
    legacy.dispose();

    final db = LocalDb(path: path);
    await db.open();
    db.close();

    final check = sqlite3.open(path);
    final columns = check
        .select('PRAGMA table_info(review_events)')
        .map((r) => r['name'] as String)
        .toList();
    final version = check.select('PRAGMA user_version').first.values.first;
    check.dispose();

    expect(columns, containsAll(['answer_ms', 'kind']));
    expect(version, 4);
  });

  test('Откат приложения не понижает версию схемы', () async {
    final path = dbPath();
    final future = sqlite3.open(path);
    future.execute('PRAGMA user_version=99'); // база побывала под новой версией
    future.dispose();

    final db = LocalDb(path: path);
    await db.open();
    db.close();

    final check = sqlite3.open(path);
    final version = check.select('PRAGMA user_version').first.values.first;
    check.dispose();
    expect(version, 99,
        reason: 'понижение версии заставит следующий апгрейд мигрировать заново');
  });
}
