import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:fern/book_screen.dart';
import 'package:fern/l10n/locale_controller.dart';
import 'package:fern/l10n/strings.dart';
import 'package:fern/models/deck.dart';
import 'package:fern/models/word_card.dart';
import 'package:fern/services/deck_repository.dart';
import 'package:fern/services/source_library.dart';

import 'test_helpers.dart';

/// Фейковый path_provider, чтобы SourceLibrary писала/читала книгу в temp-папку.
class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  final String dir;
  _FakePathProvider(this.dir);
  @override
  Future<String?> getApplicationDocumentsPath() async => dir;
}

void main() {
  setUp(() async {
    await resetStorage();
    await DeckRepository.instance.init();
    await LocaleController.instance.setCode('ru');
  });

  testWidgets('Карточка анализа рендерится с данными без overflow',
      (WidgetTester tester) async {
    final tmp = Directory.systemTemp.createTempSync('fern_book_render');
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);
    addTearDown(() => tmp.deleteSync(recursive: true));

    // Одно известное слово → в анализе будут все три группы (не только синяя).
    await DeckRepository.instance.upsertDeck(Deck(
      id: 'd1',
      languageCode: 'en',
      name: 'EN',
      colorValue: 0xFF2E7D5B,
      shapeIndex: 0,
      createdAt: 1,
    ));
    await DeckRepository.instance.upsertCard(
      WordCard(id: 'c1', deckId: 'd1', front: 'the', back: 'арт'),
    );

    // Всё внутри runAsync — иначе реальное файловое чтение (loadBookText) не
    // прогрессирует под фейковыми часами теста.
    await tester.runAsync(() async {
      final id = await SourceLibrary.instance.saveBook(
        title: 'Тест',
        languageCode: 'en',
        format: 'txt',
        text: 'The cat and the dog. The cat runs and jumps over lazy foxes.',
      );
      final src = (await SourceLibrary.instance.get(id!))!;
      await tester.pumpWidget(MaterialApp(home: BookScreen(source: src)));
      // Дать завершиться чтению файла + пересчёту анализа, затем построить кадр.
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    });

    // Никаких overflow/исключений вёрстки (была бы бесконечная высота плиток).
    expect(tester.takeException(), isNull);
    // Данные анализа на месте — все три группы отрисованы.
    expect(find.text(tr('analysis_unknown')), findsOneWidget);
    expect(find.text(tr('analysis_known')), findsOneWidget);
    expect(find.text(tr('analysis_learning')), findsOneWidget);
  });
}
