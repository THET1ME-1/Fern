import 'package:flutter_test/flutter_test.dart';
import 'package:fern/services/license_service.dart';

import 'test_helpers.dart';

/// Талон подписки (формат 3): внутри почта И срок.
///
/// Талон выдаёт сервер после оплаты и переподписывает при каждом обращении.
/// Приложение проверяет его офлайн, как обычный ключ, поэтому подписка не
/// гаснет в самолёте.
///
/// Образцы ниже выпущены генератором бота (`bot/license.py`) на отдельной
/// тестовой паре: тест заодно стережёт, что Python и Dart понимают формат
/// одинаково.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const testPublicKey = 'nHg+jMxZLIL66qgH0ZzAdRGd4cMA6wtsc3N3jNQXxQA=';

  // Месячный талон на vasya@mail.ru, выдан 8 сентября, годен до 15 октября.
  const monthly = 'FERNAMAREW2EBMAPUAI7AEGXMYLTPFQUA3LBNFWC44TVZQ2V4PM5XQVWESIG55'
      'PWX5CAKL2PYMT3KZB6CVU2BDZWOXW5KEEH7ROZI44VC4EL56JGGLTXQ3MBVOMJ'
      '7DBYPA7BFSBNNP77JUMXUAA';
  // Годовой: тот же аккаунт, срок до 15 сентября 2027.
  const yearly = 'FERNAMAREW2EBMAPUATOAIGXMYLTPFQUA3LBNFWC44TV5VD4WNXWAOC6G5AQKH'
      'XK3NU2VYEF43YL4ZZTUPALG3Y2A2UOSSLH6YSQ623567KZFQGOP34K7FIMBXMG'
      '2UAVEG6WDAVJGDMEJMLREAY';
  // Талон, срок которого кончился 1 августа.
  const expired = 'FERNAMAREW2EBMALKAGUAEGXMYLTPFQUA3LBNFWC44TVURSX23YHCO2JKSVRXZ'
      'ES46BT6I4BASHU5W3DQWXOAEKEKTGJWDGIFVPFXHFKIUEFGF7CCSAZ4NIB7ALB'
      'BBIZ333YRUSW2WAGFTMUYDI';
  // Тот же талон, но подписанный чужой парой.
  const forged = 'FERNAMAREW2EBMAPUAI7AEGXMYLTPFQUA3LBNFWC44TV54745K2ME7P7SST27Y'
      'AJXVADFRWX2LJVPCY7YICUNYJIBPSUESCILGV3T3S7UMU4DH2B537OVOSJMIJM'
      '5HGRFFVFXLOW7LUGK2JNEBQ';
  // Ключ навсегда (формат 2) той же парой: он обязан работать как прежде.
  const lifetime = 'FERNAIAQAAAAFIAPUDLWMFZXSYKANVQWS3BOOJ2QAH3ODUB42AOSUYVL5E363M'
      'KNWATPRTFGVNGLUAC2KH5WTTSYMKZKCQODHEQQSBH7MIIIUQWME67GOL5J62XJ'
      'L7DHAA2S7TSDXDZQBE';

  setUp(() async {
    await resetStorage();
    LicenseService.debugPublicKeyBase64 = testPublicKey;
    LicenseService.debugNow = DateTime.utc(2026, 9, 20);
    LicenseService.revoked = <int>{};
    await LicenseService.instance.clear();
  });

  tearDown(() async {
    LicenseService.debugPublicKeyBase64 = null;
    LicenseService.debugNow = null;
    LicenseService.revoked = <int>{};
    await LicenseService.instance.clear();
  });

  group('разбор', () {
    test('срок и почта достаются из талона', () async {
      final info = await LicenseService.verify(monthly);
      expect(info, isNotNull);
      expect(info!.email, 'vasya@mail.ru');
      expect(info.until, DateTime.utc(2026, 10, 15));
      expect(info.plan, 'month');
      expect(info.issued, DateTime.utc(2026, 9, 8));
    });

    test('годовой тариф читается', () async {
      final info = await LicenseService.verify(yearly);
      expect(info!.plan, 'year');
      expect(info.until, DateTime.utc(2027, 9, 15));
    });

    test('у ключа навсегда срока нет', () async {
      final info = await LicenseService.verify(lifetime);
      expect(info!.until, isNull);
      expect(info.email, 'vasya@mail.ru');
    });

    test('чужая подпись не проходит', () async {
      expect(await LicenseService.verify(forged), isNull);
    });

    test('отозванный номер не принимается', () async {
      final info = await LicenseService.verify(monthly);
      LicenseService.revoked = <int>{info!.id};
      expect(await LicenseService.verify(monthly), isNull);
    });
  });

  group('срок', () {
    test('годный талон открывает Pro', () async {
      final result = await LicenseService.instance.apply(monthly);
      expect(result.info, isNotNull);
      expect(LicenseService.instance.isValid, isTrue);
    });

    test('истёкший талон не принимается, и это отдельный ответ', () async {
      final result = await LicenseService.instance.apply(expired);
      expect(result.info, isNull);
      expect(result.expired, isTrue);
      expect(LicenseService.instance.isValid, isFalse);
    });

    test('талон гаснет сам, когда срок вышел', () async {
      await LicenseService.instance.apply(monthly);
      expect(LicenseService.instance.isValid, isTrue);
      expect(LicenseService.instance.ticketValid, isTrue);
      // Приложение не перезапускали, а срок кончился.
      LicenseService.debugNow = DateTime.utc(2026, 10, 16);
      expect(LicenseService.instance.isValid, isFalse);
    });

    test('окно активации талона не касается', () async {
      // Ключу формата 2 на ввод даётся три дня; талон выдан 8 сентября, и
      // 20-го он обязан приниматься — сервер выдаёт его при каждом входе.
      final result = await LicenseService.instance.apply(monthly);
      expect(result.info, isNotNull);
      expect(result.expired, isFalse);
    });

    test('талон переживает перезапуск', () async {
      await LicenseService.instance.apply(monthly);
      await LicenseService.instance.load();
      expect(LicenseService.instance.isValid, isTrue);
      expect(LicenseService.instance.ticketInfo!.until,
          DateTime.utc(2026, 10, 15));
    });

    test('протухший талон с диска не поднимается', () async {
      await LicenseService.instance.apply(monthly);
      LicenseService.debugNow = DateTime.utc(2026, 11, 1);
      await LicenseService.instance.load();
      expect(LicenseService.instance.isValid, isFalse);
    });
  });

  group('талон и ключ навсегда живут порознь', () {
    test('подписка не затирает вечную покупку', () async {
      await LicenseService.instance.apply(lifetime, enforceWindow: false);
      await LicenseService.instance.apply(monthly);
      expect(LicenseService.instance.keyValid, isTrue);
      expect(LicenseService.instance.ticketValid, isTrue);
      expect(LicenseService.instance.info!.until, isNull);
      expect(LicenseService.instance.ticketInfo!.until,
          DateTime.utc(2026, 10, 15));
    });

    test('выход из аккаунта уносит талон, а покупку оставляет', () async {
      await LicenseService.instance.apply(lifetime, enforceWindow: false);
      await LicenseService.instance.apply(monthly);
      await LicenseService.instance.clearTicket();
      expect(LicenseService.instance.ticketValid, isFalse);
      expect(LicenseService.instance.keyValid, isTrue);
      expect(LicenseService.instance.isValid, isTrue);
    });

    test('кончившаяся подписка не отбирает вечную покупку', () async {
      await LicenseService.instance.apply(lifetime, enforceWindow: false);
      await LicenseService.instance.apply(monthly);
      LicenseService.debugNow = DateTime.utc(2027, 1, 1);
      await LicenseService.instance.load();
      expect(LicenseService.instance.isValid, isTrue);
      expect(LicenseService.instance.ticketValid, isFalse);
    });
  });
}
