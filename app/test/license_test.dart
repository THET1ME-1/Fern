import 'package:flutter_test/flutter_test.dart';
import 'package:fern/services/license_service.dart';

import 'test_helpers.dart';

/// Лицензии Fern Pro.
///
/// Ключи ниже выпущены генератором бота (`bot/license.py`) на тестовой паре —
/// то есть тест проверяет ещё и то, что Python и Dart понимают один формат.
/// Разъедься кодировки, и купивший человек получил бы «ключ не годен».
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const testPublicKey = 'A6EHv/POEL4dcN0Y50vAmWfk1jCbpQ1fHdyGZBJVMbg=';
  // Лицензия №7, выдана 2026-07-20.
  const key7 = 'FERNAEAQAAAAA4AMRXNNQ7364JRZZ2NHJ5YNX2YNZLQTZLUH6SMQZLQJJBMM'
      'WDOJZ7WY2NX4NNXSAADP5DZ54MR43APQHTCJEPA4RA2MI42GSN7Q6R374UBA';
  // Лицензия №2001, выдана 2026-01-01.
  const key2001 = 'FERNAEAQAAAH2EAAA6HKJO3QNSFRFBMGAJ2K6AAQQGYKYOIUO4L6MMK4'
      'YY4DWRUEYWF2RRENLGD746WPUC3IHMMHCWEQ2P47XVJJ3BXOVMQJUPGBAUPLZECQ';

  setUp(() async {
    await resetStorage();
    LicenseService.debugPublicKeyBase64 = testPublicKey;
    LicenseService.revoked = <int>{};
  });

  tearDown(() {
    LicenseService.debugPublicKeyBase64 = null;
    LicenseService.revoked = <int>{};
  });

  test('Ключ из бота проходит проверку, номер и дата на месте', () async {
    final info = await LicenseService.verify(key7);
    expect(info, isNotNull);
    expect(info!.id, 7);
    expect(info.issued, DateTime.utc(2026, 7, 20));

    final old = await LicenseService.verify(key2001);
    expect(old!.id, 2001);
    expect(old.issued, DateTime.utc(2026, 1, 1));
  });

  test('Ключ читается как его перешлют: с пробелами, дефисами, строчными', () async {
    final messy = 'fern-${key7.substring(4, 30)} ${key7.substring(30)}';
    expect(await LicenseService.verify(messy), isNotNull);
  });

  test('Подделка не проходит: правка одного символа рушит подпись', () async {
    // Меняем символ внутри подписи на соседний по алфавиту.
    final broken = key7.replaceRange(60, 61, key7[60] == 'A' ? 'B' : 'A');
    expect(await LicenseService.verify(broken), isNull);
  });

  test('Чужая подпись не проходит: боевой публичный ключ не принимает тестовый', () async {
    LicenseService.debugPublicKeyBase64 = null; // боевой ключ
    expect(await LicenseService.verify(key7), isNull);
  });

  test('Мусор вместо ключа не роняет приложение', () async {
    for (final junk in ['', 'FERN', 'привет', 'FERN!!!', 'ABCDEF', 'FERNAAAA']) {
      expect(await LicenseService.verify(junk), isNull, reason: junk);
    }
  });

  test('Отозванный номер перестаёт работать', () async {
    LicenseService.revoked = {7};
    expect(await LicenseService.verify(key7), isNull);
    expect(await LicenseService.verify(key2001), isNotNull);
  });

  test('Принятый ключ переживает перезапуск, сброс его убирает', () async {
    final service = LicenseService.instance;
    expect((await service.apply(key7)).info, isNotNull);
    expect(service.isValid, isTrue);

    await service.load(); // как холодный старт
    expect(service.isValid, isTrue);
    expect(service.info!.id, 7);

    await service.clear();
    expect(service.isValid, isFalse);
    await service.load();
    expect(service.isValid, isFalse);
  });

  test('Ключ, отозванный после покупки, отваливается на старте', () async {
    final service = LicenseService.instance;
    await service.apply(key7);

    LicenseService.revoked = {7}; // обновление приложения принесло отзыв
    await service.load();
    expect(service.isValid, isFalse);
    // И не остаётся лежать в настройках, чтобы не показывать ложное «Pro».
    expect(service.key, isNull);
  });

  test('Негодный ключ не сохраняется', () async {
    final service = LicenseService.instance;
    expect((await service.apply('FERNZZZZ')).info, isNull);
    expect(service.isValid, isFalse);
    expect(service.key, isNull);
  });
}
