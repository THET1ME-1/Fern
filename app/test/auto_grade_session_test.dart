import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fern/l10n/locale_controller.dart';
import 'package:fern/models/deck.dart';
import 'package:fern/models/word_card.dart';
import 'package:fern/services/deck_repository.dart';
import 'package:fern/study/session_screen.dart';
import 'package:fern/study/study_models.dart';

import 'test_helpers.dart';

final _deck = Deck(
  id: 'd1',
  languageCode: 'en',
  name: 'D',
  colorValue: 0xFF2E7D5B,
  shapeIndex: 0,
  createdAt: 1,
);

Future<WordCard> _setUp(WidgetTester tester) async {
  await resetStorage();
  await DeckRepository.instance.init();
  await LocaleController.instance.setCode('ru');
  final card =
      WordCard(id: 'c1', deckId: 'd1', front: 'hello', back: 'привет');
  await DeckRepository.instance.upsertDeck(_deck);
  await DeckRepository.instance.upsertCard(card);

  tester.view.physicalSize = const Size(1200, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  return card;
}

Future<void> _open(WidgetTester tester, StudyMode mode, WordCard card) async {
  await tester.pumpWidget(MaterialApp(
    home: SessionScreen(deck: _deck, mode: mode, cards: [card]),
  ));
  await tester.pumpAndSettle();
}

void main() {
  final repo = DeckRepository.instance;

  testWidgets('время ответа доезжает до журнала повторов',
      (WidgetTester tester) async {
    final card = await _setUp(tester);
    await _open(tester, StudyMode.flashcards, card);

    await tester.tap(find.text('Показать ответ'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Хорошо'));
    await tester.pumpAndSettle();

    final events = await repo.reviewEvents();
    expect(events.single.answerMs, isNotNull,
        reason: 'сессия обязана замерять время — на нём стоит автооценка');
    expect(events.single.answerMs, greaterThanOrEqualTo(0));
  });

  testWidgets('флип подсказывает оценку по времени ответа',
      (WidgetTester tester) async {
    final card = await _setUp(tester);
    await _open(tester, StudyMode.flashcards, card);

    // Пока ответ закрыт, советовать нечего.
    expect(find.textContaining('по времени ответа'), findsNothing);

    await tester.tap(find.text('Показать ответ'));
    await tester.pumpAndSettle();

    expect(find.textContaining('по времени ответа'), findsOneWidget,
        reason: 'подпись объясняет, откуда взялась подсветка');
  });

  testWidgets('точный набранный ответ оценивается сам, без кнопок',
      (WidgetTester tester) async {
    final card = await _setUp(tester);
    await _open(tester, StudyMode.write, card);

    await tester.enterText(find.byType(TextField), 'привет');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Дальше'));
    await tester.pumpAndSettle();

    final events = await repo.reviewEvents();
    expect(events.single.grade, greaterThanOrEqualTo(Rating.good.grade),
        reason: 'слово в слово — не ниже «хорошо»');
  });

  testWidgets('описка судится строже точного попадания',
      (WidgetTester tester) async {
    final card = await _setUp(tester);
    await _open(tester, StudyMode.write, card);

    // «привт» — потеряна одна буква: ответ засчитывается, но с натяжкой.
    await tester.enterText(find.byType(TextField), 'привт');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.textContaining('Одна буква мимо'), findsOneWidget);
    await tester.tap(find.text('Дальше'));
    await tester.pumpAndSettle();

    final events = await repo.reviewEvents();
    expect(events.single.grade, Rating.hard.grade);
  });

  testWidgets('режим двух кнопок ставит ступень сам',
      (WidgetTester tester) async {
    final card = await _setUp(tester);
    await repo.setTwoButtonRating(true);
    await _open(tester, StudyMode.flashcards, card);

    await tester.tap(find.text('Показать ответ'));
    await tester.pumpAndSettle();

    expect(find.text('Помню'), findsOneWidget);
    expect(find.text('Не помню'), findsOneWidget);
    expect(find.text('Трудно'), findsNothing,
        reason: 'в режиме двух кнопок четырёх ступеней быть не должно');

    await tester.tap(find.text('Помню'));
    await tester.pumpAndSettle();

    final events = await repo.reviewEvents();
    expect(events.single.grade, greaterThan(Rating.again.grade));
  });
}
