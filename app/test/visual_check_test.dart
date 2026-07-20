@Tags(['visual'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fern/l10n/locale_controller.dart';
import 'package:fern/models/deck.dart';
import 'package:fern/models/word_card.dart';
import 'package:fern/services/deck_repository.dart';
import 'package:fern/study/results_screen.dart';
import 'package:fern/study/schedule_explain_screen.dart';
import 'package:fern/study/session_screen.dart';
import 'package:fern/study/study_models.dart';
import 'package:fern/theme/app_theme.dart';

import 'test_helpers.dart';

/// Служебный прогон: рисует новые экраны настоящими шрифтами проекта и
/// складывает PNG рядом с тестами. Нужен, чтобы посмотреть на работу глазами —
/// Linux-сборка на этой машине упирается в snap-тулчейн. Помечен тегом `visual`,
/// в обычный прогон не входит.
Future<void> _loadFonts() async {
  for (final family in const ['Unbounded', 'Onest']) {
    final loader = FontLoader(family)
      ..addFont(File('assets/fonts/$family.ttf')
          .readAsBytes()
          .then((b) => ByteData.view(b.buffer)));
    await loader.load();
  }
}

final _deck = Deck(
  id: 'd1',
  languageCode: 'en',
  name: 'D',
  colorValue: 0xFF2E7D5B,
  shapeIndex: 0,
  createdAt: 1,
);

Future<void> _shoot(WidgetTester tester, String name) async {
  await expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile('shots/$name.png'),
  );
}

Widget _app(Widget home) => MaterialApp(
      theme: AppTheme.dark(const Color(0xFF2E7D5B)),
      home: home,
    );

void main() {
  setUp(() async {
    await resetStorage();
    await DeckRepository.instance.init();
    await LocaleController.instance.setCode('ru');
  });

  setUpAll(_loadFonts);

  testWidgets('сессия: метка причины + подсветка ступени', (tester) async {
    tester.view.physicalSize = const Size(1080, 2280);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final card = WordCard(
      id: 'c1',
      deckId: 'd1',
      front: 'brightness',
      back: 'яркость',
      review: ReviewState(
        stability: 20,
        difficulty: 5,
        state: FsrsState.review,
        reps: 4,
        lastReview: DateTime.now().subtract(const Duration(days: 40)),
        due: DateTime.now().subtract(const Duration(days: 1)),
        nudgedByNeighbour: true,
      ),
    );
    await DeckRepository.instance.upsertDeck(_deck);
    await DeckRepository.instance.upsertCard(card);

    await tester.pumpWidget(_app(
      SessionScreen(deck: _deck, mode: StudyMode.flashcards, cards: [card]),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Показать ответ'));
    await tester.pumpAndSettle();
    await _shoot(tester, 'session_reason_and_pick');
  });

  testWidgets('результаты: что сделал алгоритм', (tester) async {
    tester.view.physicalSize = const Size(1080, 2280);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_app(
      const ResultsScreen(
        result: SessionResult(
          24,
          21,
          Duration(minutes: 6, seconds: 12),
          plan: SessionPlan(
            byReason: {
              SelectionReason.due: 14,
              SelectionReason.book: 6,
              SelectionReason.neighbourLapse: 4,
            },
            separatedPairs: 3,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await _shoot(tester, 'results_plan');
  });

  testWidgets('как Fern решает: мало данных', (tester) async {
    tester.view.physicalSize = const Size(1080, 2280);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_app(const ScheduleExplainScreen()));
    await tester.pumpAndSettle();
    await _shoot(tester, 'explain_empty');
  });

  testWidgets('как Fern решает: с историей', (tester) async {
    tester.view.physicalSize = const Size(1080, 2280);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repo = DeckRepository.instance;
    final card =
        WordCard(id: 'c1', deckId: 'd1', front: 'hello', back: 'привет');
    await repo.upsertCard(card);
    var at = DateTime(2026, 1, 1, 12);
    for (var i = 0; i < 140; i++) {
      await repo.rateCard(card, i % 8 == 0 ? Rating.again : Rating.good, at,
          answerMs: 1800 + (i % 5) * 400);
      at = card.review.due ?? at.add(const Duration(days: 1));
    }

    await tester.pumpWidget(_app(const ScheduleExplainScreen()));
    await tester.pumpAndSettle();
    await _shoot(tester, 'explain_data');
  });
}
