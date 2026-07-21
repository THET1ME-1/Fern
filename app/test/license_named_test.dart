import 'package:flutter_test/flutter_test.dart';
import 'package:fern/services/license_service.dart';

import 'test_helpers.dart';

/// Именные ключи (формат 2): внутри лежит почта покупателя.
///
/// Ключ остаётся переносимым — офлайн-проверка не умеет считать активации. Но
/// адрес виден в настройках, и выложить такой ключ в общий доступ значит
/// выложить вместе с ним свою почту.
///
/// Ключи ниже выпущены генератором бота (`bot/license.py`) на отдельной
/// тестовой паре — тест заодно стережёт, что Python и Dart понимают формат
/// одинаково.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const testPublicKey = 'O6hgyWBgECdLZtmodoHQy0nXKG76CdzGo74d/OYTlGU=';

  // Лицензия №42 на vasya@mail.ru, выдана 2026-07-21.
  const named = 'FERNAIAQAAAAFIAMSDLWMFZXSYKANVQWS3BOOJ234M4NUW2SDTA7KQSZELK2'
      'FJOJAP3NKNJ34XJKS6WO2MRPVUFFM52YTDGSU5VLFKPDH7XBKRSEJN5KJHNSYY3B7YX24UV'
      'HCWFER3FFBY';
  // Длинный адрес: 51 байт почты внутри ключа.
  const longEmail = 'FERNAIAQAAAAFMAMSMTWMVZHSLTMN5XGOLTBMRSHEZLTOMXG6ZROMEX'
      'GE5LZMVZEA43VMJSG63LBNFXC4ZLYMFWXA3DFFZXXEZ7J6CKGP35BFNOGUEOYUUDAXQWH2O'
      'BRATN4ALJH4O3FSYS2SNH42GUWHYSMEESWA6RJMINNOJXLI2OHD6WF3YPOKGLYQWAZOH7PN'
      'YRAY';
  // Кириллица в адресе: почта едет в UTF-8.
  const unicodeEmail = 'FERNAIAQAAAAFMAMSGGQWLILBUMB2GHUBUF72C7NDB6RQLILALWRQ'
      'DIYIY3SFTZ4G4PWXP4YPBSNBUYB2D7RL3RLWQG64O66CDA5PFRJFZMABGXMNDOA5K3DMKK7'
      'SAJGOUQUIOJWTFEX54HACV3PTS7XFWAXFAHQ';
  // Ключ прежнего формата, выпущенный той же парой: без почты.
  const plain = 'FERNAEAQAAAAA4AMR2O2MQS2773RYG4S4ZRR5RM6ZXQ5TMSOZ7K6E24FJFKH'
      'KTQQBCL2QCYPSUAPXFVWJ35AFGU3GZ67GUWL4IVOMUF24UFPVUBCN6WLAMCQ';

  setUp(() async {
    await resetStorage();
    LicenseService.debugPublicKeyBase64 = testPublicKey;
    LicenseService.revoked = <int>{};
  });

  tearDown(() {
    LicenseService.debugPublicKeyBase64 = null;
    LicenseService.revoked = <int>{};
  });

  group('разбор', () {
    test('почта достаётся из ключа', () async {
      final info = await LicenseService.verify(named);
      expect(info, isNotNull);
      expect(info!.id, 42);
      expect(info.email, 'vasya@mail.ru');
      expect(info.issued, DateTime.utc(2026, 7, 21));
    });

    test('длинный адрес переживает кодировку', () async {
      final info = await LicenseService.verify(longEmail);
      expect(info!.email, 'very.long.address.of.a.buyer@subdomain.example.org');
    });

    test('кириллица в адресе не ломается', () async {
      final info = await LicenseService.verify(unicodeEmail);
      expect(info!.email, 'вася@почта.рф');
    });

    test('ключи прежнего формата работают дальше', () async {
      final info = await LicenseService.verify(plain);
      expect(info, isNotNull);
      expect(info!.id, 7);
      expect(info.email, isNull);
    });

    test('правка внутри почты рушит подпись', () async {
      final broken = named.replaceRange(20, 21, named[20] == 'A' ? 'B' : 'A');
      expect(await LicenseService.verify(broken), isNull);
    });

    test('обрезанный именной ключ не проходит', () async {
      expect(await LicenseService.verify(named.substring(0, named.length - 8)),
          isNull);
    });
  });

  group('показ адреса', () {
    test('середина имени прячется', () {
      expect(LicenseInfo.maskEmail('vasya@mail.ru'), 'va***@mail.ru');
    });

    test('короткое имя прячется целиком', () {
      expect(LicenseInfo.maskEmail('ab@mail.ru'), '***@mail.ru');
      expect(LicenseInfo.maskEmail('a@mail.ru'), '***@mail.ru');
    });

    test('адрес без собаки не притворяется почтой', () {
      expect(LicenseInfo.maskEmail('простотекст'), '***');
    });

    test('пусто на входе — пусто на выходе', () {
      expect(LicenseInfo.maskEmail(null), isNull);
      expect(LicenseInfo.maskEmail(''), isNull);
    });
  });
}
