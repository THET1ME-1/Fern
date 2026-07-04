import 'package:flutter_test/flutter_test.dart';

import 'package:fern/models/deck.dart';
import 'package:fern/models/word_card.dart';
import 'package:fern/services/deck_repository.dart';
import 'package:fern/services/translation/endpoint_provider.dart';
import 'package:fern/services/translation/translation_provider.dart';
import 'package:fern/video/add_target.dart';
import 'package:fern/video/subtitle.dart';

import 'test_helpers.dart';

void main() {
  group('VideoService.parseId', () {
    test('парсит разные формы ссылок YouTube', () {
      expect(VideoService.parseId('https://youtu.be/dQw4w9WgXcQ'),
          'dQw4w9WgXcQ');
      expect(VideoService.parseId('https://www.youtube.com/watch?v=dQw4w9WgXcQ'),
          'dQw4w9WgXcQ');
      expect(VideoService.parseId('просто текст'), isNull);
    });
  });

  group('SubLine.wordSpan', () {
    test('границы слова = его начало → начало следующего (или конец реплики)',
        () {
      const line = SubLine(
        start: Duration(seconds: 10),
        end: Duration(seconds: 13),
        text: 'hello big world',
        words: [
          SubWord('hello', Duration(seconds: 10)),
          SubWord('big', Duration(milliseconds: 10800)),
          SubWord('world', Duration(milliseconds: 11500)),
        ],
      );
      final (s1, e1) = line.wordSpan(line.words[0]);
      expect(s1, const Duration(seconds: 10));
      expect(e1, const Duration(milliseconds: 10800));

      final (_, e3) = line.wordSpan(line.words[2]);
      expect(e3, const Duration(seconds: 13)); // последнее слово → конец реплики
      expect(line.hasWordTiming, isTrue);
    });
  });

  group('TransResult.options', () {
    test('дедуп без учёта регистра, primary первым', () {
      const r = TransResult(
        primary: 'книга',
        alternatives: ['Книга', 'том', 'книга'],
        sourceId: 'x',
      );
      expect(r.options, ['книга', 'том']);
    });
  });

  group('EndpointConfig', () {
    test('JSON round-trip сохраняет поля', () {
      const cfg = EndpointConfig(
        id: 'ep_1',
        name: 'Мой',
        kind: EndpointKind.ollama,
        baseUrl: 'http://host:11434',
        model: 'llama3.1',
      );
      final back = EndpointConfig.fromJson(cfg.toJson());
      expect(back.id, 'ep_1');
      expect(back.kind, EndpointKind.ollama);
      expect(back.baseUrl, 'http://host:11434');
      expect(back.model, 'llama3.1');
    });
  });

  group('WordCard видео-поля', () {
    test('round-trip и обратная совместимость со старым JSON', () {
      final c = WordCard(
        id: 'c1',
        deckId: 'd1',
        front: 'book',
        back: 'книга',
        sentence: 'a good book',
        sourceUrl: 'https://youtu.be/x',
        clipStartMs: 1000,
        clipEndMs: 2000,
      );
      final back = WordCard.fromJson(c.toJson());
      expect(back.sentence, 'a good book');
      expect(back.clipStartMs, 1000);
      expect(back.clipEndMs, 2000);

      // Старый JSON без новых полей — дефолты, ничего не падает.
      final old = WordCard.fromJson(
          {'id': 'c2', 'deckId': 'd1', 'front': 'f', 'back': 'b'});
      expect(old.sentence, '');
      expect(old.sourceUrl, '');
      expect(old.clipStartMs, isNull);
    });
  });

  group('VideoDeckTarget.addWord', () {
    setUp(() async => resetStorage());

    test('дедуп по «переду» без учёта регистра', () async {
      final repo = DeckRepository.instance;
      final deck = Deck(
        id: 'd1',
        languageCode: 'en',
        name: 'From video',
        colorValue: 0xFF2E7D5B,
        shapeIndex: 0,
        createdAt: 0,
      );
      await repo.upsertDeck(deck);

      final first = await VideoDeckTarget.addWord(deck, front: 'Book', back: 'книга');
      final dup = await VideoDeckTarget.addWord(deck, front: 'book', back: 'том');
      expect(first, isTrue);
      expect(dup, isFalse);

      final cards = await repo.cardsForDeck('d1');
      expect(cards.length, 1);
      expect(cards.first.front, 'Book');
    });
  });
}
