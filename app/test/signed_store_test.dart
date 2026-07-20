import 'package:flutter_test/flutter_test.dart';
import 'package:fern/services/signed_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_helpers.dart';

/// Подписанные настройки: состояние покупки и счётчик бесплатных разборов.
///
/// Правка настроек снаружи — самый лёгкий способ получить Pro даром: файл
/// настроек читаем с root-правами, через adb и через редакторы бэкапов, а
/// пересобирать приложение при этом не надо. Подпись поднимает планку до
/// пересборки, от которой в открытом коде защиты нет и не будет.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(resetStorage);

  test('Своё значение читается обратно', () async {
    await SignedStore.setBool('pro', true);
    expect(await SignedStore.getBool('pro'), isTrue);

    await SignedStore.setInt('used', 3);
    expect(await SignedStore.getInt('used', onTampered: 99), 3);
  });

  test('Подменённое значение не проходит', () async {
    await SignedStore.setBool('pro', false);
    // Кто-то поправил файл настроек: значение стало другим, подпись осталась
    // от прежнего.
    await SharedPreferencesAsync().setBool('pro', true);
    expect(await SignedStore.getBool('pro'), isFalse);
  });

  test('Значение без подписи не проходит', () async {
    await SharedPreferencesAsync().setBool('pro', true);
    expect(await SignedStore.getBool('pro'), isFalse);
  });

  test('Ненаписанное значение отличается от подделанного', () async {
    // Чистая установка: счётчика нет вовсе. Считать это попыткой обхода
    // нельзя — иначе первая книга закроется у того, кто ничего не трогал.
    expect(await SignedStore.getInt('never', onTampered: 7), isNull);
  });

  test('Обнулённый счётчик возвращает безопасный запас, а не ноль', () async {
    // Счётчик израсходованных разборов обнуляют, чтобы получить ещё книгу.
    // Ответ на подделку — считать всё израсходованным, а не начатым заново.
    await SignedStore.setInt('used', 1);
    await SharedPreferencesAsync().setInt('used', 0);
    expect(await SignedStore.getInt('used', onTampered: 7), 7);
  });

  test('Чужая подпись не годится', () async {
    await SignedStore.setInt('used', 1);
    final sign = await SharedPreferencesAsync().getString('used.sig');
    await SignedStore.setInt('other', 5);
    // Подпись от одного ключа не должна открывать другой: иначе значение
    // переставляют местами и обход снова работает.
    await SharedPreferencesAsync().setString('other.sig', sign!);
    await SharedPreferencesAsync().setInt('other', 1);
    expect(await SignedStore.getInt('other', onTampered: 42), 42);
  });
}
