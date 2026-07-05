import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fern/book_screen.dart';
import 'package:fern/l10n/locale_controller.dart';
import 'package:fern/services/deck_repository.dart';
import 'package:fern/services/source_library.dart';

import 'test_helpers.dart';

void main() {
  setUp(() async {
    await resetStorage();
    await DeckRepository.instance.init();
    await LocaleController.instance.setCode('ru');
  });

  testWidgets('Страница книги строится: шапка, автор, действия',
      (WidgetTester tester) async {
    final src = LibrarySource(
      id: 'src_test',
      kind: SourceKind.book,
      title: 'Тестовая книга',
      languageCode: 'en',
      createdAt: 1,
      format: 'txt',
      author: 'Тестовый автор',
    );

    await tester.pumpWidget(MaterialApp(home: BookScreen(source: src)));
    // Шапка строится сразу (не ждём загрузку текста / path_provider).
    await tester.pump();

    expect(find.text('Тестовая книга'), findsWidgets); // заголовок + шапка
    expect(find.text('Тестовый автор'), findsOneWidget);
    // Кнопки редактирования и удаления в AppBar.
    expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
    expect(find.byIcon(Icons.delete_outline_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
