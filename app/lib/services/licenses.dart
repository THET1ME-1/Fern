import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

/// Лицензии на чужие материалы, которые едут внутри приложения.
///
/// Flutter сам собирает лицензии пакетов, но про ассеты он не знает: шрифты
/// Unbounded и Onest распространяются под SIL OFL 1.1, а она прямо требует
/// прикладывать текст лицензии к любой копии шрифта. Регистрируем их, чтобы
/// экран «Лицензии» показывал правду.
void registerAssetLicenses() {
  LicenseRegistry.addLicense(() async* {
    final ofl = await rootBundle.loadString('assets/licenses/OFL-1.1.txt');

    yield LicenseEntryWithLineBreaks(
      const ['Unbounded (font)'],
      'Copyright (c) 2022 The Unbounded Project Authors '
      '(https://github.com/Sean-Mc-Mahon/Unbounded), '
      'with Reserved Font Name "Unbounded".\n\n$ofl',
    );

    yield LicenseEntryWithLineBreaks(
      const ['Onest (font)'],
      'Copyright (c) 2022 The Onest Project Authors '
      '(https://github.com/nikolayrastorguev/Onest), '
      'with Reserved Font Name "Onest".\n\n$ofl',
    );

    yield const LicenseEntryWithLineBreaks(
      ['Moby Part-of-Speech (dictionary)'],
      'Moby Part-of-Speech II by Grady Ward.\n\n'
      'Placed in the public domain. Используется как офлайн-словарь частей '
      'речи для английского языка.\n'
      'https://en.wikipedia.org/wiki/Moby_Project',
    );

    yield LicenseEntryWithLineBreaks(
      const ['Octanove Vocabulary Profile C1/C2 (word list)'],
      'Octanove Vocabulary Profile C1/C2 (ver 1.0), Octanove Labs LLC.\n\n'
      'Licensed under CC BY-SA 4.0. Список слов уровней C1 и C2 взят как '
      'основа готового набора для английского; переводы на семь языков, '
      'определения и примеры написаны для Fern и распространяются на тех же '
      'условиях.\n'
      'https://github.com/openlanguageprofiles/olp-en-cefrj\n\n'
      '${await rootBundle.loadString('assets/licenses/CC-BY-SA-4.0.txt')}',
    );
  });
}
