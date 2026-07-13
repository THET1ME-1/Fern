import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'deck_repository.dart';
import 'source_library.dart';

/// Единое место, знающее формат полного бэкапа Fern: колоды/паки/карты + журнал
/// + настройки ([DeckRepository]) поверх которых кладётся библиотека книг/видео
/// ([SourceLibrary]). Восстановление умеет две стратегии — «заменить всё» и
/// безопасное «объединить» (добавить только новое, не теряя текущий прогресс).
class BackupService {
  const BackupService._();

  static const String _autoFileName = 'fern_backup_auto.json';

  /// Полный снимок как JSON-строка.
  ///
  /// [includeLibrary] — вкладывать ли тексты книг / транскрипты видео / обложки.
  /// Для ручного бэкапа — да (переносим ВСЁ). Для авто-бэкапа — нет: фоновый
  /// снимок должен быть лёгким и быстрым, а незаменимое там — прогресс повторов,
  /// колоды и настройки (книги можно перечитать, интервалы FSRS — нет).
  static Future<String> exportJson({bool includeLibrary = true}) async {
    final map = await DeckRepository.instance.exportMap();
    if (includeLibrary) {
      map['library'] = await SourceLibrary.instance.exportAll();
    }
    return const JsonEncoder.withIndent('  ').convert(map);
  }

  /// Восстанавливает данные из снимка. [merge] см. [DeckRepository.importMap].
  static Future<void> restore(String raw, {bool merge = false}) async {
    final data = jsonDecode(raw) as Map<String, dynamic>;
    await DeckRepository.instance.importMap(data, merge: merge);
    if (data['library'] is List) {
      await SourceLibrary.instance
          .importAll(data['library'] as List, merge: merge);
    }
  }

  /// Тихий авто-бэкап не чаще, чем раз в [interval]: пишет облегчённый снимок
  /// (без тяжёлой библиотеки) в приватный файл приложения. Безопасная сеть на
  /// случай повреждения БД. «Best effort» — при любой ошибке молча выходит.
  static Future<void> autoBackupIfDue({
    Duration interval = const Duration(hours: 24),
  }) async {
    try {
      final repo = DeckRepository.instance;
      final last = await repo.lastAutoBackupMs();
      final now = DateTime.now().millisecondsSinceEpoch;
      if (last != 0 && now - last < interval.inMilliseconds) return;
      final dir = await getApplicationDocumentsDirectory();
      final json = await exportJson(includeLibrary: false);
      await File('${dir.path}/$_autoFileName').writeAsString(json);
      await repo.setLastAutoBackupMs(now);
    } catch (_) {
      /* авто-бэкап не должен ронять запуск — молча пропускаем */
    }
  }

  /// Восстанавливает из файла снимка (используется аварийным экраном, когда до
  /// настроек не добраться).
  static Future<void> restoreFile(String path, {bool merge = false}) async {
    final raw = await File(path).readAsString();
    await restore(raw, merge: merge);
  }

  /// Путь к файлу авто-бэкапа, если он есть (для восстановления «из последнего
  /// авто-снимка»). null — файла нет или каталог недоступен.
  static Future<String?> autoBackupPath() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final f = File('${dir.path}/$_autoFileName');
      return await f.exists() ? f.path : null;
    } catch (_) {
      return null;
    }
  }
}
