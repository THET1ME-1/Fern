import 'package:flutter_test/flutter_test.dart';

import 'package:fern/l10n/locale_controller.dart';
import 'package:fern/models/word_card.dart';

import 'test_helpers.dart';

/// Интервалы стоят на кнопках оценки — это самый заметный текст в приложении
/// после самого слова. Единицы были зашиты по-русски, и англичанин видел
/// «10 мин» и «16 дн» рядом с Good и Easy.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(resetStorage);

  final cyrillic = RegExp(r'[а-яА-Я]');

  test('единицы интервала переводятся вслед за языком интерфейса', () async {
    await LocaleController.instance.setCode('en');
    expect(durationLabel(const Duration(minutes: 10)), '10 min');
    expect(durationLabel(const Duration(days: 16)), '16 d');
    expect(durationLabel(const Duration(hours: 5)), '5 h');
    expect(durationLabel(const Duration(seconds: 30)), '<1 min');

    await LocaleController.instance.setCode('ru');
    expect(durationLabel(const Duration(minutes: 10)), '10 мин');
    expect(durationLabel(const Duration(days: 16)), '16 дн');
  });

  test('ни в одном языке интерфейса не остаётся кириллицы, кроме русского',
      () async {
    const durations = [
      Duration(seconds: 30),
      Duration(minutes: 10),
      Duration(hours: 5),
      Duration(days: 16),
      Duration(days: 60),
      Duration(days: 800),
    ];
    for (final lang in ['en', 'de', 'fr', 'es', 'it', 'pt']) {
      await LocaleController.instance.setCode(lang);
      for (final d in durations) {
        final label = durationLabel(d);
        expect(label.contains(cyrillic), isFalse,
            reason: '$lang: «$label» осталось на русском');
        expect(label.trim(), isNotEmpty);
      }
    }
  });

  // Наличие ключей во всех семи языках стережёт l10n_coverage_test: он идёт по
  // kBaseStrings и требует перевода в каждом языке.
}
