import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fern/l10n/locale_controller.dart';
import 'package:fern/l10n/strings.dart';
import 'package:fern/models/deck.dart';
import 'package:fern/models/word_card.dart';
import 'package:fern/services/deck_repository.dart';
import 'package:fern/study/session_screen.dart';
import 'package:fern/study/study_models.dart';

import 'test_helpers.dart';

/// Жалоба, с которой это начиналось: колода показывала «118 к повтору», а
/// сессия отвечала «нечего повторять». Совпадение цифры с тем, что человек
/// реально получит, и проверяем.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final repo = DeckRepository.instance;
  final now = DateTime(2026, 8, 10, 12);

  setUp(resetStorage);

  WordCard fresh(String id) =>
      WordCard(id: id, deckId: 'd', front: 'f$id', back: 'b$id');

  WordCard due(String id) {
    final c = WordCard(id: id, deckId: 'd', front: 'f$id', back: 'b$id');
    c.review.state = FsrsState.review;
    c.review.due = DateTime(2000);
    c.review.stability = 30;
    return c;
  }

  group('остаток дневного лимита', () {
    test('по умолчанию 12, введённое сегодня вычитается', () async {
      expect(await repo.newAllowedNow(now), 12);
      await repo.markNewIntroduced(12, now);
      expect(await repo.newAllowedNow(now), 0);
    });

    test('добавка «взять ещё» действует сегодня и не действует завтра',
        () async {
      await repo.markNewIntroduced(12, now);
      await repo.addExtraNewToday(12, now);
      expect(await repo.newAllowedNow(now), 12);

      final tomorrow = now.add(const Duration(days: 1));
      expect(await repo.extraNewToday(tomorrow), 0);
    });

    test('лимит 0 означает «без лимита»', () async {
      await repo.setNewPerDay(0);
      expect(await repo.newAllowedNow(now), DeckRepository.noNewLimit);
    });

    test('счётчик введённых обнуляется на следующий день', () async {
      await repo.markNewIntroduced(12, now);
      expect(await repo.newAllowedNow(now.add(const Duration(days: 1))), 12);
    });
  });

  group('очередь сессии', () {
    test('118 новых при исчерпанном лимите дают пустую сессию', () {
      final cards = [for (var i = 0; i < 118; i++) fresh('n$i')];
      final q = SessionBuilder()
          .build(StudyMode.learn, cards, now, newAllowed: 0, maxReviews: 100);
      expect(q, isEmpty);
    });

    test('118 просроченных повторов лимит новых не трогает', () {
      final cards = [for (var i = 0; i < 118; i++) due('r$i')];
      final q = SessionBuilder()
          .build(StudyMode.learn, cards, now, newAllowed: 0, maxReviews: 100);
      expect(q.length, 100); // потолок повторов, остальное — следующей сессией
    });

    test('добавка на сегодня возвращает новые слова в очередь', () async {
      await repo.markNewIntroduced(12, now);
      await repo.addExtraNewToday(12, now);
      final cards = [for (var i = 0; i < 118; i++) fresh('n$i')];
      final q = SessionBuilder().build(StudyMode.learn, cards, now,
          newAllowed: await repo.newAllowedNow(now), maxReviews: 100);
      expect(q.length, 12);
    });
  });

  testWidgets('пустая сессия называет лимит и отдаёт слова по кнопке',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2280);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await LocaleController.instance.setCode('ru');

    final deck = Deck(
      id: 'd',
      languageCode: 'en',
      name: 'D',
      colorValue: 0xFF2E7D5B,
      shapeIndex: 0,
      createdAt: 1,
    );
    final cards = [for (var i = 0; i < 118; i++) fresh('n$i')];
    await repo.upsertDeck(deck);
    for (final c in cards) {
      await repo.upsertCard(c);
    }
    await repo.markNewIntroduced(12);

    await tester.pumpWidget(MaterialApp(
      home: SessionScreen(deck: deck, mode: StudyMode.learn, cards: cards),
    ));
    await tester.pumpAndSettle();

    // Про исчерпанный лимит говорим прямо, а не «нечего повторять».
    expect(find.text(tr('new_limit_title')), findsOneWidget);
    expect(find.text(tr('nothing_due_title')), findsNothing);

    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pumpAndSettle();

    // Кнопка вернула дневную порцию: экран лимита сменился упражнением.
    expect(find.text(tr('new_limit_title')), findsNothing);
    expect(await repo.newAllowedNow(), 12);
  });
}
