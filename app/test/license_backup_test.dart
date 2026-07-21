import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fern/services/backup_service.dart';
import 'package:fern/services/deck_repository.dart';
import 'package:fern/services/license_service.dart';

import 'test_helpers.dart';

/// Ключ Pro лежит в prefs под тем же именем, что читает LicenseService.
const _kLicenseKey = 'licenseKey';

/// Тестовая пара подписи и выпущенный ею именной ключ №42 (vasya@mail.ru,
/// выдан 2026-07-21) — тот же, что в `license_named_test`.
const _testPublicKey = 'O6hgyWBgECdLZtmodoHQy0nXKG76CdzGo74d/OYTlGU=';
const _sample = 'FERNAIAQAAAAFIAMSDLWMFZXSYKANVQWS3BOOJ234M4NUW2SDTA7KQSZELK2'
    'FJOJAP3NKNJ34XJKS6WO2MRPVUFFM52YTDGSU5VLFKPDH7XBKRSEJN5KJHNSYY3B7YX24'
    'UVHCWFER3FFBY';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final repo = DeckRepository.instance;

  setUp(() async {
    await resetStorage();
    LicenseService.debugPublicKeyBase64 = _testPublicKey;
    LicenseService.debugNow = DateTime.utc(2026, 7, 22); // ключ свежий
    await LicenseService.instance.load();
  });

  tearDown(() {
    LicenseService.debugPublicKeyBase64 = null;
    LicenseService.debugNow = null;
  });

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
    await repo.init();
    expect((await LicenseService.instance.apply(_sample)).info, isNotNull);

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

  test('копия со свежим ключом открывает Pro', () async {
    await repo.init();
    await SharedPreferencesAsync().setString(_kLicenseKey, _sample);
    final snapshot = await repo.exportMap();

    await resetStorage();
    await repo.init();
    await repo.importMap(snapshot);
    await LicenseService.instance.load();

    expect(LicenseService.instance.isValid, isTrue);
  });

  test('копия со старым ключом Pro не открывает', () async {
    // Иначе покупку раздавали бы файлом копии: окно активации обходилось бы
    // в один клик «восстановить». Свой ключ покупатель обновит у бота за
    // секунду — чужой человек этого сделать не сможет.
    await repo.init();
    await SharedPreferencesAsync().setString(_kLicenseKey, _sample);
    final snapshot = await repo.exportMap();

    await resetStorage();
    await repo.init();
    LicenseService.debugNow = DateTime.utc(2027, 3, 1); // копия пролежала полгода
    await repo.importMap(snapshot);
    await LicenseService.instance.load();

    expect(LicenseService.instance.isValid, isFalse);
    expect(await SharedPreferencesAsync().getString(_kLicenseKey), isNull,
        reason: 'негодный ключ не должен оседать в настройках');
  });

  test('восстановление говорит, что ключ пора обновить', () async {
    await repo.init();
    await SharedPreferencesAsync().setString(_kLicenseKey, _sample);
    final raw = await BackupService.exportJson(includeLibrary: false);

    await resetStorage();
    await repo.init();
    LicenseService.debugNow = DateTime.utc(2027, 3, 1);
    final result = await BackupService.restore(raw);

    expect(result.licenseExpired, isTrue,
        reason: 'человеку надо сказать, что делать, а не молча закрыть Pro');
  });

  test('копия без ключа ни на что не жалуется', () async {
    await repo.init();
    final raw = await BackupService.exportJson(includeLibrary: false);

    await resetStorage();
    await repo.init();
    final result = await BackupService.restore(raw);

    expect(result.licenseExpired, isFalse);
  });
}
