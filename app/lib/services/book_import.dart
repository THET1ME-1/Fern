import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';

/// Извлечённый из файла текст книги + предполагаемое название.
class BookText {
  final String title;
  final String text;
  const BookText({required this.title, required this.text});

  bool get isEmpty => text.trim().isEmpty;
}

/// Импорт книг из текстовых форматов: `txt`, `md`, `csv`, `srt`, `vtt`,
/// `html`, `xml`, `fb2`, `epub`, `fb2.zip`. PDF не поддерживается (бинарный
/// формат) — попросим экспортировать в TXT/EPUB.
class BookImport {
  const BookImport._();

  /// Форматы, которые умеем открывать (для диалога выбора файла и подсказок).
  static const List<String> supportedExtensions = [
    'txt', 'md', 'markdown', 'text', 'csv', 'log',
    'srt', 'vtt',
    'html', 'htm', 'xhtml', 'xml', 'fb2',
    'epub', 'zip',
  ];

  static String extensionOf(String path) {
    final name = path.split(Platform.pathSeparator).last;
    // fb2.zip → «fb2» по смыслу, но обрабатываем как zip; берём последнее.
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
          final raw = _decode(bytes);
          return BookText(
            title: _fb2Title(raw) ?? fallbackTitle,
            text: _htmlToText(raw),
          );
        case 'srt':
        case 'vtt':
          return BookText(
            title: fallbackTitle,
            text: _subtitlesToText(_decode(bytes)),
          );
        default:
          // txt/md/csv/log и прочий простой текст.
          return BookText(title: fallbackTitle, text: _normalize(_decode(bytes)));
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

  /// EPUB / fb2.zip: распаковываем и склеиваем текст из xhtml/html/fb2/xml.
  static BookText _fromZip(List<int> bytes, String fallbackTitle) {
    final archive = ZipDecoder().decodeBytes(bytes);
    // Название из .opf (<dc:title>), если найдём.
    String? title;
    final buffer = StringBuffer();

    // Сортируем контент по имени файла — обычно совпадает с порядком чтения.
    final entries = archive.files.where((f) => f.isFile).toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    for (final f in entries) {
      final lower = f.name.toLowerCase();
      final List<int> content = f.content;
      if (content.isEmpty) continue;
      if (lower.endsWith('.opf')) {
        title ??= _fb2Title(_decode(content));
        continue;
      }
      if (lower.endsWith('.xhtml') ||
          lower.endsWith('.html') ||
          lower.endsWith('.htm') ||
          lower.endsWith('.fb2') ||
          lower.endsWith('.xml')) {
        final t = _htmlToText(_decode(content));
        if (t.trim().isNotEmpty) {
          buffer.writeln(t);
          buffer.writeln();
        }
      }
    }
    return BookText(
      title: title ?? fallbackTitle,
      text: buffer.toString().trim(),
    );
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

  /// SRT/VTT → чистый текст: выбрасываем индексы и таймкоды.
  static String _subtitlesToText(String raw) {
    final out = <String>[];
    for (final line in raw.split(RegExp(r'\r?\n'))) {
      final t = line.trim();
      if (t.isEmpty) continue;
      if (t == 'WEBVTT') continue;
      if (t.contains('-->')) continue;
      if (RegExp(r'^\d+$').hasMatch(t)) continue; // порядковый номер
      out.add(_decodeEntities(_stripTags(t)));
    }
    return _normalize(out.join('\n'));
  }

  /// HTML/XML → текст с сохранением абзацев.
  static String _htmlToText(String raw) {
    var s = raw;
    // Выкидываем служебные блоки.
    s = s.replaceAll(
        RegExp(r'<(script|style|head)[^>]*>.*?</\1>',
            dotAll: true, caseSensitive: false),
        ' ');
    // Блочные теги → перенос строки.
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
    // Числовые сущности &#NNN; и &#xHH;
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
  /// (оставляя разбиение на абзацы), режет запредельно длинный ввод.
  static String _normalize(String s) {
    final lines = s
        .split(RegExp(r'\r?\n'))
        .map((l) => l.replaceAll(RegExp(r'[ \t ]+'), ' ').trim())
        .where((l) => l.isNotEmpty)
        .toList();
    return lines.join('\n');
  }
}
