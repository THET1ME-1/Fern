import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fern/library_screen.dart';
import 'package:fern/l10n/locale_controller.dart';
import 'package:fern/services/deck_repository.dart';

import 'test_helpers.dart';

void main() {
  setUp(() async {
    await resetStorage();
    await DeckRepository.instance.init();
    await LocaleController.instance.setCode('ru');
  });

  testWidgets('Библиотека строится (пустая) без ошибок',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: LibraryScreen()));
    await tester.pump(); // грузит источники (пусто)
    await tester.pump();

    expect(find.text('Библиотека'), findsOneWidget);
    expect(find.text('Добавить книгу'), findsOneWidget); // карточка импорта
    expect(tester.takeException(), isNull);
  });
}
