import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fern/l10n/locale_controller.dart';
import 'package:fern/models/deck.dart';
import 'package:fern/models/word_card.dart';
import 'package:fern/services/deck_repository.dart';
import 'package:fern/study/session_screen.dart';
import 'package:fern/study/study_models.dart';
import 'package:fern/widgets/hook_editor_sheet.dart';

import 'test_helpers.dart';

Deck _deck() => Deck(
      id: 'd1',
      languageCode: 'en',
      name: 'D',
      colorValue: 0xFF2E7D5B,
      shapeIndex: 0,
      createdAt: 1,
    );

WordCard _card({String mnemonic = ''}) => WordCard(
      id: 'c1',
      deckId: 'd1',
      front: 'pillow',
      back: 'подушка',
      mnemonic: mnemonic,
    );

void _bigScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  final repo = DeckRepository.instance;

  testWidgets('лист крючка сохраняет мнемонику в карточку', (tester) async {
    await resetStorage();
    await repo.init();
    await LocaleController.instance.setCode('ru');
    final deck = _deck();
    final card = _card();
    await repo.upsertDeck(deck);
    await repo.upsertCard(card);
    _bigScreen(tester);

    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (c) {
        ctx = c;
        return const Scaffold(body: SizedBox());
      }),
    ));

    final future = showHookEditor(ctx, card);
    await tester.pumpAndSettle();

    expect(find.text('pillow'), findsOneWidget);
    await tester.enterText(
        find.byType(TextField).first, 'Под подушкой спрятана пила');
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();

    expect(await future, true);
    final stored = (await repo.cardsForDeck('d1')).single;
    expect(stored.mnemonic, 'Под подушкой спрятана пила');
  });

  group('Крючок в модели', () {
    test('переживает сериализацию', () {
      final card = _card(mnemonic: 'Под подушкой спрятана пила');
      final back = WordCard.fromJson(card.toJson());
      expect(back.mnemonic, 'Под подушкой спрятана пила');
    });

    test('пустой крючок не раздувает JSON', () {
      expect(_card().toJson().containsKey('mn'), false);
    });
  });

  testWidgets('кнопка «Крючок» открывает подсказку', (tester) async {
    await resetStorage();
    await repo.init();
    await LocaleController.instance.setCode('ru');
    final deck = _deck();
    final card = _card(mnemonic: 'Под подушкой спрятана пила');
    await repo.upsertDeck(deck);
    await repo.upsertCard(card);
    _bigScreen(tester);

    await tester.pumpWidget(MaterialApp(
      home: SessionScreen(deck: deck, mode: StudyMode.flashcards, cards: [card]),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Под подушкой спрятана пила'), findsNothing,
        reason: 'до нажатия подсказка скрыта');

    await tester.tap(find.text('Крючок'));
    await tester.pumpAndSettle();

    expect(find.text('ВСПОМНИ'), findsOneWidget);
    expect(find.text('Под подушкой спрятана пила'), findsOneWidget);
    expect(find.text('ответ с подсказкой'), findsOneWidget,
        reason: 'пользователь должен видеть, что оценка идёт со скидкой');
  });

  testWidgets('срыв на карте с крючком сперва показывает крючок',
      (tester) async {
    await resetStorage();
    await repo.init();
    await LocaleController.instance.setCode('ru');
    final deck = _deck();
    final card = _card(mnemonic: 'Под подушкой спрятана пила');
    await repo.upsertDeck(deck);
    await repo.upsertCard(card);
    _bigScreen(tester);

    await tester.pumpWidget(MaterialApp(
      home: SessionScreen(deck: deck, mode: StudyMode.flashcards, cards: [card]),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Показать ответ'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Не помню'));
    await tester.pumpAndSettle();

    // Карта осталась на экране: сперва крючок, оценка — следующим тапом.
    expect(find.text('Под подушкой спрятана пила'), findsOneWidget);
    expect(find.text('Дальше'), findsOneWidget);
    expect(find.text('Показать ответ'), findsNothing);

    await tester.tap(find.text('Дальше'));
    await tester.pumpAndSettle();

    expect(find.text('Показать ответ'), findsOneWidget,
        reason: 'после срыва карта переспрашивается в этой же сессии');
  });

  testWidgets('ответ с подсказкой даёт интервал короче, чем без неё',
      (tester) async {
    Future<DateTime?> run({required bool useHook}) async {
      await resetStorage();
      await repo.init();
      await LocaleController.instance.setCode('ru');
      final deck = _deck();
      final card = _card(mnemonic: 'Под подушкой спрятана пила');
      await repo.upsertDeck(deck);
      await repo.upsertCard(card);
      _bigScreen(tester);

      // Свой ключ на каждый прогон: иначе второй pumpWidget переиспользует
      // Navigator первого и мы остаёмся на экране результатов.
      await tester.pumpWidget(MaterialApp(
        key: ValueKey(useHook),
        home:
            SessionScreen(deck: deck, mode: StudyMode.flashcards, cards: [card]),
      ));
      await tester.pumpAndSettle();

      if (useHook) {
        await tester.tap(find.text('Крючок'));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('Показать ответ'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Легко'));
      await tester.pumpAndSettle();

      return (await repo.cardsForDeck('d1')).single.review.due;
    }

    final plain = await run(useHook: false);
    final hinted = await run(useHook: true);

    expect(plain, isNotNull);
    expect(hinted, isNotNull);
    expect(hinted!.isBefore(plain!), true,
        reason: '«Легко» с подсказкой должно опуститься до «Хорошо»');
  });
}
