import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:fern/models/deck.dart';
import 'package:fern/models/pack.dart';
import 'package:fern/models/word_card.dart';
import 'package:fern/services/book_import.dart';
import 'package:fern/services/deck_repository.dart';

import 'test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final repo = DeckRepository.instance;

  setUp(resetStorage);

  Deck deckOf(String id, {String lang = 'en', String? packId}) => Deck(
        id: id,
        languageCode: lang,
        name: id,
        colorValue: 0xFF2E7D5B,
        shapeIndex: 0,
        createdAt: 1,
        packId: packId,
      );

  group('Сверка слов по всей базе (дедуп)', () {
    test('знает слова из всех колод языка и игнорирует другой язык', () async {
      await repo.upsertDeck(deckOf('d1'));
      await repo.upsertDeck(deckOf('d2'));
      await repo.upsertDeck(deckOf('dru', lang: 'ru'));
      await repo.upsertCard(WordCard(id: 'c1', deckId: 'd1', front: 'Hello', back: 'привет'));
      await repo.upsertCard(WordCard(id: 'c2', deckId: 'd2', front: 'World', back: 'мир'));
      await repo.upsertCard(WordCard(id: 'c3', deckId: 'dru', front: 'мир', back: 'peace'));

      final known = repo.knownFrontsForLanguage('en');
      expect(known.contains('hello'), isTrue);
      expect(known.contains('world'), isTrue);
      expect(known.contains('мир'), isFalse, reason: 'русское слово — другой язык');

      expect(repo.hasWordInLanguage('HELLO', 'en'), isTrue);
      expect(repo.hasWordInLanguage('missing', 'en'), isFalse);
      expect(repo.hasWordInLanguage('Hello', 'ru'), isFalse);
    });
  });

  group('Паки', () {
    test('колода помнит пак после перезагрузки (round-trip)', () async {
      await repo.upsertPack(Pack(
        id: 'p1',
        languageCode: 'en',
        name: 'Пак',
        colorValue: 0xFF3F6FB0,
        createdAt: 1,
      ));
      await repo.upsertDeck(deckOf('d1', packId: 'p1'));

      repo.resetForTest();
      final decks = await repo.loadDecks();
      final packs = await repo.loadPacks();
      expect(packs.length, 1);
      expect(decks.single.packId, 'p1');
    });

    test('удаление пака НЕ удаляет колоды — они выпадают на верхний уровень',
        () async {
      await repo.upsertPack(Pack(
        id: 'p1',
        languageCode: 'en',
        name: 'Пак',
        colorValue: 0xFF3F6FB0,
        createdAt: 1,
      ));
      await repo.upsertDeck(deckOf('d1', packId: 'p1'));

      await repo.deletePack('p1');
      final packs = await repo.loadPacks();
      final decks = await repo.loadDecks();
      expect(packs, isEmpty);
      expect(decks.length, 1);
      expect(decks.single.packId, isNull, reason: 'колода сохранилась без пака');
    });

    test('setDeckPack кладёт и вынимает колоду', () async {
      await repo.upsertDeck(deckOf('d1'));
      await repo.setDeckPack('d1', 'p9');
      expect((await repo.loadDecks()).single.packId, 'p9');
      await repo.setDeckPack('d1', null);
      expect((await repo.loadDecks()).single.packId, isNull);
    });
  });

  group('Deck.toJson/fromJson packId', () {
    test('пишет pack только когда он задан', () {
      final withPack = deckOf('d1', packId: 'p1').toJson();
      expect(withPack['pack'], 'p1');
      final noPack = deckOf('d2').toJson();
      expect(noPack.containsKey('pack'), isFalse);
      expect(Deck.fromJson(withPack).packId, 'p1');
      expect(Deck.fromJson(noPack).packId, isNull);
    });
  });

  group('Импорт книг', () {
    test('SRT: выбрасывает индексы и таймкоды, оставляет текст', () async {
      final f = File('${Directory.systemTemp.createTempSync().path}/s.srt');
      await f.writeAsString(
        '1\n00:00:01,000 --> 00:00:04,000\nHello world\n\n'
        '2\n00:00:05,000 --> 00:00:07,000\nHow are you\n',
      );
      final book = await BookImport.extract(f.path);
      expect(book, isNotNull);
      expect(book!.text.contains('Hello world'), isTrue);
      expect(book.text.contains('How are you'), isTrue);
      expect(book.text.contains('-->'), isFalse);
      expect(book.text.contains('00:00'), isFalse);
    });

    test('HTML: снимает теги и декодирует сущности', () async {
      final f = File('${Directory.systemTemp.createTempSync().path}/b.html');
      await f.writeAsString(
        '<html><head><style>x{}</style></head><body>'
        '<p>Hello &amp; welcome</p><p>Second line</p></body></html>',
      );
      final book = await BookImport.extract(f.path);
      expect(book, isNotNull);
      expect(book!.text.contains('Hello & welcome'), isTrue);
      expect(book.text.contains('Second line'), isTrue);
      expect(book.text.contains('<p>'), isFalse);
      expect(book.text.contains('style'), isFalse);
    });

    test('TXT: сохраняет абзацы, схлопывает лишние пробелы', () async {
      final f = File('${Directory.systemTemp.createTempSync().path}/b.txt');
      await f.writeAsString('First    paragraph.\n\n\nSecond   paragraph.');
      final book = await BookImport.extract(f.path);
      expect(book, isNotNull);
      final lines = book!.text.split('\n');
      expect(lines.length, 2);
      expect(lines[0], 'First paragraph.');
      expect(lines[1], 'Second paragraph.');
    });
  });
}
