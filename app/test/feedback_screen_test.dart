import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fern/feedback_screen.dart';
import 'package:fern/l10n/locale_controller.dart';
import 'package:fern/models/feedback.dart';
import 'package:fern/services/deck_repository.dart';
import 'package:fern/settings_screen.dart';

import 'test_helpers.dart';

/// «Сообщить о проблеме»: обращение уходит на наш сервер прямо из
/// приложения. Google Play требует этого без выхода в почту или браузер.
void main() {
  setUp(() async {
    await resetStorage();
    await DeckRepository.instance.init();
    await LocaleController.instance.setCode('ru');
  });

  Future<void> pump(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: screen));
    await tester.pumpAndSettle();
  }

  testWidgets('короткий текст не отправляется и объясняет почему',
      (tester) async {
    var calls = 0;
    await pump(
      tester,
      FeedbackScreen(
        version: '1.27.0',
        send: (_) async {
          calls++;
          return FeedbackSent.ok;
        },
      ),
    );

    await tester.enterText(find.byKey(const Key('feedback_text')), 'плохо');
    await tester.tap(find.byKey(const Key('feedback_send')));
    await tester.pumpAndSettle();

    expect(calls, 0);
    expect(find.text('Напишите хотя бы пару слов'), findsOneWidget);
  });

  testWidgets('вид, текст и почта уходят на сервер, после — спасибо',
      (tester) async {
    FeedbackDraft? sent;
    await pump(
      tester,
      FeedbackScreen(
        version: '1.27.0',
        send: (draft) async {
          sent = draft;
          return FeedbackSent.ok;
        },
      ),
    );

    await tester.tap(find.byKey(const Key('feedback_kind_idea')));
    await tester.enterText(
        find.byKey(const Key('feedback_text')), 'Хочу тёмную тему поярче');
    await tester.enterText(
        find.byKey(const Key('feedback_email')), 'kira@mail.ru');
    await tester.tap(find.byKey(const Key('feedback_send')));
    await tester.pumpAndSettle();

    expect(sent?.kind, FeedbackKind.idea);
    expect(sent?.text, 'Хочу тёмную тему поярче');
    expect(sent?.email, 'kira@mail.ru');
    expect(sent?.app, '1.27.0');
    expect(find.text('Сообщение получено'), findsOneWidget);
    expect(find.text('Спасибо. Ответим на почту kira@mail.ru'), findsOneWidget);
  });

  testWidgets('почта аккаунта подставлена, поле почты не нужно',
      (tester) async {
    await pump(
      tester,
      FeedbackScreen(
        version: '1.27.0',
        accountEmail: 'kira@mail.ru',
        send: (_) async => FeedbackSent.ok,
      ),
    );

    expect(find.byKey(const Key('feedback_email')), findsNothing);
    expect(find.text('Ответим на почту kira@mail.ru'), findsOneWidget);
  });

  testWidgets('отказ сервера оставляет текст в поле', (tester) async {
    await pump(
      tester,
      FeedbackScreen(
        version: '1.27.0',
        send: (_) async => FeedbackSent.tooMany,
      ),
    );

    await tester.enterText(
        find.byKey(const Key('feedback_text')), 'Колода не открывается');
    await tester.tap(find.byKey(const Key('feedback_send')));
    await tester.pumpAndSettle();

    expect(find.textContaining('уже пришло несколько сообщений'),
        findsOneWidget);
    expect(find.text('Колода не открывается'), findsOneWidget);
  });

  testWidgets('строка в первом разделе настроек открывает форму',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 4200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
    await tester.pumpAndSettle();

    final row = tester.getTopLeft(find.text('Сообщить о проблеме')).dy;
    final appearance = tester.getTopLeft(find.text('Внешний вид')).dy;
    expect(row, lessThan(appearance));

    await tester.tap(find.text('Сообщить о проблеме'));
    await tester.pumpAndSettle();
    expect(find.byType(FeedbackScreen), findsOneWidget);
  });
}
