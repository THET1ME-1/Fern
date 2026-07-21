import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fern/services/deck_repository.dart';
import 'package:fern/services/license_service.dart';

import 'test_helpers.dart';

/// Ключ Pro лежит в prefs под тем же именем, что читает LicenseService.
const _kLicenseKey = 'licenseKey';
const _sample = 'FERNAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final repo = DeckRepository.instance;

  setUp(resetStorage);

  test('ключ Pro уезжает в бэкап и возвращается на новом устройстве', () async {
    await repo.init();
    await SharedPreferencesAsync().setString(_kLicenseKey, _sample);

    final snapshot = await repo.exportMap();

    // «Новое устройство»: пустое хранилище, восстановление из снимка.
    await resetStorage();
    await repo.init();
    expect(await SharedPreferencesAsync().getString(_kLicenseKey), isNull);

    await repo.importMap(snapshot);

    expect(await SharedPreferencesAsync().getString(_kLicenseKey), _sample,
        reason: 'иначе после смены телефона Pro пропадает вместе с ключом');
  });

  test('«удалить все данные» не отбирает старую покупку', () async {
    // Стирание уносит настройки целиком и возвращает ключ на место само.
    // Окно активации к нему неприменимо: ключ уже принимали когда-то, и
    // человек, чистящий приложение через полгода, не должен терять Pro.
    const testPublicKey = 'O6hgyWBgECdLZtmodoHQy0nXKG76CdzGo74d/OYTlGU=';
    const named = 'FERNAIAQAAAAFIAMSDLWMFZXSYKANVQWS3BOOJ234M4NUW2SDTA7KQSZELK2'
        'FJOJAP3NKNJ34XJKS6WO2MRPVUFFM52YTDGSU5VLFKPDH7XBKRSEJN5KJHNSYY3B7YX24'
        'UVHCWFER3FFBY';
    LicenseService.debugPublicKeyBase64 = testPublicKey;
    addTearDown(() {
      LicenseService.debugPublicKeyBase64 = null;
      LicenseService.debugNow = null;
    });

    await repo.init();
    LicenseService.debugNow = DateTime.utc(2026, 7, 22); // ключ свежий
    expect((await LicenseService.instance.apply(named)).info, isNotNull);

    LicenseService.debugNow = DateTime.utc(2027, 3, 1); // полгода спустя
    await repo.wipeAllData();
    await LicenseService.instance.load();
    expect(LicenseService.instance.isValid, isTrue,
        reason: 'стирание данных не должно отбирать покупку');
  });

  test('слияние чужой копии ключ не подменяет', () async {
    await repo.init();
    await SharedPreferencesAsync().setString(_kLicenseKey, _sample);
    final snapshot = await repo.exportMap();

    await resetStorage();
    await repo.init();
    await SharedPreferencesAsync().setString(_kLicenseKey, 'FERNMYOWNKEY');

    // merge — это «добавить недостающее», а не «перезаписать своё».
    await repo.importMap(snapshot, merge: true);

    expect(await SharedPreferencesAsync().getString(_kLicenseKey), 'FERNMYOWNKEY');
  });
}
