import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fern/l10n/locale_controller.dart';
import 'package:fern/models/word_card.dart';
import 'package:fern/services/deck_repository.dart';
import 'package:fern/study/schedule_explain_screen.dart';

import 'test_helpers.dart';

/// Копит историю повторов: карту учат раз в несколько дней, изредка срываясь.
Future<void> _seedHistory(int reviews) async {
  final repo = DeckRepository.instance;
  final card = WordCard(id: 'c1', deckId: 'd1', front: 'hello', back: 'привет');
  await repo.upsertCard(card);
  var at = DateTime(2026, 1, 1, 12);
  for (var i = 0; i < reviews; i++) {
    await repo.rateCard(card, i % 7 == 0 ? Rating.again : Rating.good, at,
        answerMs: 2000 + i * 10);
    at = card.review.due ?? at.add(const Duration(days: 1));
  }
}

Future<void> _open(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1200, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(const MaterialApp(home: ScheduleExplainScreen()));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() async {
    await resetStorage();
    await DeckRepository.instance.init();
    await LocaleController.instance.setCode('ru');
  });

  testWidgets('без истории экран честно говорит, что мерить нечего',
      (WidgetTester tester) async {
    await _open(tester);

    expect(find.textContaining('Мало данных'), findsOneWidget);
  });

  testWidgets('на накопленной истории показывает удержание и сравнение',
      (WidgetTester tester) async {
    await _seedHistory(120);
    await _open(tester);

    expect(find.text('УДЕРЖАНИЕ'), findsOneWidget);
    expect(find.text('Точность предсказаний'), findsOneWidget);
    // Оговорка обязательна: цифра про предсказания, а не про объём памяти.
    expect(find.textContaining('не значит'), findsOneWidget);
  });
}
