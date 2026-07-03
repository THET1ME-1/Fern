import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fern/deck_screen.dart';
import 'package:fern/l10n/locale_controller.dart';
import 'package:fern/models/deck.dart';
import 'package:fern/services/deck_repository.dart';

import 'test_helpers.dart';

void main() {
  final repo = DeckRepository.instance;

  setUp(() async {
    await resetStorage();
    await repo.init();
    await LocaleController.instance.setCode('ru');
  });

  testWidgets('Добавление слова через UI: карточка появляется и сохраняется',
      (WidgetTester tester) async {
    final deck = Deck(
      id: 'd1',
      languageCode: 'en',
      name: 'Тест',
      colorValue: 0xFF2E7D5B,
      shapeIndex: 0,
      createdAt: 1,
    );
    await repo.upsertDeck(deck);

    // Высокий экран, чтобы весь список поместился (иначе ленивый ListView
    // не строит элементы ниже сгиба и find.text их не находит).
    tester.view.physicalSize = const Size(1000, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(home: DeckScreen(deck: deck)));
    await tester.pumpAndSettle();

    // Открываем редактор карточки (FAB).
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    // Заполняем слово и перевод.
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'apple');
    await tester.enterText(fields.at(1), 'яблоко');

    // Сохраняем.
    await tester.tap(find.text('Сохранить'));
    // Прокачиваем кадры: закрытие листа + upsert + перезагрузка списка
    // (перезагрузка идёт через слушателя репозитория — несколько микротасков).
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    // Реально сохранена в репозитории...
    final cards = await repo.cardsForDeck('d1');
    expect(cards.length, 1, reason: 'карта должна сохраниться в репозитории');
    expect(cards.first.front, 'apple');

    // ...и видна в списке.
    await tester.pumpAndSettle();
    expect(find.text('apple'), findsOneWidget);
    expect(find.text('яблоко'), findsOneWidget);
  });
}
