import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:fern/l10n/locale_controller.dart';
import 'package:fern/models/deck.dart';
import 'package:fern/models/word_card.dart';
import 'package:fern/services/deck_import.dart';
import 'package:fern/services/deck_repository.dart';
import 'package:fern/services/pos.dart';
import 'package:fern/services/pos_split.dart';

import 'test_helpers.dart';

void main() {
  group('PosDetect', () {
    test('strip: часть речи отрезается от слова', () {
      expect(PosDetect.strip('the артикль'), ('the', 'article'));
      expect(PosDetect.strip('have глагол'), ('have', 'verb'));
      expect(PosDetect.strip('of предлог'), ('of', 'prep'));
      expect(PosDetect.strip('cat'), ('cat', null)); // нет метки
    });

    test('detect: словарь и эвристика англ. служебных слов', () {
      expect(PosDetect.detect('run', dictPos: 'verb'), 'verb');
      expect(PosDetect.detect('the', languageCode: 'en'), 'article');
      expect(PosDetect.detect('and', languageCode: 'en'), 'conj');
      expect(PosDetect.detect('xyzzy', languageCode: 'en'), ''); // неизвестно
    });
  });

  group('Импорт: POS не вклеивается в слово', () {
    final repo = DeckRepository.instance;
    setUp(() async {
      await resetStorage();
      await repo.init();
      await LocaleController.instance.setCode('ru');
    });

    test('CSV «the артикль,этот» → front «the», pos «article»', () async {
      final dir = Directory.systemTemp.createTempSync('fern_pos_csv');
      addTearDown(() => dir.deleteSync(recursive: true));
      final f = File('${dir.path}/deck.csv');
      await f.writeAsString('the артикль,этот\nbe глагол,быть\n');
      final res = await DeckImport.import(f.path, 'en');
      final cards = await repo.cardsForDeck(res.deckId!);
      final the = cards.firstWhere((c) => c.back == 'этот');
      expect(the.front, 'the');
      expect(the.pos, 'article');
      final be = cards.firstWhere((c) => c.back == 'быть');
      expect(be.front, 'be');
      expect(be.pos, 'verb');
    });
  });

  group('PosSplit', () {
    final repo = DeckRepository.instance;
    setUp(() async {
      await resetStorage();
      await repo.init();
      await LocaleController.instance.setCode('ru');
    });

    test('колода раскладывается на колоды по частям речи', () async {
      await repo.upsertDeck(Deck(
        id: 'd1',
        languageCode: 'en',
        name: 'Слова',
        colorValue: 1,
        shapeIndex: 0,
        createdAt: 1,
      ));
      await repo.addCards([
        WordCard(id: 'c1', deckId: 'd1', front: 'the', back: 'этот', pos: 'article'),
        WordCard(id: 'c2', deckId: 'd1', front: 'be', back: 'быть', pos: 'verb'),
        WordCard(id: 'c3', deckId: 'd1', front: 'have', back: 'иметь', pos: 'verb'),
        WordCard(id: 'c4', deckId: 'd1', front: 'cat', back: 'кот', pos: 'noun'),
      ]);
      final deck = repo.decks.firstWhere((d) => d.id == 'd1');

      final created = await PosSplit.split(deck);
      expect(created, 3); // article, verb, noun

      // Появился пак и колоды по типам; карты переехали.
      expect(repo.packs.length, 1);
      final verbDeck =
          repo.decks.firstWhere((d) => d.name == 'Глаголы');
      final verbCards = await repo.cardsForDeck(verbDeck.id);
      expect(verbCards.map((c) => c.front).toSet(), {'be', 'have'});
      // Исходная колода теперь в паке.
      expect(repo.decks.firstWhere((d) => d.id == 'd1').packId, isNotNull);
    });

    test('чистит вклеенную метку у старых карт при разбивке', () async {
      await repo.upsertDeck(Deck(
        id: 'd3',
        languageCode: 'en',
        name: 'Старое',
        colorValue: 1,
        shapeIndex: 0,
        createdAt: 1,
      ));
      // Старый импорт: часть речи вклеена в слово, pos не заполнен.
      await repo.addCards([
        WordCard(id: 'x1', deckId: 'd3', front: 'the артикль', back: 'этот'),
        WordCard(id: 'x2', deckId: 'd3', front: 'be глагол', back: 'быть'),
      ]);
      await PosSplit.split(repo.decks.firstWhere((d) => d.id == 'd3'));
      final cards = await repo.loadCards();
      final the = cards.firstWhere((c) => c.id == 'x1');
      expect(the.front, 'the'); // слово очищено
    });

    test('меньше двух частей речи — не разбиваем', () async {
      await repo.upsertDeck(Deck(
        id: 'd2',
        languageCode: 'en',
        name: 'X',
        colorValue: 1,
        shapeIndex: 0,
        createdAt: 1,
      ));
      await repo.addCards([
        WordCard(id: 'a', deckId: 'd2', front: 'cat', back: 'кот', pos: 'noun'),
        WordCard(id: 'b', deckId: 'd2', front: 'dog', back: 'пёс', pos: 'noun'),
      ]);
      final created =
          await PosSplit.split(repo.decks.firstWhere((d) => d.id == 'd2'));
      expect(created, 0);
    });
  });
}
