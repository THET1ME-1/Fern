import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'card_images.dart';
import 'deck_repository.dart';
import 'license_service.dart';
import 'source_library.dart';

/// Единое место, знающее формат полного бэкапа Fern: колоды/паки/карты + журнал
/// + настройки ([DeckRepository]) поверх которых кладётся библиотека книг/видео
/// ([SourceLibrary]). Восстановление умеет две стратегии — «заменить всё» и
/// безопасное «объединить» (добавить только новое, не теряя текущий прогресс).
/// Чем закончилось восстановление копии.
class RestoreResult {
  /// Ключ Pro в снимке был, но принять его нельзя: пора взять свежий у бота.
  final bool licenseExpired;

  const RestoreResult({this.licenseExpired = false});
}

class BackupService {
  const BackupService._();

  static const String _autoFileName = 'fern_backup_auto.json';
  static const String _tmpSuffix = '/fern_backup_auto.json.tmp';

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
      map['cardImages'] = await _exportCardImages();
    }
    return const JsonEncoder.withIndent('  ').convert(map);
  }

  /// Восстанавливает данные из снимка. [merge] см. [DeckRepository.importMap].
  static Future<RestoreResult> restore(String raw, {bool merge = false}) async {
    final data = jsonDecode(raw) as Map<String, dynamic>;
    // Ключ живёт внутри «settings», а не на верхнем уровне снимка.
    final settings = data['settings'];
    final savedKey = settings is Map ? settings['licenseKey'] : null;
    final hadKey = savedKey is String && savedKey.isNotEmpty;
    await DeckRepository.instance.importMap(data, merge: merge);
    // Ключ Pro импорт кладёт прямо в prefs, а `LicenseService` держит статус в
    // памяти и сверяется с диском только при запуске. Без этой строки человек
    // на новом телефоне восстанавливал свой снимок и видел библиотеку под
    // замком и бесплатный тариф в настройках — «покупка не восстановилась».
    await LicenseService.instance.load();
    if (data['library'] is List) {
      await SourceLibrary.instance
          .importAll(data['library'] as List, merge: merge);
    }
    if (data['cardImages'] is List) {
      await _importCardImages(data['cardImages'] as List);
    }
    // Ключ в снимке был, а Pro не открылся — значит он просрочен. Молча
    // оставлять человека без покупки нельзя: надо сказать, что делать.
    return RestoreResult(
      licenseExpired: hadKey && !LicenseService.instance.isValid,
    );
  }

  /// Картинки карточек в base64. Идут вместе с библиотекой (тяжёлое), в
  /// авто-бэкап не попадают: там ценен прогресс, а не байты фотографий.
  static Future<List<Map<String, String>>> _exportCardImages() async {
    final out = <Map<String, String>>[];
    try {
      final cards = await DeckRepository.instance.loadCards();
      for (final c in cards) {
        if (c.image.isEmpty) continue;
        final b64 = await CardImages.readB64(c.image);
        if (b64 != null) out.add({'name': c.image, 'b64': b64});
      }
    } catch (_) {
      // Каталог недоступен — бэкап всё равно должен собраться.
    }
    return out;
  }

  static Future<void> _importCardImages(List raw) async {
    for (final item in raw) {
      if (item is! Map) continue;
      final name = item['name'] as String?;
      final b64 = item['b64'] as String?;
      if (name == null || b64 == null) continue;
      try {
        await CardImages.writeBytes(name, base64Decode(b64));
      } catch (_) {
        // Битая картинка не должна валить восстановление карточек.
      }
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

      final target = File('${dir.path}/$_autoFileName');
      // Пустой снимок поверх непустого — это конец страховки. Так и случалось:
      // аварийный экран уводил базу в карантин, запуск доходил до сюда, сутки
      // с прошлого снимка давно прошли — и файл, из которого предлагалось
      // восстановиться, затирался снимком пустой базы.
      if (await _wouldLoseData(target, json)) return;

      // Запись через временный файл: обрыв на середине оставит прежний снимок
      // целым, а не полстроки JSON.
      final tmp = File('${dir.path}$_tmpSuffix');
      await tmp.writeAsString(json, flush: true);
      await tmp.rename(target.path);
      await repo.setLastAutoBackupMs(now);
    } catch (_) {
      /* авто-бэкап не должен ронять запуск — молча пропускаем */
    }
  }

  /// Новый снимок пуст, а прежний — нет.
  static Future<bool> _wouldLoseData(File target, String fresh) async {
    if (_cardCount(fresh) > 0) return false;
    if (!await target.exists()) return false;
    try {
      return _cardCount(await target.readAsString()) > 0;
    } catch (_) {
      return false; // прежний снимок не читается — терять нечего
    }
  }

  static int _cardCount(String json) {
    try {
      final cards = (jsonDecode(json) as Map)['cards'];
      return cards is List ? cards.length : 0;
    } catch (_) {
      return 0;
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
