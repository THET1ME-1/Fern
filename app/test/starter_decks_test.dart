import 'package:flutter_test/flutter_test.dart';

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

  // Английский теперь сеется по умолчанию, поэтому в «Готовых колодах» его нет;
  // проверяем на испанском наборе (остаётся для не-дефолтных языков).
  test('испанский набор загружается из ассетов', () async {
    final packs = await StarterDecks.forLanguage('es');
    expect(packs.isNotEmpty, true);
    expect(packs.first.cards.isNotEmpty, true);
    // Переводы на русский непусты.
    expect(packs.first.cards.first.back.isNotEmpty, true);
  });

  test('несуществующий язык — пустой список; английского в стартерах нет', () async {
    expect(await StarterDecks.forLanguage('xx'), isEmpty);
    expect(await StarterDecks.hasPacksFor('xx'), false);
    expect(await StarterDecks.hasPacksFor('es'), true);
    // Английский — дефолтный, среди стартеров его быть не должно.
    expect(await StarterDecks.hasPacksFor('en'), false);
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
