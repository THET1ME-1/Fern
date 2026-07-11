import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Разобранная веб-статья: заголовок + чистый текст для чтения.
class Article {
  final String title;
  final String text;
  const Article(this.title, this.text);

  bool get hasText => text.trim().length > 40;
}

/// Импорт статьи по ссылке: тянет страницу и извлекает читаемый текст
/// (readability-lite — вырезает скрипты/навигацию/подвалы, предпочитает
/// `<article>`/`<main>`). Без внешних зависимостей сверх уже используемого http.
class ArticleImport {
  ArticleImport._();

  static final RegExp _urlRe = RegExp(r'https?://\S+', caseSensitive: false);

  /// Первая ссылка в тексте (или null).
  static String? firstUrl(String text) => _urlRe.firstMatch(text)?.group(0);

  static Future<Article?> fetch(String url) async {
    try {
      final res = await http.get(
        Uri.parse(url.trim()),
        headers: const {
          'User-Agent':
              'Mozilla/5.0 (Android) AppleWebKit/537.36 Fern/1.0',
        },
      ).timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) return null;
      return _extract(res.body, url);
    } catch (e) {
      debugPrint('ArticleImport.fetch failed: $e');
      return null;
    }
  }

  @visibleForTesting
  static Article parseForTest(String html, String url) => _extract(html, url);

  static Article _extract(String html, String url) {
    final title = _title(html) ?? _hostOf(url);
    var body = html;
    // Убираем неконтентные блоки целиком.
    for (final tag in const [
      'script', 'style', 'noscript', 'nav', 'header', 'footer', 'aside',
      'form', 'svg', 'template'
    ]) {
      body = body.replaceAll(
        RegExp('<$tag\\b[^>]*>.*?</$tag>',
            caseSensitive: false, dotAll: true),
        ' ',
      );
    }
    // Предпочитаем основной контент, если размечен.
    final main = RegExp(r'<(article|main)\b[^>]*>(.*?)</\1>',
            caseSensitive: false, dotAll: true)
        .firstMatch(body);
    if (main != null) body = main.group(2)!;
    return Article(title, _htmlToText(body));
  }

  static String _htmlToText(String html) {
    var s = html;
    // Блочные теги → перенос строки (абзацы).
    s = s.replaceAll(
        RegExp(r'</(p|div|li|h[1-6]|tr|section|article|blockquote)>',
            caseSensitive: false),
        '\n');
    s = s.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
    s = s.replaceAll(RegExp(r'<[^>]+>'), ' '); // остальные теги
    s = _decodeEntities(s);
    // Чистим пробелы и пустые строки, схлопываем повторы.
    final lines = <String>[];
    for (final raw in s.split('\n')) {
      final line = raw.replaceAll(RegExp(r'[ \t ]+'), ' ').trim();
      if (line.isNotEmpty) lines.add(line);
    }
    return lines.join('\n');
  }

  static String? _title(String html) {
    final og = RegExp(
            r'<meta\b[^>]*property=["' "'" r']og:title["' "'" r'][^>]*content=["' "'" r']([^"' "'" r']+)',
            caseSensitive: false)
        .firstMatch(html);
    if (og != null) return _decodeEntities(og.group(1)!).trim();
    final t = RegExp(r'<title[^>]*>(.*?)</title>',
            caseSensitive: false, dotAll: true)
        .firstMatch(html);
    if (t != null) {
      return _decodeEntities(t.group(1)!.replaceAll(RegExp(r'<[^>]+>'), ''))
          .trim();
    }
    return null;
  }

  static String _hostOf(String url) {
    try {
      return Uri.parse(url).host;
    } catch (_) {
      return 'Article';
    }
  }

  static String _decodeEntities(String s) => s
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&apos;', "'")
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&mdash;', '—')
      .replaceAll('&ndash;', '–')
      .replaceAll('&laquo;', '«')
      .replaceAll('&raquo;', '»')
      .replaceAllMapped(RegExp(r'&#(\d+);'),
          (m) => String.fromCharCode(int.parse(m.group(1)!)))
      .replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'),
          (m) => String.fromCharCode(int.parse(m.group(1)!, radix: 16)));
}
