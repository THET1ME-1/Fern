import 'dart:ffi';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:sqlite3/open.dart';

import 'package:fern/models/fsrs.dart';
import 'package:fern/services/deck_repository.dart';
import 'package:fern/services/language_registry.dart';
import 'package:fern/services/source_library.dart';

bool _sqliteReady = false;

/// На хосте нет unversioned `libsqlite3.so` (на Android его даёт
/// sqlite3_flutter_libs) — в тестах открываем версионную `.so.0`. Один раз.
void _ensureSqliteLoaded() {
  if (_sqliteReady) return;
  _sqliteReady = true;
  open.overrideForAll(() => DynamicLibrary.open('libsqlite3.so.0'));
}

/// Ставит чистое in-memory хранилище под ОБА prefs-API (legacy + async) и свежую
/// пустую SQLite-БД, а также сбрасывает кэш репозитория. Зовём в `setUp` каждого
/// теста, работающего с данными.
Future<void> resetStorage() async {
  _ensureSqliteLoaded();
  SharedPreferences.setMockInitialValues({});
  SharedPreferencesAsyncPlatform.instance =
      InMemorySharedPreferencesAsync.empty();
  // Закрываем прежнее соединение (если было) до удаления файла БД.
  DeckRepository.instance.resetForTest();
  SourceLibrary.instance.resetForTest();
  LanguageRegistry.instance.resetForTest();
  // Планировщик — синглтон: возвращаем дефолтные веса/удержание между кейсами.
  Fsrs.instance.requestRetention = 0.9;
  Fsrs.instance.setWeights(null);
  // Файл БД — на процесс (pid): `flutter test` гоняет тест-ФАЙЛЫ параллельно в
  // отдельных процессах, а кейсы внутри файла — последовательно. Так у каждого
  // процесса свой файл (нет гонок), а тут мы его чистим под каждый кейс.
  final path = '${Directory.systemTemp.path}/fern_test_$pid.db';
  DeckRepository.debugDatabasePath = path;
  for (final suffix in const ['', '-wal', '-shm', '-journal']) {
    final f = File('$path$suffix');
    if (f.existsSync()) f.deleteSync();
  }
}
