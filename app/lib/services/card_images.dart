import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Картинки карточек — визуальная опора для запоминания.
///
/// Файл лежит в `appDocs/card_images/<имя>`, а карточка хранит ТОЛЬКО имя
/// файла: абсолютный путь к контейнеру приложения меняется между установками
/// и обновлениями, так что запоминать его нельзя (та же схема, что у обложек
/// книг в [SourceLibrary]).
class CardImages {
  CardImages._();

  static String? _dirPath;

  /// Абсолютный путь к каталогу картинок. null, пока не прошла [init] или если
  /// файловая система недоступна (тесты, веб) — тогда картинки просто не видны.
  static String? get dirPath => _dirPath;

  /// Готовит каталог. Зовём один раз на старте, до построения UI, чтобы экраны
  /// могли строить путь синхронно.
  static Future<void> init() async {
    if (_dirPath != null) return;
    try {
      final base = await getApplicationDocumentsDirectory();
      final dir = Directory('${base.path}/card_images');
      if (!await dir.exists()) await dir.create(recursive: true);
      _dirPath = dir.path;
    } catch (_) {
      _dirPath = null;
    }
  }

  /// Абсолютный путь к картинке карточки, если она есть на диске.
  static String? resolve(String fileName) {
    final dir = _dirPath;
    if (dir == null || fileName.isEmpty) return null;
    final path = '$dir/$fileName';
    return File(path).existsSync() ? path : null;
  }

  /// Копирует выбранный файл к себе и возвращает имя копии.
  /// Имя привязано к карточке — одна карточка держит одну картинку.
  static Future<String?> save(String cardId, String sourcePath) async {
    await init();
    final dir = _dirPath;
    if (dir == null) return null;
    try {
      final ext = _extension(sourcePath);
      final name = '$cardId$ext';
      // Прежнюю картинку карточки убираем: расширение могло смениться.
      await deleteFor(cardId);
      await File(sourcePath).copy('$dir/$name');
      return name;
    } catch (_) {
      return null;
    }
  }

  /// Пишет картинку из бэкапа. Имя берём как есть — оно уже привязано к карте.
  static Future<bool> writeBytes(String fileName, List<int> bytes) async {
    await init();
    final dir = _dirPath;
    if (dir == null || fileName.isEmpty) return false;
    try {
      await File('$dir/$fileName').writeAsBytes(bytes);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Картинка в base64 — для бэкапа. null, если файла нет.
  static Future<String?> readB64(String fileName) async {
    final path = resolve(fileName);
    if (path == null) return null;
    try {
      return base64Encode(await File(path).readAsBytes());
    } catch (_) {
      return null;
    }
  }

  static Future<void> delete(String fileName) async {
    final path = resolve(fileName);
    if (path == null) return;
    try {
      await File(path).delete();
    } catch (_) {
      // Файла нет или он занят — карточке это уже не мешает.
    }
  }

  /// Убирает картинку карточки с любым расширением.
  static Future<void> deleteFor(String cardId) async {
    final dir = _dirPath;
    if (dir == null) return;
    try {
      final folder = Directory(dir);
      if (!folder.existsSync()) return;
      for (final f in folder.listSync().whereType<File>()) {
        final name = f.uri.pathSegments.last;
        if (name == cardId || name.startsWith('$cardId.')) f.deleteSync();
      }
    } catch (_) {
      // Каталог недоступен — молча пропускаем.
    }
  }

  /// Забывает найденный каталог — тесты подсовывают свой path_provider.
  static void resetForTest() => _dirPath = null;

  /// Стирает все картинки — часть «удалить все данные».
  static Future<void> wipeAll() async {
    final dir = _dirPath;
    if (dir == null) return;
    try {
      final folder = Directory(dir);
      if (folder.existsSync()) folder.deleteSync(recursive: true);
      await folder.create(recursive: true);
    } catch (_) {
      // Каталог занят или недоступен — данные карточек это уже не держит.
    }
  }

  /// Расширение исходного файла (с точкой), с запасным `.jpg`.
  static String _extension(String path) {
    final dot = path.lastIndexOf('.');
    if (dot < 0 || dot < path.length - 6) return '.jpg';
    final ext = path.substring(dot).toLowerCase();
    return RegExp(r'^\.[a-z0-9]{2,5}$').hasMatch(ext) ? ext : '.jpg';
  }
}
