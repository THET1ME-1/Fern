import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';

import '../utils/html_entity.dart';
import 'package:flutter/foundation.dart';

import '../l10n/strings.dart';
import '../models/book_chapter.dart';

/// Извлечённый из файла текст книги + предполагаемое название + оглавление +
/// байты обложки (если удалось извлечь из epub/fb2).
class BookText {
  final String title;
  final String text;
  final List<BookChapter> chapters;
  final List<int>? cover;
  const BookText({
    required this.title,
    required this.text,
    this.chapters = const [],
    this.cover,
  });

  bool get isEmpty => text.trim().isEmpty;
}

/// Отказ разбирать файл: формат чужой.
///
/// [name] — как формат называют люди («MOBI», «PDF»), чтобы сообщение было о
/// деле, а не «не удалось открыть файл». Пусто, когда формат не опознан, а
/// внутри всё равно не текст.
class ForeignBook {
  final String? name;
  const ForeignBook(this.name);
}

/// Накопитель абзацев и глав: тексты добавляются кусками, главы отмечают
/// индекс абзаца, с которого начинаются (в том же разбиении, что и читалка).
class _Assembler {
  final List<String> paragraphs = [];
  final List<BookChapter> chapters = [];

  void startChapter(String title) {
    final t = title.trim();
    chapters.add(BookChapter(
      t.isEmpty
          ? BookImport.chapterTemplate
              .replaceAll('{n}', '${chapters.length + 1}')
          : t,
      paragraphs.length,
    ));
  }

  void add(String text) {
    for (final line in text.split('\n')) {
      final t = line.trim();
      if (t.isNotEmpty) paragraphs.add(t);
    }
  }

  String get text => paragraphs.join('\n');

  /// Оглавление без «мусорных» глав: убираем пустые в начале и слишком мелкие.
  List<BookChapter> get cleanChapters {
    // Оставляем только главы, у которых есть контент (следующая глава/конец
    // дальше по тексту), и не больше разумного числа.
    final out = <BookChapter>[];
    for (var i = 0; i < chapters.length; i++) {
      final c = chapters[i];
      final end =
          i + 1 < chapters.length ? chapters[i + 1].startParagraph : paragraphs.length;
      if (end - c.startParagraph >= 1) out.add(c);
    }
    // Если получилась одна глава на всю книгу — оглавление не нужно.
    return out.length <= 1 ? const [] : out;
  }
}

/// Импорт книг из текстовых форматов: `txt`, `md`, `csv`, `srt`, `vtt`,
/// `html`, `xml`, `fb2`, `epub`, `fb2.zip`. PDF не поддерживается (бинарный
/// формат) — попросим экспортировать в TXT/EPUB.
class BookImport {
  const BookImport._();

  static const List<String> supportedExtensions = [
    'txt', 'md', 'markdown', 'text', 'csv', 'log',
    'srt', 'vtt',
    'html', 'htm', 'xhtml', 'xml', 'fb2',
    'epub', 'zip',
  ];

  static String extensionOf(String path) {
    final name = path.split(Platform.pathSeparator).last;
    final dot = name.lastIndexOf('.');
    if (dot < 0) return '';
    return name.substring(dot + 1).toLowerCase();
  }

  static String _baseName(String path) {
    final name = path.split(Platform.pathSeparator).last;
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }

  // ------------------------------- Заслон -------------------------------

  /// Форматы книг, которые Fern не читает. Значение — как формат называют
  /// люди: оно попадает прямо в сообщение, поэтому `azw3` здесь `AZW3`, а не
  /// «неизвестный формат».
  static const Map<String, String> _foreignByExtension = {
    'mobi': 'MOBI',
    'azw': 'AZW',
    'azw3': 'AZW3',
    'kfx': 'KFX',
    'prc': 'PRC',
    'lit': 'LIT',
    'chm': 'CHM',
    'pdf': 'PDF',
    'djvu': 'DjVu',
    'djv': 'DjVu',
    'doc': 'DOC',
    'docx': 'DOCX',
    'odt': 'ODT',
    'rtf': 'RTF',
    'fb3': 'FB3',
    'ibooks': 'iBooks',
  };

