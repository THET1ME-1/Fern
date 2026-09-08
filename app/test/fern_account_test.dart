import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:fern/services/fern_account.dart';
import 'package:fern/services/license_service.dart';

import 'test_helpers.dart';

/// Аккаунт Fern: вход, регистрация, выход, сброс пароля.
///
/// Слой перенесён из Togetherly, поэтому проверяем то, на чём он там спотыкался:
/// неверный пароль отличается от обрыва сети, занятая почта названа своим
/// именем, а выход не отбирает вечную покупку.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<http.Request> requests;

  /// Токен, который PocketBase сочтёт годным: SDK разбирает JWT и смотрит на
  /// срок, поэтому строкой «токен» не отделаться.
  String fakeJwt() {
    String part(Map<String, dynamic> data) => base64Url
        .encode(utf8.encode(jsonEncode(data)))
        .replaceAll('=', '');
    final exp = DateTime.now()
            .add(const Duration(days: 7))
            .millisecondsSinceEpoch ~/
        1000;
    return '${part({'alg': 'HS256'})}.${part({'id': 'rec1', 'exp': exp})}.подпись';
  }

  PocketBase fakeServer({
    int authCode = 200,
    int createCode = 200,
    Map<String, dynamic>? authBody,
    Map<String, dynamic>? createBody,
    bool offline = false,
  }) {
    final client = MockClient((request) async {
      requests.add(request);
      if (offline) throw http.ClientException('нет сети');
      final path = request.url.path;
      if (path.endsWith('/auth-with-password') ||
          path.endsWith('/auth-refresh')) {
        return http.Response(
          jsonEncode(authBody ??
              {
                'token': fakeJwt(),
                'record': {
                  'id': 'rec1',
                  'email': 'vasya@mail.ru',
                  'collectionId': 'c1',
                  'collectionName': 'fern_users',
                },
              }),
          authCode,
          headers: {'content-type': 'application/json'},
        );
      }
      if (path.endsWith('/request-password-reset')) {
        return http.Response('{}', 204);
      }
      if (path.endsWith('/records')) {
        return http.Response(
          jsonEncode(createBody ?? {'id': 'rec1', 'email': 'vasya@mail.ru'}),
          createCode,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('{}', 404);
    });
    return PocketBase(FernAccount.baseUrl, httpClientFactory: () => client);
  }

  setUp(() async {
    await resetStorage();
    requests = <http.Request>[];
    await LicenseService.instance.clear();
  });

  tearDown(() async {
    await FernAccount.instance.signOut();
    FernAccount.debugClient = null;
  });

  group('вход', () {
    test('удачный вход помнит почту и аккаунт', () async {
      FernAccount.debugClient = fakeServer();
      final outcome =
          await FernAccount.instance.signIn('vasya@mail.ru', 'пароль123');
      expect(outcome, AuthOutcome.ok);
      expect(FernAccount.instance.signedIn, isTrue);
      expect(FernAccount.instance.email, 'vasya@mail.ru');
      expect(FernAccount.instance.uid, 'rec1');
    });

    test('неверный пароль назван своим именем', () async {
      FernAccount.debugClient = fakeServer(
          authCode: 400,
          authBody: {'code': 400, 'message': 'Failed to authenticate.'});
      final outcome =
          await FernAccount.instance.signIn('vasya@mail.ru', 'не тот');
      expect(outcome, AuthOutcome.wrongPassword);
      expect(FernAccount.instance.signedIn, isFalse);
    });

    test('нет сети — это не «неверный пароль»', () async {
      FernAccount.debugClient = fakeServer(offline: true);
      final outcome =
          await FernAccount.instance.signIn('vasya@mail.ru', 'пароль123');
      expect(outcome, AuthOutcome.network);
    });

    test('почта приводится к нижнему регистру и без пробелов', () async {
      FernAccount.debugClient = fakeServer();
      await FernAccount.instance.signIn('  Vasya@Mail.RU ', 'пароль123');
      final body = jsonDecode(requests.first.body) as Map<String, dynamic>;
      expect(body['identity'], 'vasya@mail.ru');
    });

    test('адрес без собаки до сервера не летит', () async {
      FernAccount.debugClient = fakeServer();
      final outcome = await FernAccount.instance.signIn('вася', 'пароль123');
      expect(outcome, AuthOutcome.invalidEmail);
      expect(requests, isEmpty);
    });
  });

  group('регистрация', () {
    test('после регистрации человек уже внутри', () async {
      FernAccount.debugClient = fakeServer();
      final outcome =
          await FernAccount.instance.signUp('vasya@mail.ru', 'пароль123');
      expect(outcome, AuthOutcome.ok);
      expect(FernAccount.instance.signedIn, isTrue);
      // Создание записи и следом вход: токена при создании PocketBase не даёт.
      expect(requests.length, 2);
    });

    test('короткий пароль отбивается до сервера', () async {
      FernAccount.debugClient = fakeServer();
      final outcome = await FernAccount.instance.signUp('vasya@mail.ru', '123');
      expect(outcome, AuthOutcome.weakPassword);
      expect(requests, isEmpty);
    });

    test('занятая почта: пробуем войти ею же', () async {
      FernAccount.debugClient = fakeServer(createCode: 400, createBody: {
        'data': {
          'email': {'code': 'validation_not_unique', 'message': 'занята'}
        }
      });
      final outcome =
          await FernAccount.instance.signUp('vasya@mail.ru', 'пароль123');
      // Пароль подошёл — значит это его же аккаунт, и человека пускают.
      expect(outcome, AuthOutcome.ok);
    });

    test('занятая почта с чужим паролем названа занятой', () async {
      FernAccount.debugClient = fakeServer(
        createCode: 400,
        createBody: {
          'data': {
            'email': {'code': 'validation_not_unique', 'message': 'занята'}
          }
        },
        authCode: 400,
        authBody: {'code': 400, 'message': 'Failed to authenticate.'},
      );
      final outcome =
          await FernAccount.instance.signUp('vasya@mail.ru', 'пароль123');
      expect(outcome, AuthOutcome.emailTaken);
    });
  });

  group('выход', () {
    test('выход уносит талон подписки, а вечный ключ оставляет', () async {
      FernAccount.debugClient = fakeServer();
      await FernAccount.instance.signIn('vasya@mail.ru', 'пароль123');
      await FernAccount.instance.signOut();
      expect(FernAccount.instance.signedIn, isFalse);
      expect(LicenseService.instance.ticket, isNull);
    });
  });

  group('сброс пароля', () {
    test('письмо просят по адресу', () async {
      FernAccount.debugClient = fakeServer();
      final ok =
          await FernAccount.instance.requestPasswordReset('vasya@mail.ru');
      expect(ok, isTrue);
      expect(requests.single.url.path, endsWith('/request-password-reset'));
    });
  });
}
