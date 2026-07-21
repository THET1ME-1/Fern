import 'package:flutter_test/flutter_test.dart';

import 'package:fern/l10n/locale_controller.dart';
import 'package:fern/services/deck_repository.dart';
import 'package:fern/services/starter_decks.dart';

import 'test_helpers.dart';

/// Что лежит в приложении сразу после онбординга.
///
/// Английские колоды сеялись ДО того, как человек выбирал язык изучения.
/// Выбрал испанский — четыре английские колоды остались в базе, скрытые
/// фильтром по языку: невидимая работа, всплывающая при переключении языка.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await resetStorage();
    await DeckRepository.instance.init();
    await LocaleController.instance.setCode('ru');
  });

  test('до выбора языка не сеется ничего', () async {
    await DeckRepository.instance.seedDemoIfNeeded();
    final decks = await DeckRepository.instance.loadDecks();
    expect(decks, isEmpty,
        reason: 'какой язык учить — ещё неизвестно, сеять нечего');
  });

  test('выбрал испанский — получил испанские колоды, не английские', () async {
    await DeckRepository.instance.setOnboarded(true);
    await StarterDecks.seedFor('es');

    final decks = await DeckRepository.instance.loadDecks();
    expect(decks, isNotEmpty);
    expect(decks.every((d) => d.languageCode == 'es'), isTrue,
        reason: 'английские колоды тут никто не просил');
    expect(decks.length, greaterThan(1),
        reason: 'набор целиком, а не первая колода из четырёх');
  });

  test('выбрал английский — получил английский набор', () async {
    await DeckRepository.instance.setOnboarded(true);
    await StarterDecks.seedFor('en');

    final decks = await DeckRepository.instance.loadDecks();
    expect(decks, isNotEmpty);
    expect(decks.every((d) => d.languageCode == 'en'), isTrue);
  });

  // Наборы есть у всех языков встроенного списка, поэтому «языка без набора»
  // приходится брать за его пределами: код вроде 'xx' человек заводит сам.
  test('язык без готового набора — пусто, но без ошибок', () async {
    await DeckRepository.instance.setOnboarded(true);
    await StarterDecks.seedFor('xx');
    expect(await DeckRepository.instance.loadDecks(), isEmpty);
  });

  test('набор кладётся целиком, колоды не затирают друг друга', () async {
    await DeckRepository.instance.setOnboarded(true);
    await StarterDecks.seedFor('es');
    final decks = await DeckRepository.instance.loadDecks();
    final ids = decks.map((d) => d.id).toSet();
    expect(ids.length, decks.length,
        reason: 'идентификатор колоды строился из метки времени, и четыре '
            'колоды набора укладывались в одну миллисекунду');
  });
}
