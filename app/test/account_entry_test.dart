import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:fern/l10n/locale_controller.dart';
import 'package:fern/services/deck_repository.dart';
import 'package:fern/services/fern_account.dart';
import 'package:fern/services/subscription_service.dart';
import 'package:fern/settings_screen.dart';
import 'package:fern/widgets/account_sheet.dart';

import 'test_helpers.dart';

/// Вход и регистрация не зависят от оплаты: строка «Войти» живёт в
/// настройках, а вошедший может удалить аккаунт сам (App Store 5.1.1(v)).
void main() {
  late List<http.Request> requests;
  // Что сервер ответит на удаление: код и тело.
  int deleteCode = 200;
  Map<String, dynamic> deleteBody = {'ok': true};

  String fakeJwt() {
    String part(Map<String, dynamic> data) =>
        base64Url.encode(utf8.encode(jsonEncode(data))).replaceAll('=', '');
    final exp = DateTime.now()
            .add(const Duration(days: 7))
            .millisecondsSinceEpoch ~/
        1000;
    return '${part({'alg': 'HS256'})}.${part({'id': 'rec1', 'exp': exp})}.подпись';
  }

  PocketBase fakeServer() {
    final client = MockClient((request) async {
      requests.add(request);
      final path = request.url.path;
      if (path.endsWith('/auth-with-password')) {
        return http.Response(
          jsonEncode({
            'token': fakeJwt(),
            'record': {
              'id': 'rec1',
              'email': 'kira@mail.ru',
              'collectionId': 'c1',
              'collectionName': 'fern_users',
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (path.endsWith('/api/fern/me')) {
        return http.Response(
          jsonEncode({'ok': true, 'until': null, 'status': 'none'}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (path.endsWith('/api/fern/account/delete')) {
        return http.Response(jsonEncode(deleteBody), deleteCode,
            headers: {'content-type': 'application/json'});
      }
      return http.Response('{}', 404);
    });
    return PocketBase(FernAccount.baseUrl, httpClientFactory: () => client);
  }

  setUp(() async {
    await resetStorage();
    await DeckRepository.instance.init();
    await LocaleController.instance.setCode('ru');
    requests = <http.Request>[];
    deleteCode = 200;
    deleteBody = {'ok': true};
    FernAccount.debugClient = fakeServer();
  });

  tearDown(() async {
    await FernAccount.instance.signOut();
    FernAccount.debugClient = null;
    await SubscriptionService.instance.forget();
  });

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 4200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
    await tester.pumpAndSettle();
  }

  testWidgets('без аккаунта в настройках есть вход, и он открывает окно входа',
      (tester) async {
    await open(tester);

    expect(find.text('Аккаунт'), findsOneWidget);
    expect(find.text('Войти или создать аккаунт'), findsOneWidget);

    await tester.tap(find.text('Войти или создать аккаунт'));
    await tester.pumpAndSettle();
    expect(find.byType(AccountSheet), findsOneWidget);
  });

  testWidgets('вошедший видит почту, выход и удаление', (tester) async {
    await FernAccount.instance.signIn('kira@mail.ru', 'пароль123');
    await open(tester);

    expect(find.text('Войти или создать аккаунт'), findsNothing);
    expect(find.text('kira@mail.ru'), findsWidgets);
    expect(find.text('Выйти из аккаунта'), findsOneWidget);
    expect(find.text('Удалить аккаунт'), findsOneWidget);
  });

  testWidgets('удаление спрашивает подтверждение и выводит из аккаунта',
      (tester) async {
    await FernAccount.instance.signIn('kira@mail.ru', 'пароль123');
    await open(tester);

    await tester.tap(find.text('Удалить аккаунт'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Удалить'));
    await tester.pumpAndSettle();

    final deleteCall = requests
        .where((r) => r.url.path.endsWith('/api/fern/account/delete'))
        .toList();
    expect(deleteCall, hasLength(1));
    expect(deleteCall.single.method, 'POST');
    expect(deleteCall.single.headers['Authorization'], isNotEmpty);
    expect(FernAccount.instance.signedIn, isFalse);
    expect(find.text('Войти или создать аккаунт'), findsOneWidget);
  });

  test('сервер отказал из-за живой подписки — аккаунт на месте', () async {
    await FernAccount.instance.signIn('kira@mail.ru', 'пароль123');
    deleteCode = 409;
    deleteBody = {'ok': false, 'error': 'active_subscription'};

    final outcome = await FernAccount.instance.deleteAccount();

    expect(outcome, AccountDeleteOutcome.activeSubscription);
    expect(FernAccount.instance.signedIn, isTrue);
  });

  test('без сети удаление не выдаёт себя за удачу', () async {
    await FernAccount.instance.signIn('kira@mail.ru', 'пароль123');
    deleteCode = 500;
    deleteBody = {'ok': false};

    final outcome = await FernAccount.instance.deleteAccount();

    expect(outcome, AccountDeleteOutcome.failed);
    expect(FernAccount.instance.signedIn, isTrue);
  });
}
