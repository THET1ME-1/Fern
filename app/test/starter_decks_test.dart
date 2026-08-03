import 'package:flutter_test/flutter_test.dart';

import 'package:fern/l10n/locale_controller.dart';
import 'package:fern/services/deck_repository.dart';
import 'package:fern/services/starter_decks.dart';

import 'test_helpers.dart';

void main() {
  // Нужно, чтобы rootBundle отдавал объявленные ассеты в тестах.
  TestWidgetsFlutterBinding.ensureInitialized();
  final repo = DeckRepository.instance;

  setUp(() async {
    await resetStorage();
    await repo.init();
  });

  // Базовые 500 слов английскому кладутся сами, поэтому «Готовые колоды» для
  // него — это набор B1 сверху; общий механизм проверяем на испанском.
  test('испанский набор загружается из ассетов', () async {
    final packs = await StarterDecks.forLanguage('es');
    expect(packs.isNotEmpty, true);
    expect(packs.first.cards.isNotEmpty, true);
    // Переводы на русский непусты.
    expect(packs.first.cards.first.back.isNotEmpty, true);
  });

  test('несуществующий язык — пустой список', () async {
    expect(await StarterDecks.forLanguage('xx'), isEmpty);
    expect(await StarterDecks.hasPacksFor('xx'), false);
    expect(await StarterDecks.hasPacksFor('es'), true);
  });

  test('английский набор берут руками, а не на онбординге', () async {
    // Готовый набор у английского теперь есть — но это ПРОДОЛЖЕНИЕ поверх
    // стартовых 500 слов: B1 и C1–C2.
    expect(await StarterDecks.hasPacksFor('en'), true);
    final packs = await StarterDecks.forLanguage('en');
    expect(packs.map((p) => p.wordCount).reduce((a, b) => a + b), 2661);
    expect(packs.length, 8);

    // На онбординге кладутся только базовые колоды: 1278 карточек на первом
    // запуске — это не «посложнее», это закрыть приложение навсегда.
    await DeckRepository.instance.setOnboarded(true);
    await StarterDecks.seedFor('en');
    final decks = await DeckRepository.instance.loadDecks();
    expect(decks.any((d) => d.nameKey?.startsWith('starter_deck_') ?? false),
        isFalse);
    expect(decks, isNotEmpty, reason: 'базовый набор всё же посеян');
  });

  test('название и перевод колоды локализуются под язык интерфейса', () async {
    // Немецкий интерфейс: имя колоды и значения карточек — на немецком.
    await LocaleController.instance.setCode('de');
    final packsDe = await StarterDecks.forLanguage('es');
    expect(packsDe.first.name, 'Erste Wörter'); // seed_deck_first_words → de
    final holaDe = packsDe.first.cards.firstWhere((c) => c.front == 'hola');
    expect(holaDe.back, 'hallo');

    // Русский интерфейс: те же карточки — на русском.
    await LocaleController.instance.setCode('ru');
    final packsRu = await StarterDecks.forLanguage('es');
    expect(packsRu.first.name, 'Первые слова');
    final holaRu = packsRu.first.cards.firstWhere((c) => c.front == 'hola');
    expect(holaRu.back, 'привет');
  });

  test('добавление готовой колоды создаёт колоду и карты', () async {
    final packs = await StarterDecks.forLanguage('es');
    final pack = packs.first;
    await StarterDecks.add(pack, now: DateTime(2026, 7, 3));

    final decks = await repo.loadDecks();
    expect(decks.where((d) => d.name == pack.name).length, 1);
    final deck = decks.firstWhere((d) => d.name == pack.name);
    final cards = await repo.cardsForDeck(deck.id);
    expect(cards.length, pack.wordCount);
    expect(deck.languageCode, 'es');
  });
}
