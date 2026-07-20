import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fern/l10n/locale_controller.dart';
import 'package:fern/l10n/strings.dart';
import 'package:fern/services/deck_repository.dart';

import 'test_helpers.dart';

/// Готовые наборы обязаны говорить на всех семи языках интерфейса.
///
/// Если у карточки есть перевод только на русский, попробовать язык сможет
/// один человек из семи, а остальные увидят кириллицу на обороте.
const _uiLangs = ['ru', 'en', 'de', 'fr', 'es', 'it', 'pt'];
const _assets = [
  'assets/seed/en.json',
  'assets/starter/es.json',
  'assets/starter/de.json',
  'assets/starter/fr.json',
  'assets/starter/it.json',
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final path in _assets) {
    test('$path: перевод есть на каждом языке интерфейса', () async {
      final raw = await rootBundle.loadString(path);
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final cards = [
        for (final deck in data['decks'] as List)
          ...(deck['cards'] as List).cast<Map<String, dynamic>>(),
      ];
      expect(cards, isNotEmpty);

      final gaps = <String>[];
      for (final card in cards) {
        final back = card['back'];
        if (back is! Map) {
          gaps.add('${card['front']}: оборот не карта языков');
          continue;
        }
        for (final lang in _uiLangs) {
          final value = (back[lang] as String?)?.trim() ?? '';
          if (value.isEmpty) gaps.add('${card['front']} → $lang');
        }
      }
      expect(gaps, isEmpty,
          reason: 'без перевода остались: ${gaps.take(10).join(', ')}');
    });
  }

  test('оборот подставляется по языку интерфейса, а не по русскому', () async {
    await resetStorage();
    await DeckRepository.instance.init();

    const back = {
      'ru': 'привет',
      'en': 'hello',
      'de': 'hallo',
      'fr': 'bonjour',
      'es': 'saludo',
      'it': 'ciao',
      'pt': 'olá',
    };
    for (final lang in _uiLangs) {
      await LocaleController.instance.setCode(lang);
      expect(localizedBack(back), back[lang],
          reason: 'интерфейс $lang должен видеть свой перевод');
    }
  });

  test('посев на немецком интерфейсе даёт немецкие обороты', () async {
    await resetStorage();
    await DeckRepository.instance.init();
    await LocaleController.instance.setCode('de');
    // Посев ждёт выбранного языка изучения — в тестах отмечаем
    // онбординг пройденным.
    await DeckRepository.instance.setOnboarded(true);
    await DeckRepository.instance.seedDemoIfNeeded();

    final cards = await DeckRepository.instance.loadCards();
    expect(cards, isNotEmpty, reason: 'английский набор сеется сам');

    final hello = cards.where((c) => c.front == 'you').toList();
    expect(hello, isNotEmpty);
    expect(hello.first.back, 'du, Sie',
        reason: 'иначе немец учит английский по русским подсказкам');
  });
}
