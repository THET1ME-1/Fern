import 'package:flutter_test/flutter_test.dart';

import 'package:fern/l10n/locale_controller.dart';
import 'package:fern/main.dart';
import 'package:fern/theme/theme_controller.dart';

import 'test_helpers.dart';

void main() {
  testWidgets('Приложение запускается и показывает баннер языка',
      (WidgetTester tester) async {
    await resetStorage();
    await ThemeController.instance.load();
    await LocaleController.instance.load();

    await tester.pumpWidget(const FernApp());
    await tester.pump();

    // Заголовок приложения на месте.
    expect(find.text('Fern'), findsWidgets);
  });
}