  /// Сигнатуры в начале файла. Расширение врёт чаще, чем заголовок: книгу
  /// переименовывают в `.txt`, чтобы «прошла».
  static const List<({int offset, String magic, String name})> _signatures = [
    (offset: 60, magic: 'BOOKMOBI', name: 'MOBI'),
    (offset: 60, magic: 'TEXtREAd', name: 'PalmDOC'),
    (offset: 0, magic: '%PDF', name: 'PDF'),
    (offset: 0, magic: 'AT&TFORM', name: 'DjVu'),
    (offset: 0, magic: '{\\rtf', name: 'RTF'),
    (offset: 0, magic: 'ITSF', name: 'CHM'),
  ];

  /// Байты OLE-контейнера (старые .doc от Word).
  static const List<int> _oleMagic = [
    0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1
  ];

  /// Сколько байт достаточно, чтобы узнать формат и понять, текст ли это.
  static const int _headBytes = 4096;

  /// Потолок РАЗВЁРНУТОГО содержимого архива. Zip-бомба на мегабайт
  /// разворачивается в гигабайты и кладёт приложение по памяти; заявленные в
  /// заголовке размеры видны ДО распаковки — по ним и отсекаем. Самая толстая
  /// настоящая книга с картинками — десятки мегабайт.
  static const int defaultMaxUncompressedBytes = 200 * 1024 * 1024;

  /// Изменяемо только ради тестов: бюджет по-настоящему большой, и гонять в
  /// тесте двухсотмегабайтный архив дороже, чем ужать лимит.
  @visibleForTesting
  static int maxUncompressedBytes = defaultMaxUncompressedBytes;

  /// Имя формата по сигнатуре, либо null.
  static String? sniffFormat(List<int> head) {
    for (final s in _signatures) {
      if (_matchesAt(head, s.offset, s.magic.codeUnits)) return s.name;
    }
    if (_matchesAt(head, 0, _oleMagic)) return 'DOC';
    return null;
  }

  static bool _matchesAt(List<int> bytes, int offset, List<int> magic) {
    if (bytes.length < offset + magic.length) return false;
    for (var i = 0; i < magic.length; i++) {
      if (bytes[offset + i] != magic[i]) return false;
    }
    return true;
  }

  static bool _isZip(List<int> head) =>
      _matchesAt(head, 0, const [0x50, 0x4B, 0x03, 0x04]) ||
      _matchesAt(head, 0, const [0x50, 0x4B, 0x05, 0x06]);

  /// BOM UTF-16: FF FE (LE) или FE FF (BE). Виндовый блокнот так сохраняет
  /// «Юникод», и половина байтов такого текста — нули.
  static bool _hasUtf16Bom(List<int> b) =>
      b.length >= 2 &&
      ((b[0] == 0xFF && b[1] == 0xFE) || (b[0] == 0xFE && b[1] == 0xFF));

  /// Текст это или бинарник.
  ///
  /// Смотрим на БАЙТЫ, а не на разобранную строку: cp1251-декодер разворачивает
  /// любой байт в букву, и мусор из `.mobi` неотличим от русского текста уже
  /// после декодирования. Нулевой байт в первых килобайтах — верный признак
  /// бинарного файла, в тексте его не бывает. Исключение — UTF-16 с BOM.
  static bool _looksBinary(List<int> head) {
    if (head.isEmpty) return false;
    if (_hasUtf16Bom(head)) return false;
    var control = 0;
    for (final b in head) {
      if (b == 0x00) return true;
      final isPlainWhitespace = b == 0x09 || b == 0x0A || b == 0x0D;
      if (b < 0x20 && !isPlainWhitespace) control++;
    }
    return control * 50 > head.length; // больше 2% управляющих байтов
  }

  /// Проверяет файл ДО разбора: читается ли он вообще.
  ///
  /// Возвращает null, если книгу можно пробовать разбирать. Иначе — отказ с
  /// именем формата для сообщения человеку.
  static Future<ForeignBook?> refuse(String path) async {
    try {
      final file = File(path);
      final length = await file.length();
      final head = await file
          .openRead(0, length < _headBytes ? length : _headBytes)
          .expand((chunk) => chunk)
          .toList();
      return refuseHead(path, head);
    } catch (e) {
      // Ошибка ЧТЕНИЯ — не повод говорить «это не текст»: пропускаем дальше,
      // extract упадёт на том же файле и покажет честное «не удалось открыть».
      debugPrint('BookImport.refuse failed: $e');
      return null;
    }
  }

