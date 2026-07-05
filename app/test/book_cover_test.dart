import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:fern/services/book_import.dart';

void main() {
  // 1×1 PNG.
  const pngB64 =
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==';

  test('FB2: обложка извлекается из <binary>', () async {
    final dir = Directory.systemTemp.createTempSync('fern_cover');
    addTearDown(() => dir.deleteSync(recursive: true));
    final f = File('${dir.path}/book.fb2');
    await f.writeAsString(
      '<FictionBook><description><title-info>'
      '<book-title>Обложка</book-title>'
      '<coverpage><image href="#cover.png"/></coverpage>'
      '</title-info></description>'
      '<body><section><title><p>Гл</p></title><p>Текст.</p></section></body>'
      '<binary id="cover.png" content-type="image/png">$pngB64</binary>'
      '</FictionBook>',
    );

    final book = await BookImport.extract(f.path);
    expect(book, isNotNull);
    expect(book!.cover, isNotNull);
    // PNG-сигнатура.
    expect(book.cover!.take(4).toList(), [0x89, 0x50, 0x4E, 0x47]);
  });

  test('TXT: обложки нет', () async {
    final dir = Directory.systemTemp.createTempSync('fern_nocover');
    addTearDown(() => dir.deleteSync(recursive: true));
    final f = File('${dir.path}/plain.txt');
    await f.writeAsString('Просто текст.');
    final book = await BookImport.extract(f.path);
    expect(book!.cover, isNull);
  });
}
