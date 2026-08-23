import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:fern/l10n/locale_controller.dart';
import 'package:fern/services/book_import.dart';

import 'test_helpers.dart';

void main() {
  test('FB2: секции становятся главами', () async {
    final dir = Directory.systemTemp.createTempSync('fern_fb2');
    addTearDown(() => dir.deleteSync(recursive: true));
    final f = File('${dir.path}/book.fb2');
    await f.writeAsString(
      '<FictionBook><description><title-info>'
      '<book-title>Тест</book-title></title-info></description><body>'
      '<section><title><p>Глава первая</p></title>'
      '<p>Первый абзац.</p><p>Второй абзац.</p></section>'
      '<section><title><p>Глава вторая</p></title>'
      '<p>Третий абзац.</p></section>'
      '</body></FictionBook>',
    );

    final book = await BookImport.extract(f.path);
    expect(book, isNotNull);
    expect(book!.title, 'Тест');
    expect(book.chapters.length, 2);
    expect(book.chapters[0].title, 'Глава первая');
    expect(book.chapters[0].startParagraph, 0);
    expect(book.chapters[1].title, 'Глава вторая');
    expect(book.chapters[1].startParagraph, greaterThan(0));
  });

  test('TXT: строки-заголовки распознаются как главы', () async {
    final dir = Directory.systemTemp.createTempSync('fern_txt');
    addTearDown(() => dir.deleteSync(recursive: true));
    final f = File('${dir.path}/book.txt');
    await f.writeAsString(
      'Глава 1\n'
      'Первый абзац главы один.\n'
      'Ещё абзац.\n'
      'Глава 2\n'
      'Абзац главы два.\n',
    );

    final book = await BookImport.extract(f.path);
    expect(book!.chapters.length, 2);
    expect(book.chapters[0].title, 'Глава 1');
    expect(book.chapters[1].title, 'Глава 2');
    expect(book.chapters[1].startParagraph, 3);
  });

  test('Обычный текст без заголовков — без глав', () async {
    final dir = Directory.systemTemp.createTempSync('fern_txt2');
    addTearDown(() => dir.deleteSync(recursive: true));
    final f = File('${dir.path}/plain.txt');
    await f.writeAsString('Просто текст.\nВторая строка.\n');
    final book = await BookImport.extract(f.path);
    expect(book!.chapters, isEmpty);
  });


  test('глава без заголовка называется на языке интерфейса', () async {
    // Разбор идёт в фоновом изоляте, где своя копия статики: если шаблон
    // названия не передать аргументом, глава получит язык по умолчанию.
    await resetStorage();
    await LocaleController.instance.setCode('ru');
    addTearDown(() => LocaleController.instance.setCode('en'));

    final dir = Directory.systemTemp.createTempSync('fern_untitled');
    addTearDown(() => dir.deleteSync(recursive: true));
    final f = File('${dir.path}/book.fb2');
    await f.writeAsString(
      '<FictionBook><description><title-info>'
      '<book-title>Без имён</book-title></title-info></description><body>'
      '<section><p>Первый абзац.</p></section>'
      '<section><p>Второй абзац.</p></section>'
      '</body></FictionBook>',
    );

    final book = await BookImport.extract(f.path);
    expect(book, isNotNull);
    expect(book!.chapters.map((c) => c.title), ['Раздел 1', 'Раздел 2']);
  });
}
