import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fern/l10n/locale_controller.dart';
import 'package:fern/services/deck_repository.dart';
import 'package:fern/study/book_reader_screen.dart';
import 'package:fern/study/reader_settings.dart';

import 'test_helpers.dart';

void main() {
  setUp(() async {
    await resetStorage();
    await DeckRepository.instance.init();
    await LocaleController.instance.setCode('ru');
    await ReaderSettings.instance.load();
  });

  testWidgets('Читалка строится и прокручивается без ошибок',
      (WidgetTester tester) async {
    const text =
        'The quick brown fox jumps over the lazy dog.\n\n'
        'Sphinx of black quartz judge my vow.\n\n'
        'Pack my box with five dozen liquor jugs.';

    await tester.pumpWidget(const MaterialApp(
      home: BookReaderScreen(
        sourceId: 'src_smoke',
        title: 'Пример',
        languageCode: 'en',
        text: text,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Пример'), findsOneWidget); // заголовок
    expect(tester.takeException(), isNull);

    // Прокрутка не должна ронять исключений.
    await tester.drag(find.byType(BookReaderScreen), const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
