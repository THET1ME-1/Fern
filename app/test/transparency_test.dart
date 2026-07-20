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

final _now = DateTime.now();

/// Просроченная зрелая карта.
WordCard _overdue(String id, String front, String back,
        {bool nudged = false}) =>
    WordCard(
      id: id,
      deckId: 'd1',
      front: front,
      back: back,
      review: ReviewState(
        stability: 20,
        difficulty: 5,
        state: FsrsState.review,
        reps: 4,
        lastReview: _now.subtract(const Duration(days: 40)),
        due: _now.subtract(const Duration(days: 1)),
        nudgedByNeighbour: nudged,
      ),
    );

Future<void> _setUp(WidgetTester tester, List<WordCard> cards) async {
  await resetStorage();
  await DeckRepository.instance.init();
  await LocaleController.instance.setCode('ru');
  await DeckRepository.instance.upsertDeck(_deck);
  for (final c in cards) {
    await DeckRepository.instance.upsertCard(c);
  }
  tester.view.physicalSize = const Size(1200, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(MaterialApp(
    home: SessionScreen(
      deck: _deck,
      mode: StudyMode.flashcards,
      cards: cards,
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  group('Метка причины в сессии', () {
    testWidgets('карта, подтянутая за соседом, объясняет себя',
        (WidgetTester tester) async {
      await _setUp(tester, [_overdue('c1', 'bright', 'яркий', nudged: true)]);

      expect(find.text('Сосед сорвался'), findsOneWidget);
    });

    testWidgets('обычный повтор по сроку метки не носит',
        (WidgetTester tester) async {
      await _setUp(tester, [_overdue('c1', 'table', 'стол')]);

      expect(find.text('Сосед сорвался'), findsNothing);
      expect(find.text('Новое слово'), findsNothing);
    });

    testWidgets('новое слово помечено', (WidgetTester tester) async {
      await _setUp(tester,
          [WordCard(id: 'n1', deckId: 'd1', front: 'window', back: 'окно')]);

      expect(find.text('Новое слово'), findsOneWidget);
    });
  });

  group('Сводка «Что сделал алгоритм»', () {
    testWidgets('после сессии перечисляет, что планировщик решил сам',
        (WidgetTester tester) async {
      await _setUp(tester, [_overdue('c1', 'bright', 'яркий', nudged: true)]);

      await tester.tap(find.text('Показать ответ'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Хорошо'));
      await tester.pumpAndSettle();

      expect(find.text('Что сделал алгоритм'), findsOneWidget);
      expect(find.textContaining('раньше срока'), findsOneWidget);
    });

    testWidgets('когда решать было нечего, сводки нет',
        (WidgetTester tester) async {
      await _setUp(tester, [_overdue('c1', 'table', 'стол')]);

      await tester.tap(find.text('Показать ответ'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Хорошо'));
      await tester.pumpAndSettle();

      expect(find.text('Что сделал алгоритм'), findsNothing,
          reason: 'обычная сессия по срокам объяснений не требует');
    });
  });
}
