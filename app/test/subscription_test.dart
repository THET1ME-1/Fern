import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:fern/services/fern_account.dart';
import 'package:fern/services/license_service.dart';
import 'package:fern/services/pro.dart';
import 'package:fern/services/subscription_service.dart';

import 'test_helpers.dart';

/// Подписка: срок с сервера, талон на устройстве, Pro без сети.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const testPublicKey = 'nHg+jMxZLIL66qgH0ZzAdRGd4cMA6wtsc3N3jNQXxQA=';
  // Талон до 15 октября 2026, выпущен генератором бота (см. ticket_test).
  const ticket = 'FERNAMAREW2EBMAPUAI7AEGXMYLTPFQUA3LBNFWC44TVZQ2V4PM5XQVWESIG55'
      'PWX5CAKL2PYMT3KZB6CVU2BDZWOXW5KEEH7ROZI44VC4EL56JGGLTXQ3MBVOMJ'
      '7DBYPA7BFSBNNP77JUMXUAA';

  late List<http.Request> requests;
  Map<String, dynamic> me = <String, dynamic>{};
  bool offline = false;

  String fakeJwt() {
    String part(Map<String, dynamic> data) =>
        base64Url.encode(utf8.encode(jsonEncode(data))).replaceAll('=', '');
    final exp =
        DateTime.now().add(const Duration(days: 7)).millisecondsSinceEpoch ~/ 1000;
    return '${part({'alg': 'HS256'})}.${part({'id': 'rec1', 'exp': exp})}.подпись';
  }

  PocketBase fakeServer() {
    final client = MockClient((request) async {
      requests.add(request);
      if (offline) throw http.ClientException('нет сети');
      final path = request.url.path;
      if (path.endsWith('/auth-with-password')) {
        return http.Response(
          jsonEncode({
            'token': fakeJwt(),
            'record': {
              'id': 'rec1',
              'email': 'vasya@mail.ru',
              'collectionId': 'c1',
              'collectionName': 'fern_users',
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (path.endsWith('/api/fern/me')) {
        return http.Response(jsonEncode(me), 200,
            headers: {'content-type': 'application/json'});
      }
      if (path.endsWith('/api/fern/checkout')) {
        return http.Response(
            jsonEncode({'ok': true, 'url': 'https://app.lava.top/pay/1'}), 200,
            headers: {'content-type': 'application/json'});
      }
      if (path.endsWith('/api/fern/cancel')) {
        return http.Response(
            jsonEncode({'ok': true, 'until': '2026-10-08'}), 200,
            headers: {'content-type': 'application/json'});
      }
      return http.Response('{}', 404);
    });
    return PocketBase(FernAccount.baseUrl, httpClientFactory: () => client);
  }

  setUp(() async {
    await resetStorage();
    requests = <http.Request>[];
    offline = false;
    LicenseService.debugPublicKeyBase64 = testPublicKey;
    LicenseService.debugNow = DateTime.utc(2026, 9, 20);
    SubscriptionService.debugNow = DateTime.utc(2026, 9, 20);
    await LicenseService.instance.clear();
    await SubscriptionService.instance.forget();
    FernAccount.debugClient = fakeServer();
    await FernAccount.instance.signIn('vasya@mail.ru', 'пароль123');
    me = {
      'ok': true,
      'until': '2026-10-08',
      'status': 'active',
      'plan': 'month',
      'ticket': ticket,
      'ticket_until': '2026-10-15',
    };
  });

  tearDown(() async {
    LicenseService.debugPublicKeyBase64 = null;
    LicenseService.debugNow = null;
    SubscriptionService.debugNow = null;
    await FernAccount.instance.signOut();
    FernAccount.debugClient = null;
    await SubscriptionService.instance.forget();
  });

  test('подписка с сервера открывает Pro', () async {
    expect(await SubscriptionService.instance.refresh(), isTrue);
    expect(SubscriptionService.instance.status, SubStatus.active);
    expect(SubscriptionService.instance.until, DateTime.utc(2026, 10, 8));
    expect(SubscriptionService.instance.active, isTrue);
    expect(Pro.active, isTrue);
  });

  test('без сети остаётся то, что уже есть', () async {
    await SubscriptionService.instance.refresh();
    offline = true;
    expect(await SubscriptionService.instance.refresh(), isFalse);
    expect(SubscriptionService.instance.status, SubStatus.active);
    expect(Pro.active, isTrue, reason: 'талон работает офлайн');
  });

  test('сервер сказал «подписки нет» — талон убираем', () async {
    await SubscriptionService.instance.refresh();
    expect(Pro.active, isTrue);
    me = {'ok': true, 'until': null, 'status': 'refunded', 'ticket': null};
    expect(await SubscriptionService.instance.refresh(), isTrue);
    expect(SubscriptionService.instance.status, SubStatus.refunded);
    expect(Pro.active, isFalse);
  });

  test('состояние переживает перезапуск', () async {
    await SubscriptionService.instance.refresh();
    await SubscriptionService.instance.load();
    expect(SubscriptionService.instance.status, SubStatus.active);
    expect(SubscriptionService.instance.until, DateTime.utc(2026, 10, 8));
    expect(SubscriptionService.instance.plan, 'month');
  });

  test('сервер не дёргается чаще раза в двадцать часов', () async {
    await SubscriptionService.instance.refresh();
    final before = requests.length;
    await SubscriptionService.instance.refreshIfStale();
    expect(requests.length, before, reason: 'только что спрашивали');
    SubscriptionService.debugNow = DateTime.utc(2026, 9, 21, 12);
    await SubscriptionService.instance.refreshIfStale();
    expect(requests.length, greaterThan(before));
  });

  test('счёт возвращает ссылку на оплату', () async {
    final url = await SubscriptionService.instance.checkoutUrl(plan: 'month');
    expect(url, 'https://app.lava.top/pay/1');
    final body = jsonDecode(requests.last.body) as Map<String, dynamic>;
    expect(body['plan'], 'month');
    expect(body['currency'], 'RUB');
  });

  test('отмена оставляет доступ до конца оплаченного', () async {
    me = {...me, 'status': 'cancelled'};
    expect(await SubscriptionService.instance.cancel(), isTrue);
    expect(SubscriptionService.instance.status, SubStatus.cancelled);
    expect(Pro.active, isTrue);
  });

  test('выход из аккаунта закрывает Pro на этом устройстве', () async {
    await SubscriptionService.instance.refresh();
    await FernAccount.instance.signOut();
    await SubscriptionService.instance.forget();
    expect(Pro.active, isFalse);
    expect(SubscriptionService.instance.status, SubStatus.none);
  });
}
