import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fern/analyze/analyze_screen.dart';
import 'package:fern/models/deck.dart';
import 'package:fern/models/word_card.dart';
import 'package:fern/l10n/locale_controller.dart';
import 'package:fern/services/deck_repository.dart';

import 'test_helpers.dart';

void main() {
  final repo = DeckRepository.instance;

  setUp(() async {
    await resetStorage();
    await repo.init();
    await repo.setSelectedLanguageCode('en');
    await LocaleController.instance.setCode('ru');
    await repo.upsertDeck(Deck(
      id: 'd1',
      languageCode: 'en',
      name: 'EN',
      colorValue: 0xFF2E7D5B,
      shapeIndex: 0,
      createdAt: 1,
    ));
    await repo.upsertCard(WordCard(
      id: 'c_hour',
      deckId: 'd1',
      front: 'hour',
      back: 'час',
      review: ReviewState(
        state: FsrsState.review,
        stability: 200,
        difficulty: 5,
        reps: 4,
        lastReview: DateTime.now(),
      ),
    ));
  });

  testWidgets('разбор показывает статистику, слова и грамматику',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 3400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.runAsync(() async {
      await tester.pumpWidget(const MaterialApp(
        home: AnalyzeScreen(initialText: 'I have been waiting for an hour.'),
      ));
      // Разбор идёт после загрузки каталога — даём кадрам пройти без
      // pumpAndSettle: на экране живёт вечная анимация ожидания.
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 120));
      }
    });

    // Статистика: знакомое слово одно (hour), остальные незнакомы.
    expect(find.text('Знакомо 14% текста'), findsOneWidget);
    // Найденная конструкция с объяснением и уровнем.
    expect(find.text('Present Perfect Continuous'), findsOneWidget);
    expect(find.text('B1'), findsWidgets);
    // Незнакомые слова предложены к добавлению.
    expect(find.text('waiting'), findsWidgets);
    expect(find.textContaining('Добавить все'), findsOneWidget);
  });

  testWidgets('пустой экран объясняет, что делать', (tester) async {
    tester.view.physicalSize = const Size(1400, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: AnalyzeScreen()));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Текст ещё не разобран'), findsOneWidget);
    expect(find.text('Разобрать'), findsOneWidget);
  });
}

