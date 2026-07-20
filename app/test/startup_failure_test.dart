import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fern/recovery_screen.dart';
import 'package:fern/startup.dart';

/// Аварийный экран обязан говорить правду о том, что случилось.
///
/// Раньше `main()` ловил ЛЮБОЕ исключение из двух десятков шагов запуска —
/// тему, локали, лицензию, биллинг, посев колод, напоминания — и на всё это
/// отвечал «Хранилище словаря повреждено», предлагая две кнопки, каждая из
/// которых уводит живую базу в карантин. Сбой в загрузке шрифта стоил человеку
/// словаря.
void main() {
  /// Экран живёт до загрузки локалей и берёт язык из системного.
  void speakRussian(WidgetTester tester) {
    tester.platformDispatcher.localeTestValue = const Locale('ru');
    addTearDown(tester.platformDispatcher.clearLocaleTestValue);
  }

  testWidgets('отказ хранилища: предлагаем копию и карантин',
      (WidgetTester tester) async {
    speakRussian(tester);
    await tester.pumpWidget(RecoveryApp(
      failure: StartupError(
        StartupStep.storage,
        'SqliteException(11): database disk image is malformed',
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('Хранилище словаря'), findsOneWidget);
    expect(find.textContaining('Восстановить из копии'), findsOneWidget);
    expect(find.textContaining('Начать заново'), findsOneWidget);
  });

  testWidgets('прочий сбой: карантин не предлагаем и называем причину',
      (WidgetTester tester) async {
    speakRussian(tester);
    await tester.pumpWidget(RecoveryApp(
      failure: StartupError(
        StartupStep.theme,
        'MissingPluginException(No implementation found)',
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('Начать заново'), findsNothing,
        reason: 'словарь тут ни при чём — стирать его не за что');
    expect(find.textContaining('Восстановить из копии'), findsNothing);
    expect(find.textContaining('оформление'), findsOneWidget,
        reason: 'человек должен видеть, что именно не поднялось');
    expect(find.textContaining('MissingPluginException'), findsOneWidget,
        reason: 'техническая причина — это то, что можно переслать в issue');
    expect(find.text('Повторить'), findsOneWidget);
  });

  test('шаг запуска знает своё человеческое имя', () {
    expect(StartupStep.storage.title(ru: true), 'хранилище словаря');
    expect(StartupStep.storage.title(ru: false), 'word storage');
    for (final step in StartupStep.values) {
      expect(step.title(ru: true), isNotEmpty);
      expect(step.title(ru: false), isNotEmpty);
    }
  });
}
