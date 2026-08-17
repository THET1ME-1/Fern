import 'package:flutter_test/flutter_test.dart';

import 'package:fern/services/article_import.dart';
import 'package:fern/services/book_import.dart';

/// Числовые HTML-сущности приходят с чужой страницы, а не из своего кода:
/// проверяем, что кривые (слишком большие, вне диапазона Юникода) не роняют
/// разбор статьи, а остаются текстом.
void main() {
  Article parse(String body) => ArticleImport.parseForTest(
        '<html><head><title>T</title></head><body><p>$body</p></body></html>',
        'https://example.com/a',
      );

  test('обычные сущности разворачиваются', () {
    expect(parse('&#1055;&#1088;&#1080; &#x43;&#x61;&#x74;').text,
        contains('При Cat'));
  });

  test('эмодзи вне BMP не ломает разбор', () {
    expect(parse('привет &#128512; мир').text, contains('привет'));
  });

  test('номер за пределами Юникода не роняет разбор', () {
    final a = parse('число &#1114112; конец');
    expect(a.text, contains('число'));
    expect(a.text, contains('конец'));
  });

  test('огромное число не роняет разбор', () {
    final a = parse('число &#99999999999999999999999; конец');
    expect(a.text, contains('конец'));
  });

  test('огромное шестнадцатеричное не роняет разбор', () {
    final a = parse('число &#xFFFFFFFFFFFFFFFFFF; конец');
    expect(a.text, contains('конец'));
  });

  test('отрицательного диапазона нет: суррогат остаётся текстом', () {
    // U+D800 — одинокий суррогат: строку с ним не примут ни SQLite, ни jsonEncode.
    final a = parse('текст &#55296; хвост');
    expect(a.text, contains('текст'));
    expect(a.text, contains('хвост'));
    expect(a.text.runes.every((r) => r < 0xD800 || r > 0xDFFF), isTrue);
  });

  test('книга: кривая сущность не роняет разбор и не даёт суррогатов', () {
    final txt = BookImport.cleanHtmlForTest(
        '<p>текст &#1114112; и &#99999999999999999999; и &#55296; хвост</p>');
    expect(txt, contains('текст'));
    expect(txt, contains('хвост'));
    expect(txt.runes.every((r) => r < 0xD800 || r > 0xDFFF), isTrue);
  });
}
