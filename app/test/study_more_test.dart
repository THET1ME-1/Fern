import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fern/l10n/locale_controller.dart';
import 'package:fern/models/deck.dart';
import 'package:fern/models/word_card.dart';
import 'package:fern/services/deck_repository.dart';
import 'package:fern/study/session_screen.dart';
import 'package:fern/study/study_models.dart';

import 'test_helpers.dart';

void main() {
  final repo = DeckRepository.instance;

  testWidgets('«Ещё сессия» после результатов запускает новую сессию',
      (WidgetTester tester) async {
    await resetStorage();
    await repo.init();
    await LocaleController.instance.setCode('ru');
    final deck = Deck(
      id: 'd1',
      languageCode: 'en',
      name: 'D',
      colorValue: 0xFF2E7D5B,
      shapeIndex: 0,
      createdAt: 1,
    );
    final card = WordCard(id: 'c1', deckId: 'd1', front: 'hello', back: 'привет');
    await repo.upsertDeck(deck);
    await repo.upsertCard(card);

    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
      home: SessionScreen(
        deck: deck,
        mode: StudyMode.flashcards,
        cards: [card],
      ),
    ));
    await tester.pumpAndSettle();

    // Проходим единственную карточку до конца сессии.
    await tester.tap(find.text('Показать ответ'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Хорошо'));
    await tester.pumpAndSettle();

    // Экран результатов заменил сессию — SessionScreen'а в дереве нет.
    expect(find.text('Ещё сессия'), findsOneWidget);
    expect(find.byType(SessionScreen), findsNothing);

    // Тап «Ещё сессия» должен запустить НОВУЮ сессию.
    await tester.tap(find.text('Ещё сессия'));
    await tester.pumpAndSettle();

    expect(find.byType(SessionScreen), findsOneWidget,
        reason: 'кнопка «Ещё сессия» должна открывать новую сессию');
  });
}
