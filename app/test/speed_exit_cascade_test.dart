import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fern/l10n/locale_controller.dart';
import 'package:fern/models/deck.dart';
import 'package:fern/models/word_card.dart';
import 'package:fern/services/deck_repository.dart';
import 'package:fern/study/session_screen.dart';
import 'package:fern/study/study_models.dart';

import 'test_helpers.dart';

/// Выход из «Быстрого повтора» не должен раздавать «не помню».
///
/// Диалог выхода замораживает отсчёт, но подсветка выбранного варианта
/// отложена на 850 мс. Если нажать крестик сразу после ответа, подсветка
/// добегает уже под диалогом, двигает очередь и заставляет `build`
/// перезапустить отсчёт — дальше каждые восемь секунд очередная невидимая
/// карточка получает настоящий провал FSRS.
final _deck = Deck(
  id: 'd1',
  languageCode: 'en',
  name: 'D',
  colorValue: 0xFF2E7D5B,
  shapeIndex: 0,
  createdAt: 1,
);

void main() {
  final repo = DeckRepository.instance;

  testWidgets('ответ и сразу выход не роняют остальные карточки',
      (WidgetTester tester) async {
    await resetStorage();
    await repo.init();
    await LocaleController.instance.setCode('ru');
    await repo.upsertDeck(_deck);
    final cards = [
      for (var i = 0; i < 6; i++)
        WordCard(id: 'c$i', deckId: 'd1', front: 'w$i', back: 'п$i'),
    ];
    for (final c in cards) {
      await repo.upsertCard(c);
    }

    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
      home: SessionScreen(deck: _deck, mode: StudyMode.speed, cards: cards),
    ));
    // pumpAndSettle тут нельзя: отсчёт «Быстрого повтора» — это анимация,
    // и ожидание её конца прогоняет всю сессию таймаутами.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Отвечаем на первый вопрос — любой из вариантов.
    final option = find.byWidgetPredicate(
        (w) => w is Text && (w.data ?? '').startsWith('п')).first;
    await tester.tap(option, warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 100));

    // И тут же выходим: подсветка ответа ещё в пути.
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pump(const Duration(milliseconds: 900));

    // Человек читает вопрос диалога сорок секунд.
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(seconds: 5));
    }

    // Считаем события, а не провалы: выбранный вариант мог быть и неверным —
    // это законная оценка. Каскад виден по количеству: до починки за эти сорок
    // секунд набегало пять записей по карточкам, которых никто не показывал.
    final events = await repo.reviewEvents();
    expect(events.length, lessThanOrEqualTo(1),
        reason: 'человек ответил один раз и ушёл читать диалог: '
            'больше одной записи взяться неоткуда');
  });
}
