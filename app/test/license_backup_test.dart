import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fern/services/deck_repository.dart';

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
