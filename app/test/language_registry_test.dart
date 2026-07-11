import 'package:flutter_test/flutter_test.dart';

import 'package:fern/models/language.dart';
import 'package:fern/services/deck_repository.dart';
import 'package:fern/services/language_registry.dart';

import 'test_helpers.dart';

void main() {
  final reg = LanguageRegistry.instance;

  setUp(() async {
    await resetStorage();
    await DeckRepository.instance.init();
    await reg.load();
  });

  test('резолвит встроенные, но не неизвестные коды', () {
    expect(reg.byCode('en')?.name, 'English');
    expect(reg.byCode('ru')?.name, 'Русский');
    expect(reg.byCode('zzz'), isNull);
    expect(reg.isKnown('zzz'), false);
    expect(reg.isKnown('de'), true);
  });

  test('создание своего языка: резолв, тег «свой», авто-закрепление вверх',
      () async {
    await reg.addOrUpdateCustom(
        const StudyLanguage('tlh', 'Klingon', '🖖'), pin: true);
    expect(reg.isCustom('tlh'), true);
    expect(reg.byCode('tlh')?.name, 'Klingon');
    expect(reg.byCode('tlh')?.emoji, '🖖');
    expect(reg.isPinned('tlh'), true);
    // Закреплённый — первым в общем списке.
    expect(reg.all.first.code, 'tlh');
  });

  test('редактирование и удаление своего языка', () async {
    await reg.addOrUpdateCustom(const StudyLanguage('tlh', 'Klingon', '🖖'));
    await reg.addOrUpdateCustom(const StudyLanguage('tlh', 'Клингонский', '🛸'));
    expect(reg.byCode('tlh')?.name, 'Клингонский');
    expect(reg.byCode('tlh')?.emoji, '🛸');

    await reg.removeCustom('tlh');
    expect(reg.byCode('tlh'), isNull);
    expect(reg.isCustom('tlh'), false);
  });

  test('закрепление/открепление встроенного языка', () async {
    expect(reg.isPinned('ja'), false);
    await reg.setPinned('ja', true);
    expect(reg.isPinned('ja'), true);
    expect(reg.all.first.code, 'ja'); // закреплённый вверх
    await reg.togglePin('ja');
    expect(reg.isPinned('ja'), false);
  });

  test('свои языки и закрепления переживают перезапуск (persist → load)',
      () async {
    await reg.addOrUpdateCustom(
        const StudyLanguage('tlh', 'Klingon', '🖖'), pin: true);
    await reg.setPinned('ja', true);

    // Имитируем перезапуск: чистим память, грузим из prefs.
    reg.resetForTest();
    expect(reg.byCode('tlh'), isNull);
    await reg.load();

    expect(reg.byCode('tlh')?.name, 'Klingon');
    expect(reg.isPinned('tlh'), true);
    expect(reg.isPinned('ja'), true);
  });
}
