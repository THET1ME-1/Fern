import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fern/l10n/locale_controller.dart';
import 'package:fern/models/fsrs.dart';
import 'package:fern/services/deck_repository.dart';
import 'package:fern/settings_screen.dart';

import 'test_helpers.dart';

/// Строка «Оптимизация FSRS» на узком экране. Пока персональных весов нет,
/// в строке одна кнопка и места хватает; после оптимизации рядом встаёт
/// «Сбросить», и раскладка обязана выдержать обе — иначе гибкая колонка
/// текста получает нулевую ширину и заголовок сыплется столбиком по букве.
void main() {
  setUp(() async {
    await resetStorage();
    await DeckRepository.instance.init();
    await LocaleController.instance.setCode('ru');
  });

  testWidgets('заголовок оптимизации не схлопывается рядом со «Сбросить»',
      (WidgetTester tester) async {
    // Персональные веса = на строке появляется вторая кнопка.
    await DeckRepository.instance.setFsrsWeights(
      List<double>.of(Fsrs.defaultWeights),
    );
    addTearDown(() => DeckRepository.instance.setFsrsWeights(null));

    // Ширина обычного телефона: именно на ней две кнопки съедали строку.
    tester.view.physicalSize = const Size(360, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // Экран читает журнал из SQLite: файловый ввод-вывод только в runAsync.
    await tester.runAsync(() async {
      await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();

    expect(find.text('Сбросить'), findsWidgets);
    final title = find.text('Оптимизация FSRS');
    expect(title, findsOneWidget);

    final size = tester.getSize(title);
    expect(size.width, greaterThan(120),
        reason: 'колонка текста осталась без ширины — заголовок переносится '
            'по одной букве');
    expect(size.height, lessThan(60),
        reason: 'заголовок вытянулся в столбик');

    final subtitle =
        tester.getSize(find.text('Используются ваши персональные веса'));
    expect(subtitle.width, greaterThan(120),
        reason: 'подпись под заголовком схлопнулась вместе с ним');
  });
}
