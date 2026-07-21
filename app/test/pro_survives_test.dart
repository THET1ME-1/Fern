import 'package:flutter_test/flutter_test.dart';

import 'package:fern/services/backup_service.dart';
import 'package:fern/services/billing_service.dart';
import 'package:fern/services/deck_repository.dart';
import 'package:fern/services/license_service.dart';
import 'package:fern/services/pro.dart';

import 'test_helpers.dart';

/// Покупка не должна теряться на ровном месте.
///
/// `Pro.active` читается из памяти синглтонов, а с диском их сводит только
/// `load()` при запуске приложения. Всё, что пишет в prefs мимо сервисов,
/// оставляет память и диск в расхождении — до перезапуска человек видит одно,
/// а получает другое.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const testPublicKey = 'A6EHv/POEL4dcN0Y50vAmWfk1jCbpQ1fHdyGZBJVMbg=';
  const key7 = 'FERNAEAQAAAAA4AMRXNNQ7364JRZZ2NHJ5YNX2YNZLQTZLUH6SMQZLQJJBMM'
      'WDOJZ7WY2NX4NNXSAADP5DZ54MR43APQHTCJEPA4RA2MI42GSN7Q6R374UBA';

  setUp(() async {
    await resetStorage();
    LicenseService.debugPublicKeyBase64 = testPublicKey;
    await LicenseService.instance.clear();
    await BillingService.instance.debugSetOwned(false);
  });

  tearDown(() => LicenseService.debugPublicKeyBase64 = null);

  /// Перезапуск приложения: память синглтонов забыта, читаем диск заново.
  Future<void> restart() async {
    await LicenseService.instance.load();
    await BillingService.instance.load();
  }

  test('«удалить все данные» не отбирает купленный ключ', () async {
    await DeckRepository.instance.init();
    expect((await LicenseService.instance.apply(key7)).info, isNotNull);
    expect(Pro.active, isTrue);

    // Человек чистит СВОИ колоды и книги. Про покупку речи не было.
    await DeckRepository.instance.wipeAllData();
    await restart();

    expect(Pro.active, isTrue,
        reason: 'ключ добывать заново из переписки с ботом — так себе развязка');
    expect(LicenseService.instance.key, key7);
  });

  test('«удалить все данные» не отбирает покупку из магазина', () async {
    await DeckRepository.instance.init();
    await BillingService.instance.debugSetOwned(true);
    expect(Pro.active, isTrue);

    await DeckRepository.instance.wipeAllData();
    await restart();

    expect(Pro.active, isTrue,
        reason: 'без сети магазин покупку не подтвердит, и человек останется '
            'без оплаченного');
  });

  test('восстановление бэкапа включает Pro сразу, без перезапуска', () async {
    await DeckRepository.instance.init();
    await LicenseService.instance.apply(key7);
    final snapshot = await BackupService.exportJson(includeLibrary: false);

    // Новый телефон: чистая установка, тот же человек, свой снимок.
    await resetStorage();
    LicenseService.debugPublicKeyBase64 = testPublicKey;
    await LicenseService.instance.clear();
    await DeckRepository.instance.init();
    expect(Pro.active, isFalse);

    await BackupService.restore(snapshot);

    expect(Pro.active, isTrue,
        reason: 'иначе библиотека остаётся под замком и выглядит это как '
            '«покупка не восстановилась»');
    expect(LicenseService.instance.key, key7,
        reason: 'в настройках должен быть виден ключ, а не пустой тариф');
  });
}
