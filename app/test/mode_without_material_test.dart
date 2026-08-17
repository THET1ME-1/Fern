import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fern/l10n/locale_controller.dart';
import 'package:fern/models/deck.dart';
import 'package:fern/models/word_card.dart';
import 'package:fern/services/deck_repository.dart';
import 'package:fern/study/session_screen.dart';
import 'package:fern/study/study_models.dart';

import 'test_helpers.dart';

/// «Контекст» и «Связи» живут на особых карточках: первому нужен пример-
/// предложение, второму — слова одной темы. Когда таких карточек нет, экран
/// раньше говорил «Пока нечего повторять, возвращайтесь позже» — человек ждал
/// следующего дня, хотя ждать было нечего.
void main() {
  final deck = Deck(
    id: 'd1',
    languageCode: 'en',
    name: 'Слова',
    colorValue: 0xFF2E7D5B,
    shapeIndex: 0,
    createdAt: 1,
  );

  setUp(() async {
    await resetStorage();
    await DeckRepository.instance.init();
    await LocaleController.instance.setCode('ru');
    await DeckRepository.instance.upsertDeck(deck);
  });

  Future<void> pump(WidgetTester tester, StudyMode mode,
      List<WordCard> cards) async {
    tester.view.physicalSize = const Size(1080, 2000);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      key: ValueKey(mode),
      home: SessionScreen(deck: deck, mode: mode, cards: cards),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  testWidgets('«Контекст» без примеров объясняет, чего не хватает',
      (tester) async {
    final cards = [
      for (var i = 0; i < 5; i++)
        WordCard(id: 'c$i', deckId: 'd1', front: 'word$i', back: 'слово$i'),
    ];
    for (final c in cards) {
      await DeckRepository.instance.upsertCard(c);
    }

    await pump(tester, StudyMode.cloze, cards);

    expect(find.text('Для этого упражнения нет слов'), findsOneWidget);
    expect(find.textContaining('пример'), findsOneWidget);
    expect(find.text('Пока нечего повторять'), findsNothing);
  });

  testWidgets('обычный режим без срока говорит про срок, а не про материал',
      (tester) async {
    // Карточка уже повторена и срок не подошёл — это честное «нечего повторять».
    final card = WordCard(
      id: 'c1',
      deckId: 'd1',
      front: 'word',
      back: 'слово',
      review: ReviewState(
        stability: 30,
        difficulty: 5,
        state: FsrsState.review,
        reps: 3,
        lastReview: DateTime.now(),
        due: DateTime.now().add(const Duration(days: 10)),
      ),
    );
    await DeckRepository.instance.upsertCard(card);

    await pump(tester, StudyMode.flashcards, [card]);

    expect(find.text('Пока нечего повторять'), findsOneWidget);
    expect(find.text('Для этого упражнения нет слов'), findsNothing);
  });
}