  /// Тот же заслон по уже прочитанным первым байтам — чтобы `extract` не читал
  /// файл дважды.
  static ForeignBook? refuseHead(String path, List<int> head) {
    final ext = extensionOf(path);
    final byExtension = _foreignByExtension[ext];
    if (byExtension != null) return ForeignBook(byExtension);

    final sniffed = sniffFormat(head);
    if (sniffed != null) return ForeignBook(sniffed);

    // Контейнеры обязаны быть zip-архивом: `.epub`, внутри которого лежит не
    // архив, разбору не поддастся, а сообщение «не удалось открыть» ничего не
    // объясняет.
    if (ext == 'epub' || ext == 'zip') {
      return _isZip(head) ? null : const ForeignBook(null);
    }

    if (_looksBinary(head)) return const ForeignBook(null);
    return null;
  }

  /// Как называть главу без собственного заголовка. Значение приходит из
  /// главного изолята: разбор идёт в фоновом, а там своя копия статики — язык
  /// интерфейса туда не доезжает, и `tr` вернул бы язык по умолчанию.
  static String chapterTemplate = 'Section {n}';

  /// Читает файл по пути и возвращает извлечённый текст (или null при ошибке /
  /// неподдерживаемом формате).
  ///
  /// Разбор идёт в ОТДЕЛЬНОМ ИЗОЛЯТЕ: распаковка epub и разбор fb2 на книге в
  /// несколько мегабайт занимают секунды, а в главном изоляте это застывший
  /// экран и риск «приложение не отвечает».
  static Future<BookText?> extract(String path) => compute(
        _extractInIsolate,
        (path, maxUncompressedBytes, trf('chapter_n', const {})),
      );

  /// У изолята своя копия статических полей: настроенный бюджет распаковки и
  /// название главы передаём аргументом и выставляем на месте.
  static Future<BookText?> _extractInIsolate((String, int, String) args) {
    maxUncompressedBytes = args.$2;
    chapterTemplate = args.$3;
    return extractSync(args.$1);
  }

  /// Тело разбора. Отдельно от [extract], потому что `compute` принимает
  /// только функцию верхнего уровня или статический метод.
  @visibleForTesting
  static Future<BookText?> extractSync(String path) async {
    try {
      final ext = extensionOf(path);
      final file = File(path);
      final bytes = await file.readAsBytes();
      final fallbackTitle = _baseName(path);

      // Второй рубеж: разбор зовут не только из библиотеки, а чужой формат
      // разворачивается в непустую кашу и выглядит как настоящая книга.
      final head = bytes.length > _headBytes ? bytes.sublist(0, _headBytes) : bytes;
      if (refuseHead(path, head) != null) return null;

      switch (ext) {
        case 'epub':
        case 'zip':
          return _fromZip(bytes, fallbackTitle);
        case 'html':
        case 'htm':
        case 'xhtml':
          return BookText(
            title: fallbackTitle,
            text: _htmlToText(_decode(bytes)),
          );
        case 'fb2':
        case 'xml':
          return _fromFb2(_decode(bytes), fallbackTitle);
        case 'srt':
        case 'vtt':
          return BookText(
            title: fallbackTitle,
            text: _subtitlesToText(_decode(bytes)),
          );
        default:
          return _fromPlain(_decode(bytes), fallbackTitle);
      }
    } catch (e) {
      debugPrint('BookImport.extract failed: $e');
      return null;
    }
  }

  /// Декодирует байты книги.
  ///
  /// Сначала строгий UTF-8. Не вышло — почти наверняка это старый русский
  /// текст в Windows-1251 (таких .txt и .fb2 в сети большинство): раньше они
  /// молча превращались в кашу из «?», потому что запасная ветка была
  /// недостижима (`allowMalformed: true` не бросает никогда).
  static String _decode(List<int> bytes) {
    if (_hasUtf16Bom(bytes)) return _decodeUtf16(bytes);
    try {
      return utf8.decode(bytes, allowMalformed: false);
    } catch (_) {
      return _decodeCp1251(bytes);
    }
  }

