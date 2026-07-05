import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';

import '../models/book_chapter.dart';

/// Извлечённый из файла текст книги + предполагаемое название + оглавление.
class BookText {
  final String title;
  final String text;
  final List<BookChapter> chapters;
  const BookText({
    required this.title,
    required this.text,
    this.chapters = const [],
  });

  bool get isEmpty => text.trim().isEmpty;
}

/// Накопитель абзацев и глав: тексты добавляются кусками, главы отмечают
/// индекс абзаца, с которого начинаются (в том же разбиении, что и читалка).
class _Assembler {
  final List<String> paragraphs = [];
  final List<BookChapter> chapters = [];

  void startChapter(String title) {
    final t = title.trim();
    chapters.add(BookChapter(
      t.isEmpty ? 'Раздел ${chapters.length + 1}' : t,
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

  /// Читает файл по пути и возвращает извлечённый текст (или null при ошибке /
  /// неподдерживаемом формате). Тяжёлое парсинг-действие — вызывать в await.
  static Future<BookText?> extract(String path) async {
    try {
      final ext = extensionOf(path);
      final file = File(path);
      final bytes = await file.readAsBytes();
      final fallbackTitle = _baseName(path);

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

  /// Декодирует байты как UTF-8 (с заменой битых), иначе latin1.
  static String _decode(List<int> bytes) {
    try {
      return utf8.decode(bytes, allowMalformed: false);
    } catch (_) {
      try {
        return utf8.decode(bytes, allowMalformed: true);
      } catch (_) {
        return latin1.decode(bytes);
      }
    }
  }

  // ------------------------------- EPUB / zip -------------------------------

  static BookText _fromZip(List<int> bytes, String fallbackTitle) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final byName = <String, ArchiveFile>{};
    for (final f in archive.files) {
      if (f.isFile) byName[f.name] = f;
    }

    // Ищем .opf (спайн = порядок чтения, манифест = id→href, dc:title).
    String? title;
    List<String> spineHrefs = [];
    final tocTitles = <String, String>{}; // basename → заголовок из оглавления

    final opf = byName.values.where((f) => f.name.toLowerCase().endsWith('.opf'));
    if (opf.isNotEmpty) {
      final raw = _decode(opf.first.content as List<int>);
      title = _fb2Title(raw);
      spineHrefs = _opfSpine(raw);
      // Оглавление: ncx или nav.xhtml.
      _collectToc(byName, tocTitles);
    }

    final a = _Assembler();
    Iterable<ArchiveFile> ordered;
    if (spineHrefs.isNotEmpty) {
      ordered = [
        for (final href in spineHrefs)
          if (_matchByBase(byName, href) != null) _matchByBase(byName, href)!,
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
    );
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

    return BookText(title: title, text: a.text, chapters: a.cleanChapters);
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
    r = r.replaceAllMapped(RegExp(r'&#(\d+);'), (m) {
      final code = int.tryParse(m.group(1)!);
      return code == null ? m.group(0)! : String.fromCharCode(code);
    });
    r = r.replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'), (m) {
      final code = int.tryParse(m.group(1)!, radix: 16);
      return code == null ? m.group(0)! : String.fromCharCode(code);
    });
    return r;
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
