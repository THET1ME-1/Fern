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

/// Наборы первой волны: у них раскладка колод ровно 180/140/100/80.
const _firstWave = [
  'assets/seed/en.json',
  'assets/starter/es.json',
  'assets/starter/de.json',
  'assets/starter/fr.json',
  'assets/starter/it.json',
  'assets/starter/ru.json',
];

/// Остальные сорок девять языков. Слов те же 500, но делятся между колодами
/// иначе: сетка понятий у них общая, и «Первых слов» в ней больше.
const _secondWave = [
  'af', 'ar', 'az', 'bg', 'bn', 'ca', 'cs', 'da',
  'el', 'eo', 'et', 'fa', 'fi', 'ga', 'he', 'hi',
  'hr', 'hu', 'hy', 'id', 'is', 'ja', 'ka', 'kk',
  'ko', 'lt', 'lv', 'ms', 'nb', 'nl', 'pl', 'pt',
  'ro', 'sk', 'sl', 'sq', 'sr', 'sv', 'sw', 'ta',
  'te', 'th', 'tl', 'tr', 'uk', 'ur', 'uz', 'vi',
  'zh',
];

List<String> get _assets => [
      ..._firstWave,
      for (final code in _secondWave) 'assets/starter/$code.json',
    ];

/// Раскладка набора первой волны: столько карточек в колоде с таким ключом.
const _layout = {
  'seed_deck_first_words': 180,
  'seed_deck_verbs': 140,
  'seed_deck_food': 100,
  'seed_deck_clothes': 80,
};

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

  for (final path in _assets) {
    test('$path: 500 слов в четырёх колодах, без повторов', () async {
      final raw = await rootBundle.loadString(path);
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final decks = (data['decks'] as List).cast<Map<String, dynamic>>();

      final sizes = {
        for (final d in decks)
          d['nameKey'] as String: (d['cards'] as List).length,
      };
      if (_firstWave.contains(path)) {
        expect(sizes, _layout, reason: 'раскладка набора должна совпадать');
      } else {
        expect(sizes.keys.toSet(), _layout.keys.toSet(),
            reason: 'колоды набора те же четыре');
      }

      final cards = [
        for (final d in decks) ...(d['cards'] as List).cast<Map<String, dynamic>>(),
      ];
      expect(cards.length, 500, reason: 'набор на 500 слов — это обещание');

      // Одно слово дважды допустимо только с РАЗНЫМИ значениями: «orange» —
      // оранжевый и апельсин. Одинаковый перевод в двух колодах значит, что
      // человек учит одно и то же дважды, а интерференция ещё и считает такую
      // пару путаемой.
      final byFront = <String, Set<String>>{};
      for (final card in cards) {
        final front = card['front'] as String;
        final ru = ((card['back'] as Map)['ru'] as String?)?.trim() ?? '';
        byFront.putIfAbsent(front, () => <String>{}).add(ru);
      }
      final repeats = [
        for (final e in byFront.entries)
          if (e.value.length == 1 &&
              cards.where((c) => c['front'] == e.key).length > 1)
            e.key,
      ];
      expect(repeats, isEmpty,
          reason: 'повторы с тем же значением: ${repeats.join(', ')}');

      final noExample = [
        for (final c in cards)
          if (((c['example'] as String?) ?? '').trim().isEmpty) c['front'],
      ];
      expect(noExample, isEmpty);
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
