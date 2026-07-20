import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fern/l10n/locale_controller.dart';
import 'package:fern/services/deck_repository.dart';

import 'test_helpers.dart';

/// Каким языком приложение встречает человека на первом запуске.
///
/// Порядок такой: сохранённый выбор → язык телефона (перебираются все
/// предпочитаемые) → страна телефона → английский.
void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  void systemLocales(List<Locale> locales) {
    binding.platformDispatcher.localesTestValue = locales;
    binding.platformDispatcher.localeTestValue = locales.first;
    addTearDown(() {
      binding.platformDispatcher.clearLocalesTestValue();
      binding.platformDispatcher.clearLocaleTestValue();
    });
  }

  setUp(() async {
    await resetStorage();
    await DeckRepository.instance.init();
  });

  // ПЕРВЫМ в файле: дальше тесты зовут load() и меняют состояние синглтона.
  test('до первой загрузки язык не русский по умолчанию', () async {
    // Значение поля видно, если загрузка настроек не поднялась: с недавних пор
    // это не роняет запуск, а тихо оставляет то, что было. Русский по
    // умолчанию означал бы кириллицу у человека, который её не читает.
    systemLocales([const Locale('en', 'US')]);
    expect(LocaleController.instance.code, isNot('ru'));
  });

  test('язык телефона в списке поддержанных — берём его', () async {
    systemLocales([const Locale('es', 'MX')]);
    await LocaleController.instance.load();
    expect(LocaleController.instance.code, 'es');
  });

  test('язык не поддержан — смотрим на страну', () async {
    // Телефон на японском, но человек в Бразилии.
    systemLocales([const Locale('ja', 'BR')]);
    await LocaleController.instance.load();
    expect(LocaleController.instance.code, 'pt');
  });

  test('второй предпочитаемый язык тоже считается', () async {
    systemLocales([const Locale('ja', 'JP'), const Locale('de', 'DE')]);
    await LocaleController.instance.load();
    expect(LocaleController.instance.code, 'de');
  });

  test('ни язык, ни страна не подошли — английский', () async {
    systemLocales([const Locale('ja', 'JP')]);
    await LocaleController.instance.load();
    expect(LocaleController.instance.code, 'en',
        reason: 'английский — общий знаменатель, а не язык автора приложения');
  });

  test('сохранённый выбор сильнее системы', () async {
    systemLocales([const Locale('de', 'DE')]);
    await DeckRepository.instance.setLanguageCode('it');
    await LocaleController.instance.load();
    expect(LocaleController.instance.code, 'it');
  });

}
