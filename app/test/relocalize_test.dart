import 'package:fern/l10n/locale_controller.dart';
import 'package:fern/l10n/strings.dart';
import 'package:fern/models/deck.dart';
import 'package:fern/models/word_card.dart';
import 'package:fern/services/deck_repository.dart';
import 'package:fern/services/starter_decks.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

/// Стартовые колоды переводились один раз — в момент создания — и намертво
/// оставались на том языке. Сменил интерфейс на английский, а карточки всё ещё
/// «hola → привет».
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final repo = DeckRepository.instance;

  setUp(resetStorage);

  test('стартовая колода переводится вслед за языком интерфейса', () async {
    await repo.init();
    await LocaleController.instance.setCode('ru');

    final packs = await StarterDecks.forLanguage('es');
    expect(packs, isNotEmpty);
    await StarterDecks.add(packs.first);

    final deck = repo.decks.firstWhere((d) => d.languageCode == 'es');
    expect(deck.isBuiltIn, isTrue, reason: 'у встроенной колоды есть ключ имени');

    Future<String> hola() async => (await repo.cardsForDeck(deck.id))
        .firstWhere((c) => c.front == 'hola')
        .back;

    expect(deck.name, tr('seed_deck_first_words'));
    expect(await hola(), 'привет');

    // Переключаем интерфейс — колода и карточки должны переехать на английский.
    await LocaleController.instance.setCode('en');
    final english = repo.decks.firstWhere((d) => d.id == deck.id);
    expect(english.name, 'First words');
    expect(await hola(), 'hello');

    // И обратно.
    await LocaleController.instance.setCode('de');
    expect(await hola(), 'hallo');
  });

  test('правки пользователя переводом не затираются', () async {
    await repo.init();
    await LocaleController.instance.setCode('ru');

    final packs = await StarterDecks.forLanguage('es');
    await StarterDecks.add(packs.first);
    final deck = repo.decks.firstWhere((d) => d.languageCode == 'es');

    final card = (await repo.cardsForDeck(deck.id))
        .firstWhere((c) => c.front == 'hola');
    card.back = 'моё слово';
    await repo.upsertCard(card);

    await LocaleController.instance.setCode('en');

    final after = (await repo.cardsForDeck(deck.id))
        .firstWhere((c) => c.front == 'hola');
    expect(after.back, 'моё слово', reason: 'своё не трогаем');
  });

  test('колода пользователя локализацией не затрагивается', () async {
    await repo.init();
    await LocaleController.instance.setCode('ru');

    await repo.upsertDeck(
      Deck(
        id: 'mine',
        languageCode: 'es',
        name: 'Мои слова',
        colorValue: 0xFF2E7D5B,
        shapeIndex: 0,
        createdAt: 1,
      ),
    );
    await repo.upsertCard(
      WordCard(id: 'u1', deckId: 'mine', front: 'hola', back: 'привет'),
    );

    await LocaleController.instance.setCode('en');

    final fresh = repo.decks.firstWhere((d) => d.id == 'mine');
    expect(fresh.name, 'Мои слова');
    expect((await repo.cardsForDeck('mine')).first.back, 'привет');
  });
}
