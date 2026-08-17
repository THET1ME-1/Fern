import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fern/utils/picked_file.dart';

/// Отмена выбора файла возвращает не только `null`: на части устройств приходит
/// результат с пустым списком, и `files.single` ронял импорт книги.
void main() {
  test('отмена (null) — пути нет', () {
    expect(pickedPath(null), isNull);
  });

  test('пустой результат — пути нет, а не падение', () {
    expect(pickedPath(FilePickerResult(const [])), isNull);
  });

  test('обычный выбор даёт путь', () {
    final r = FilePickerResult([
      PlatformFile(name: 'book.epub', size: 10, path: '/tmp/book.epub'),
    ]);
    expect(pickedPath(r), '/tmp/book.epub');
  });

  test('несколько файлов: берём первый, а не падаем', () {
    final r = FilePickerResult([
      PlatformFile(name: 'a.epub', size: 1, path: '/tmp/a.epub'),
      PlatformFile(name: 'b.epub', size: 1, path: '/tmp/b.epub'),
    ]);
    expect(pickedPath(r), '/tmp/a.epub');
  });
}