  /// UTF-16 по BOM. До заслона такие файлы «читались» через cp1251 и
  /// превращались в кашу с нулевыми байтами.
  ///
  /// Одинокие суррогаты заменяются на U+FFFD: строку с непарным суррогатом не
  /// примут ни SQLite, ни jsonEncode — битый файл ронял бы сохранение книги.
  static String _decodeUtf16(List<int> b) {
    final little = b[0] == 0xFF;
    final units = <int>[];
    // Нечётный хвост отбрасываем: битому последнему байту соответствий нет.
    for (var i = 2; i + 1 < b.length; i += 2) {
      units.add(little ? b[i] | (b[i + 1] << 8) : (b[i] << 8) | b[i + 1]);
    }
    for (var i = 0; i < units.length; i++) {
      final u = units[i];
      final isHigh = u >= 0xD800 && u <= 0xDBFF;
      final isLow = u >= 0xDC00 && u <= 0xDFFF;
      if (isHigh &&
          i + 1 < units.length &&
          units[i + 1] >= 0xDC00 &&
          units[i + 1] <= 0xDFFF) {
        i++; // валидная пара
        continue;
      }
      if (isHigh || isLow) units[i] = 0xFFFD;
    }
    return String.fromCharCodes(units);
  }

  /// Верхняя половина таблицы Windows-1251 (байты 0x80–0xFF). Нижняя совпадает
  /// с ASCII.
  static const String _cp1251High =
      'ЂЃ‚ѓ„…†‡€‰Љ‹ЊЌЋЏ'
      'ђ‘’“”•–—\uFFFD™љ›њќћџ'
      '\u00A0ЎўЈ¤Ґ¦§Ё©Є«¬\u00AD®Ї'
      '°±Ііґµ¶·ё№є»јЅѕї'
      'АБВГДЕЖЗИЙКЛМНОП'
      'РСТУФХЦЧШЩЪЫЬЭЮЯ'
      'абвгдежзийклмноп'
      'рстуфхцчшщъыьэюя';

  /// Только для тестов: доступ к декодеру байтов.
  static String debugDecode(List<int> bytes) => _decode(bytes);

  static String _decodeCp1251(List<int> bytes) {
    final buf = StringBuffer();
    for (final b in bytes) {
      if (b < 0x80) {
        buf.writeCharCode(b);
      } else {
        buf.write(_cp1251High[b - 0x80]);
      }
    }
    return buf.toString();
  }

  // ------------------------------- EPUB / zip -------------------------------

  static BookText _fromZip(List<int> bytes, String fallbackTitle) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final byName = <String, ArchiveFile>{};
    var declared = 0;
    for (final f in archive.files) {
      if (!f.isFile) continue;
      declared += f.size;
      if (f.size > maxUncompressedBytes || declared > maxUncompressedBytes) {
        throw const FormatException('zip expands beyond budget');
      }
      byName[f.name] = f;
    }

    // Ищем .opf (спайн = порядок чтения, манифест = id→href, dc:title).
    String? title;
    List<int>? cover;
    List<String> spineHrefs = [];
    final tocTitles = <String, String>{}; // basename → заголовок из оглавления

    final opf = byName.values.where((f) => f.name.toLowerCase().endsWith('.opf'));
    if (opf.isNotEmpty) {
      final raw = _decode(opf.first.content as List<int>);
      title = _fb2Title(raw);
      spineHrefs = _opfSpine(raw);
      cover = _epubCover(byName, raw);
      // Оглавление: ncx или nav.xhtml.
      _collectToc(byName, tocTitles);
    }
    // Запасной вариант обложки — файл-картинка с «cover» в имени.
    cover ??= _fallbackCover(byName);

    final a = _Assembler();
    Iterable<ArchiveFile> ordered;
    if (spineHrefs.isNotEmpty) {
      // Поиск по архиву линейный, поэтому берём файл ОДИН раз на href
      // (раньше _matchByBase звался дважды на каждую главу).
      ordered = [
        for (final href in spineHrefs)
          ?_matchByBase(byName, href),
      ];
    } else {
      // Без opf — по имени файла (обычно = порядок чтения).
      ordered = byName.values
          .where((f) => _isContent(f.name))
          .toList()
        ..sort((x, y) => x.name.compareTo(y.name));
    }

    for (final f in ordered) {
      if (!_isContent(f.name)) continue;
      final raw = _decode(f.content as List<int>);
      final text = _htmlToText(raw);
      if (text.trim().isEmpty) continue;
      final base = _basePath(f.name);
      final chapterTitle = tocTitles[base] ?? _firstHeading(raw) ?? '';
      a.startChapter(chapterTitle);
      a.add(text);
    }

