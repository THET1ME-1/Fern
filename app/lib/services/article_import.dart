import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../utils/html_entity.dart';

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

  /// Потолок скачивания. Статья — это сотни килобайт HTML; ссылка на видеофайл
  /// или дамп без потолка утащила бы в память гигабайты и уронила приложение.
  static const int maxBytes = 5 * 1024 * 1024;

  static Future<Article?> fetch(String url, {http.Client? client}) async {
    final own = client == null;
    final c = client ?? http.Client();
    try {
      final req = http.Request('GET', Uri.parse(url.trim()))
        ..headers['User-Agent'] =
            'Mozilla/5.0 (Android) AppleWebKit/537.36 Fern/1.0';
      final res = await c.send(req).timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) return null;
      // Читаем ПОТОКОМ и останавливаемся на потолке: Content-Length у живых
      // серверов бывает пустым или враньём, верить ему нельзя.
      final buf = BytesBuilder(copy: false);
      await for (final chunk
          in res.stream.timeout(const Duration(seconds: 20))) {
        buf.add(chunk);
        if (buf.length > maxBytes) {
          debugPrint('ArticleImport.fetch: body over $maxBytes bytes');
          return null;
        }
      }
      // Через Response.bytes, чтобы кодировка бралась из заголовков ответа —
      // как делал прежний `res.body`.
      final body = http.Response.bytes(
        buf.takeBytes(),
        res.statusCode,
        headers: res.headers,
      ).body;
      return _extract(body, url);
    } catch (e) {
      debugPrint('ArticleImport.fetch failed: $e');
      return null;
    } finally {
      if (own) c.close();
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
    s = _decodeAll(s);
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
    if (og != null) return _decodeAll(og.group(1)!).trim();
    final t = RegExp(r'<title[^>]*>(.*?)</title>',
            caseSensitive: false, dotAll: true)
        .firstMatch(html);
    if (t != null) {
      return _decodeAll(t.group(1)!.replaceAll(RegExp(r'<[^>]+>'), ''))
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
      .replaceAll('&hellip;', '…');

  /// Числовые сущности разбирает общий помощник: номер приходит с чужой
  /// страницы, и кривой ронял разбор целиком.
  static String _decodeAll(String s) => decodeNumericEntities(_decodeEntities(s));
}
