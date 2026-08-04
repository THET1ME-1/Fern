import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fern/l10n/locale_controller.dart';
import 'package:fern/models/word_card.dart';
import 'package:fern/services/deck_repository.dart';
import 'package:fern/settings_screen.dart';

import 'test_helpers.dart';

/// Журнал из одних внутридневных шагов: 129 слов, у каждого знакомство и два
/// шага внутри того же дня. Ровно та история, с которой пришёл человек —
/// 387 событий и ни одного повтора через сутки.
Future<void> _sameDayHistory(DeckRepository repo) async {
  final at = DateTime(2026, 8, 4, 10);
  for (var i = 0; i < 129; i++) {
    final card = WordCard(id: 'c$i', deckId: 'd1', front: 'w$i', back: 'с$i');
    await repo.upsertCard(card);
    // Один и тот же момент — значит все события внутридневные.
    for (var k = 0; k < 3; k++) {
      await repo.rateCard(card, Rating.good, at);
    }
  }
}

void main() {
  setUp(() async {
    await resetStorage();
    await DeckRepository.instance.init();
    await LocaleController.instance.setCode('ru');
  });

  testWidgets('полный счётчик повторов не включает кнопку оптимизации',
      (WidgetTester tester) async {
    final repo = DeckRepository.instance;
    await tester.runAsync(() => _sameDayHistory(repo));
    expect(await repo.reviewEventCount(), 387);

    tester.view.physicalSize = const Size(1200, 3600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    // Экран читает журнал из SQLite, а файловый ввод-вывод внутри testWidgets
    // идёт только через runAsync.
    await tester.runAsync(() async {
      await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();

    // Подпись называет то, чего не хватает, а не общее число событий.
    expect(find.text('Слов, повторённых через сутки: 0 / 20'), findsOneWidget);
    expect(find.text('Повторов накоплено: 387 / 200'), findsNothing,
        reason: 'полный счётчик рядом с отказом «мало данных» — та самая '
            'жалоба, из-за которой кнопка выглядела сломанной');

    // И кнопка не предлагает нажать себя впустую.
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Оптимизировать'),
    );
    expect(button.onPressed, isNull);
  });
}
