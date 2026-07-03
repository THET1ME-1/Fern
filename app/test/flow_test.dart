import 'package:flutter_test/flutter_test.dart';

import 'package:fern/l10n/locale_controller.dart';
import 'package:fern/main.dart';
import 'package:fern/services/deck_repository.dart';
import 'package:fern/theme/theme_controller.dart';

import 'test_helpers.dart';

void main() {
  testWidgets('Флоу: колода → Карточки → показать ответ → оценить',
      (WidgetTester tester) async {
    await resetStorage();
    await DeckRepository.instance.init();
    await ThemeController.instance.load();
    await LocaleController.instance.load();
    await LocaleController.instance.setCode('ru');
    await DeckRepository.instance.seedDemoIfNeeded();

    await tester.pumpWidget(const FernApp());
    await tester.pumpAndSettle();

    // Демо-колода на главном экране.
    expect(find.text('Первые слова'), findsOneWidget);
    await tester.tap(find.text('Первые слова'));
    await tester.pumpAndSettle();

    // Экран колоды: режим «Карточки».
    expect(find.text('Карточки'), findsWidgets);
    await tester.tap(find.text('Карточки').first);
    await tester.pumpAndSettle();

    // Сессия: показать ответ и оценить.
    expect(find.text('Показать ответ'), findsOneWidget);
    await tester.tap(find.text('Показать ответ'));
    await tester.pumpAndSettle();

    expect(find.text('Хорошо'), findsOneWidget);
    await tester.tap(find.text('Хорошо'));
    await tester.pumpAndSettle();
    // Дошли без исключений — вертикальный срез работает.
  });
}
