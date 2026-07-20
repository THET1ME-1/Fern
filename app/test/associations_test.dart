import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fern/l10n/locale_controller.dart';
import 'package:fern/models/deck.dart';
import 'package:fern/models/word_card.dart';
import 'package:fern/services/deck_repository.dart';
import 'package:fern/services/word_links.dart';
import 'package:fern/study/session_screen.dart';
import 'package:fern/study/study_models.dart';

import 'test_helpers.dart';

WordCard _c(String id, String front, String back) =>
    WordCard(id: id, deckId: 'd1', front: front, back: back);

Deck _deck() => Deck(
      id: 'd1',
      languageCode: 'en',
      name: 'D',
      colorValue: 0xFF2E7D5B,
      shapeIndex: 0,
      createdAt: 1,
    );

void main() {
  group('Третий лишний (buildOddOne)', () {
    test('собирает пару со связью и чужое слово', () {
      final bright = _c('c1', 'bright', 'яркий');
      final shiny = _c('c2', 'shiny', 'яркий');
      final table = _c('c3', 'table', 'стол');
      final pool = [bright, shiny, table];

      final odd = buildOddOne(bright, pool, 'en');
      expect(odd, isNotNull);
      expect(odd!.options.length, 3);
      expect(odd.odd.front, 'table');
      expect(odd.kind, LinkKind.synonym);
    });

    test('без связей карточка не годится', () {
      final a = _c('c1', 'table', 'стол');
      final pool = [a, _c('c2', 'chair', 'стул'), _c('c3', 'window', 'окно')];
      expect(buildOddOne(a, pool, 'en'), isNull);
    });

    test('без чужого слова упражнение не строится', () {
      final bright = _c('c1', 'bright', 'яркий');
      final shiny = _c('c2', 'shiny', 'яркий');
      expect(buildOddOne(bright, [bright, shiny], 'en'), isNull);
    });

    test('набор не скачет между пересборками', () {
      final bright = _c('c1', 'bright', 'яркий');
      final pool = [
        bright,
        _c('c2', 'shiny', 'яркий'),
        _c('c3', 'table', 'стол'),
        _c('c4', 'window', 'окно'),
      ];
      final first = buildOddOne(bright, pool, 'en')!;
      final second = buildOddOne(bright, pool, 'en')!;
      expect(
        first.options.map((c) => c.id).toList(),
        second.options.map((c) => c.id).toList(),
      );
    });
  });

  test('режим «Связи» не двигает расписание', () {
    expect(StudyMode.associations.affectsSchedule, false);
    expect(StudyMode.flashcards.affectsSchedule, true);
  });

  test('очередь режима собирается только из связанных карт', () {
    final bright = _c('c1', 'bright', 'яркий');
    final shiny = _c('c2', 'shiny', 'яркий');
    final table = _c('c3', 'table', 'стол');
    final queue = SessionBuilder().build(
      StudyMode.associations,
      [bright, shiny, table],
      DateTime.now(),
      language: 'en',
    );

    expect(queue, isNotEmpty);
    expect(queue.every((e) => e.kind == ExerciseKind.oddOne), true);
    expect(
      queue.map((e) => e.card.id).toSet().contains('c3'),
      false,
      reason: 'у «table» связей нет — в очередь она не попадает',
    );
  });

  testWidgets('верный выбор ведёт дальше и объясняет связь', (tester) async {
    await resetStorage();
    await DeckRepository.instance.init();
    await LocaleController.instance.setCode('ru');

    final bright = _c('c1', 'bright', 'яркий');
    final shiny = _c('c2', 'shiny', 'яркий');
    final table = _c('c3', 'table', 'стол');
    final deck = _deck();
    await DeckRepository.instance.upsertDeck(deck);
    for (final c in [bright, shiny, table]) {
      await DeckRepository.instance.upsertCard(c);
    }

    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
      home: SessionScreen(
        deck: deck,
        mode: StudyMode.associations,
        cards: [bright, shiny, table],
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Какое здесь лишнее?'), findsOneWidget);

    // Лишнее здесь — «table»: со «связанными» его ничего не роднит.
    await tester.tap(find.text('table'));
    await tester.pump();
    expect(find.text('СВЯЗЬ'), findsOneWidget);

    await tester.pumpAndSettle(const Duration(seconds: 2));
    // Расписание не тронуто — это проверка смысла, а не перевода.
    final stored = (await DeckRepository.instance.cardsForDeck('d1'))
        .firstWhere((c) => c.id == 'c1');
    expect(stored.review.reps, 0);
  });
}
