import 'package:flutter_test/flutter_test.dart';
import 'package:fern/services/license_service.dart';

import 'test_helpers.dart';

/// Окно активации: свежий ключ вводится один раз, а копия, гуляющая по сети,
/// протухает через пару дней.
///
/// Считать активации офлайн невозможно, поэтому ограничиваем не число
/// устройств, а срок годности самого ключа. Покупатель этого не замечает: бот
/// выдаёт ключ с текущей датой по первому запросу, хоть через год после
/// покупки. А выложенный на форум ключ к моменту, когда его кто-то увидит,
/// чаще всего уже мёртв.
///
/// Активированный ключ живёт дальше без ограничений — иначе Pro отваливался бы
/// у честного покупателя на третий день.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const testPublicKey = 'O6hgyWBgECdLZtmodoHQy0nXKG76CdzGo74d/OYTlGU=';

  // Именной ключ №42 (vasya@mail.ru), выдан 2026-07-21.
  const named = 'FERNAIAQAAAAFIAMSDLWMFZXSYKANVQWS3BOOJ234M4NUW2SDTA7KQSZELK2'
      'FJOJAP3NKNJ34XJKS6WO2MRPVUFFM52YTDGSU5VLFKPDH7XBKRSEJN5KJHNSYY3B7YX24UV'
      'HCWFER3FFBY';
  // Ключ прежнего формата, выдан 2026-07-20.
  const plain = 'FERNAEAQAAAAA4AMR2O2MQS2773RYG4S4ZRR5RM6ZXQ5TMSOZ7K6E24FJFKH'
      'KTQQBCL2QCYPSUAPXFVWJ35AFGU3GZ67GUWL4IVOMUF24UFPVUBCN6WLAMCQ';

  setUp(() async {
    await resetStorage();
    LicenseService.debugPublicKeyBase64 = testPublicKey;
    LicenseService.revoked = <int>{};
    LicenseService.debugNow = null;
    // Синглтон держит лицензию в памяти: без перечитывания чистых настроек
    // ключ из прошлого теста доживает до следующего.
    await LicenseService.instance.load();
  });

  tearDown(() {
    LicenseService.debugPublicKeyBase64 = null;
    LicenseService.revoked = <int>{};
    LicenseService.debugNow = null;
  });

  test('свежий ключ активируется', () async {
    LicenseService.debugNow = DateTime.utc(2026, 7, 22);
    final result = await LicenseService.instance.apply(named);
    expect(result.info, isNotNull);
    expect(result.expired, isFalse);
    expect(LicenseService.instance.isValid, isTrue);
  });

  test('на границе окна ещё активируется', () async {
    LicenseService.debugNow = DateTime.utc(2026, 7, 24, 23);
    expect((await LicenseService.instance.apply(named)).info, isNotNull);
  });

  test('после окна ключ не берут, и это отдельная беда', () async {
    LicenseService.debugNow = DateTime.utc(2026, 7, 26);
    final result = await LicenseService.instance.apply(named);
    expect(result.info, isNull);
    expect(result.expired, isTrue, reason: 'человеку надо сказать, что делать');
    expect(LicenseService.instance.isValid, isFalse);
  });

  test('подделка остаётся подделкой, а не просрочкой', () async {
    LicenseService.debugNow = DateTime.utc(2026, 7, 26);
    final result = await LicenseService.instance.apply('FERNZZZZ');
    expect(result.info, isNull);
    expect(result.expired, isFalse);
  });

  test('активированный ключ живёт после окна', () async {
    LicenseService.debugNow = DateTime.utc(2026, 7, 22);
    await LicenseService.instance.apply(named);

    LicenseService.debugNow = DateTime.utc(2027, 5, 1); // почти год спустя
    await LicenseService.instance.load(); // холодный старт
    expect(LicenseService.instance.isValid, isTrue);
    expect(LicenseService.instance.info!.id, 42);
  });

  test('ключи прежнего формата окном не ограничены', () async {
    LicenseService.debugNow = DateTime.utc(2027, 1, 1);
    final result = await LicenseService.instance.apply(plain);
    expect(result.info, isNotNull, reason: 'условия покупки задним числом не меняем');
  });
}