    return BookText(
      title: title ?? fallbackTitle,
      text: a.text,
      chapters: a.cleanChapters,
      cover: cover,
    );
  }

  static bool _isImage(String name) {
    final l = name.toLowerCase();
    return l.endsWith('.jpg') ||
        l.endsWith('.jpeg') ||
        l.endsWith('.png') ||
        l.endsWith('.gif') ||
        l.endsWith('.webp');
  }

  static List<int>? _bytes(ArchiveFile? f) {
    if (f == null) return null;
    final b = f.content as List<int>;
    return b.isEmpty ? null : b;
  }

  static List<int>? _epubCover(Map<String, ArchiveFile> byName, String opf) {
    String? href;
    // 1) <meta name="cover" content="ID"/> → item id=ID.
    final meta = RegExp(r'<meta\b[^>]*>', caseSensitive: false)
        .allMatches(opf)
        .map((m) => m.group(0)!)
        .firstWhere(
          (t) => _attr(t, 'name')?.toLowerCase() == 'cover',
          orElse: () => '',
        );
    final coverId = meta.isEmpty ? null : _attr(meta, 'content');
    // Перебираем manifest-item: ищем по id, либо properties="cover-image".
    for (final m in RegExp(r'<item\b[^>]*>', caseSensitive: false)
        .allMatches(opf)) {
      final tag = m.group(0)!;
      final props = (_attr(tag, 'properties') ?? '').toLowerCase();
      if ((coverId != null && _attr(tag, 'id') == coverId) ||
          props.contains('cover-image')) {
        href = _attr(tag, 'href');
        if (href != null) break;
      }
    }
    if (href == null) return null;
    return _bytes(_matchByBase(byName, href));
  }

  static List<int>? _fallbackCover(Map<String, ArchiveFile> byName) {
    for (final f in byName.values) {
      if (_isImage(f.name) && f.name.toLowerCase().contains('cover')) {
        return _bytes(f);
      }
    }
    return null;
  }

  static bool _isContent(String name) {
    final l = name.toLowerCase();
    return l.endsWith('.xhtml') ||
        l.endsWith('.html') ||
        l.endsWith('.htm') ||
        l.endsWith('.fb2') ||
        (l.endsWith('.xml') && !l.endsWith('.opf') && !l.contains('container'));
  }

  static String _basePath(String name) {
    final slash = name.replaceAll('\\', '/');
    final idx = slash.lastIndexOf('/');
    return (idx < 0 ? slash : slash.substring(idx + 1)).toLowerCase();
  }

  static ArchiveFile? _matchByBase(Map<String, ArchiveFile> byName, String href) {
    final base = _basePath(href.split('#').first);
    for (final entry in byName.entries) {
      if (_basePath(entry.key) == base) return entry.value;
    }
    return null;
  }

  static List<String> _opfSpine(String opf) {
    // id → href из <manifest><item ...>
    final idToHref = <String, String>{};
    for (final m in RegExp(r'<item\b[^>]*>', caseSensitive: false)
        .allMatches(opf)) {
      final tag = m.group(0)!;
      final id = _attr(tag, 'id');
      final href = _attr(tag, 'href');
      if (id != null && href != null) idToHref[id] = href;
    }
    // Порядок из <spine><itemref idref="...">
    final hrefs = <String>[];
    for (final m in RegExp(r'<itemref\b[^>]*>', caseSensitive: false)
        .allMatches(opf)) {
      final idref = _attr(m.group(0)!, 'idref');
      final href = idref == null ? null : idToHref[idref];
      if (href != null) hrefs.add(href);
    }
    return hrefs;
  }

  static void _collectToc(
    Map<String, ArchiveFile> byName,
    Map<String, String> out,
  ) {
    // NCX: <navPoint>...<text>Title</text>...<content src="file"/>
    for (final f in byName.values) {
      if (!f.name.toLowerCase().endsWith('.ncx')) continue;
      final raw = _decode(f.content as List<int>);
      for (final np in RegExp(r'<navPoint\b.*?</navPoint>',
              dotAll: true, caseSensitive: false)
          .allMatches(raw)) {
        final block = np.group(0)!;
        final text = RegExp(r'<text[^>]*>(.*?)</text>',
                dotAll: true, caseSensitive: false)
            .firstMatch(block);
        final src = RegExp(r'<content\b[^>]*\bsrc="([^"]+)"',
                caseSensitive: false)
            .firstMatch(block);
        if (text != null && src != null) {
          final title = _decodeEntities(_stripTags(text.group(1) ?? '')).trim();
          if (title.isNotEmpty) {
            out.putIfAbsent(_basePath(src.group(1)!.split('#').first), () => title);
          }
        }
      }
    }
    // EPUB3 nav.xhtml: <a href="file">Title</a> внутри <nav ... toc>.
    for (final f in byName.values) {
      final l = f.name.toLowerCase();
      if (!l.endsWith('.xhtml') && !l.endsWith('.html')) continue;
      if (!l.contains('nav') && !l.contains('toc')) continue;
      final raw = _decode(f.content as List<int>);
      for (final m in RegExp(r'<a\b[^>]*\bhref="([^"]+)"[^>]*>(.*?)</a>',
              dotAll: true, caseSensitive: false)
          .allMatches(raw)) {
        final title = _decodeEntities(_stripTags(m.group(2) ?? '')).trim();
        if (title.isNotEmpty) {
          out.putIfAbsent(
              _basePath(m.group(1)!.split('#').first), () => title);
        }
      }
    }
  }

  static String? _attr(String tag, String name) {
    final m = RegExp('$name="([^"]*)"', caseSensitive: false).firstMatch(tag) ??
        RegExp("$name='([^']*)'", caseSensitive: false).firstMatch(tag);
    return m?.group(1);
  }

  static String? _firstHeading(String rawHtml) {
    final m = RegExp(r'<h[1-6][^>]*>(.*?)</h[1-6]>',
            dotAll: true, caseSensitive: false)
        .firstMatch(rawHtml);
    if (m == null) return null;
    final t = _decodeEntities(_stripTags(m.group(1) ?? '')).trim();
    return t.isEmpty ? null : (t.length > 80 ? t.substring(0, 80) : t);
  }

  // ------------------------------- FB2 -------------------------------

  static BookText _fromFb2(String raw, String fallbackTitle) {
    final title = _fb2Title(raw) ?? fallbackTitle;
    // body без служебных секций.
    final bodyMatch = RegExp(r'<body\b[^>]*>(.*?)</body>',
            dotAll: true, caseSensitive: false)
        .firstMatch(raw);
    final body = bodyMatch?.group(1) ?? raw;

    // Секции верхнего уровня как главы. Разбор по <section>…</section>.
    final sections = RegExp(r'<section\b[^>]*>(.*?)</section>',
            dotAll: true, caseSensitive: false)
        .allMatches(body)
        .toList();

    final a = _Assembler();
    if (sections.length >= 2) {
      for (final s in sections) {
        final block = s.group(1) ?? '';
        final titleMatch = RegExp(r'<title\b[^>]*>(.*?)</title>',
                dotAll: true, caseSensitive: false)
            .firstMatch(block);
        final chapterTitle = titleMatch == null
            ? ''
            : _decodeEntities(_stripTags(titleMatch.group(1) ?? '')).trim();
        final text = _htmlToText(block);
        if (text.trim().isEmpty) continue;
        a.startChapter(chapterTitle);
        a.add(text);
      }
    }
    if (a.paragraphs.isEmpty) {
      // Нет секций — весь текст одной книгой.
      a.add(_htmlToText(body));
    }

    return BookText(
      title: title,
      text: a.text,
      chapters: a.cleanChapters,
      cover: _fb2Cover(raw),
    );
  }

  static List<int>? _fb2Cover(String raw) {
    // Id обложки из <coverpage>…<image href="#id"/>.
    String? coverId;
    final cp = RegExp(r'<coverpage\b.*?</coverpage>',
            dotAll: true, caseSensitive: false)
        .firstMatch(raw);
    if (cp != null) {
      final img = RegExp(r'href="#?([^"]+)"', caseSensitive: false)
          .firstMatch(cp.group(0)!);
      coverId = img?.group(1);
    }
    // Ищем нужный <binary> (по id) или первую картинку.
    for (final m in RegExp(r'<binary\b([^>]*)>(.*?)</binary>',
            dotAll: true, caseSensitive: false)
        .allMatches(raw)) {
      final attrs = m.group(1) ?? '';
      final id = _attr('<x$attrs>', 'id');
      final ct = (_attr('<x$attrs>', 'content-type') ?? '').toLowerCase();
      final matches = coverId != null ? id == coverId : ct.startsWith('image/');
      if (!matches) continue;
      final b64 = (m.group(2) ?? '').replaceAll(RegExp(r'\s+'), '');
      if (b64.isEmpty) continue;
      try {
        return base64.decode(b64);
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  static String? _fb2Title(String raw) {
    final m = RegExp(r'<dc:title[^>]*>(.*?)</dc:title>',
                dotAll: true, caseSensitive: false)
            .firstMatch(raw) ??
        RegExp(r'<book-title[^>]*>(.*?)</book-title>',
                dotAll: true, caseSensitive: false)
            .firstMatch(raw);
    if (m == null) return null;
    final t = _decodeEntities(_stripTags(m.group(1) ?? '')).trim();
    return t.isEmpty ? null : t;
  }

  // ------------------------------- Простой текст -------------------------------

  // Строка-заголовок главы: «Глава 3», «Chapter IV», «ГЛАВА ПЕРВАЯ».
  // (\b не работает с кириллицей без unicode — используем lookahead на букву.)
  static final RegExp _chapterHeading = RegExp(
    r'^\s*(глава|chapter|часть|part|книга|book)(?![\p{L}]).{0,40}$',
    caseSensitive: false,
    unicode: true,
  );

  static BookText _fromPlain(String raw, String fallbackTitle) {
    final normalized = _normalize(raw);
    final lines = normalized.split('\n');
    final a = _Assembler();
    for (final line in lines) {
      if (line.trim().isEmpty) continue;
      if (line.length <= 45 && _chapterHeading.hasMatch(line)) {
        a.startChapter(line.trim());
      }
      a.add(line);
    }
    return BookText(
      title: fallbackTitle,
      text: a.text,
      chapters: a.cleanChapters,
    );
  }

  /// SRT/VTT → чистый текст: выбрасываем индексы и таймкоды.
  static String _subtitlesToText(String raw) {
    final out = <String>[];
    for (final line in raw.split(RegExp(r'\r?\n'))) {
      final t = line.trim();
      if (t.isEmpty) continue;
      if (t == 'WEBVTT') continue;
      if (t.contains('-->')) continue;
      if (RegExp(r'^\d+$').hasMatch(t)) continue;
      out.add(_decodeEntities(_stripTags(t)));
    }
    return _normalize(out.join('\n'));
  }

  @visibleForTesting
  static String cleanHtmlForTest(String raw) => _htmlToText(raw);

  /// HTML/XML → текст с сохранением абзацев.
  static String _htmlToText(String raw) {
    var s = raw;
    s = s.replaceAll(
        RegExp(r'<(script|style|head)[^>]*>.*?</\1>',
            dotAll: true, caseSensitive: false),
        ' ');
    s = s.replaceAll(
        RegExp(r'</(p|div|section|article|h[1-6]|li|br|tr|title)\s*>',
            caseSensitive: false),
        '\n');
    s = s.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
    s = _stripTags(s);
    s = _decodeEntities(s);
    return _normalize(s);
  }

  static String _stripTags(String s) =>
      s.replaceAll(RegExp(r'<[^>]+>'), ' ');

  static String _decodeEntities(String s) {
    var r = s;
    const map = {
      '&amp;': '&',
      '&lt;': '<',
      '&gt;': '>',
      '&quot;': '"',
      '&apos;': "'",
      '&#39;': "'",
      '&nbsp;': ' ',
      '&mdash;': '—',
      '&ndash;': '–',
      '&hellip;': '…',
      '&laquo;': '«',
      '&raquo;': '»',
      '&rsquo;': '’',
      '&lsquo;': '‘',
      '&ldquo;': '“',
      '&rdquo;': '”',
    };
    map.forEach((k, v) => r = r.replaceAll(k, v));
    // Номера сущностей в чужом EPUB/FB2 бывают за границей Юникода и длиннее
    // 64 бит — общий помощник отсекает такие, не роняя разбор книги.
    return decodeNumericEntities(r);
  }

  /// Нормализует пробелы: схлопывает пробелы в строке, убирает пустые строки
  /// (оставляя разбиение на абзацы).
  static String _normalize(String s) {
    final lines = s
        .split(RegExp(r'\r?\n'))
        .map((l) => l.replaceAll(RegExp(r'[ \t ]+'), ' ').trim())
        .where((l) => l.isNotEmpty)
        .toList();
    return lines.join('\n');
  }
}
