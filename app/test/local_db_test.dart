import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:fern/models/deck.dart';
import 'package:fern/models/pack.dart';
import 'package:fern/models/word_card.dart';
import 'package:fern/services/local_db.dart';

import 'test_helpers.dart';

void main() {
  late LocalDb db;
  late String path;

  setUp(() async {
    // resetStorage грузит libsqlite и чистит окружение.
    await resetStorage();
    path = '${Directory.systemTemp.path}/fern_localdb_$pid.db';
    for (final s in const ['', '-wal', '-shm', '-journal']) {
      final f = File('$path$s');
      if (f.existsSync()) f.deleteSync();
    }
    db = LocalDb(path: path);
    await db.open();
  });

  tearDown(() => db.close());

  Deck deck(String id, {String? pack}) => Deck(
        id: id,
        languageCode: 'en',
        name: id,
        colorValue: 1,
        shapeIndex: 0,
        createdAt: 0,
        packId: pack,
      );

  WordCard card(String id, {String deckId = 'd1', ReviewState? review}) =>
      WordCard(id: id, deckId: deckId, front: id, back: 'b', review: review);

  test('upsert карт: чтение и порядок вставки сохраняются', () {
    db.upsertCard(card('c1'));
    db.upsertCard(card('c2'));
    db.upsertCard(card('c3'));
    expect(db.allCards().map((c) => c.id).toList(), ['c1', 'c2', 'c3']);
    expect(db.cardCount(), 3);
  });

  test('upsert обновляет на месте, не перекидывая строку в конец', () {
    db.upsertCard(card('c1'));
    db.upsertCard(card('c2'));
    db.upsertCard(WordCard(id: 'c1', deckId: 'd1', front: 'c1', back: 'НОВОЕ'));
    final cards = db.allCards();
    expect(cards.map((c) => c.id).toList(), ['c1', 'c2'],
        reason: 'порядок не должен меняться при обновлении');
    expect(cards.first.back, 'НОВОЕ');
  });

  test('deleteCardsForDeck удаляет только карты своей колоды', () {
    db.upsertCard(card('a1', deckId: 'd1'));
    db.upsertCard(card('a2', deckId: 'd1'));
    db.upsertCard(card('b1', deckId: 'd2'));
    db.deleteCardsForDeck('d1');
    expect(db.allCards().map((c) => c.id).toList(), ['b1']);
  });

  test('countDue: новые (due=null) и просроченные считаются, будущие — нет', () {
    final now = DateTime(2024, 1, 10);
    db.upsertCard(card('new')); // due == null
    db.upsertCard(card('past',
        review: ReviewState(
            state: FsrsState.review, due: now.subtract(const Duration(days: 1)))));
    db.upsertCard(card('future',
        review: ReviewState(
            state: FsrsState.review, due: now.add(const Duration(days: 1)))));
    expect(db.countDue(now.millisecondsSinceEpoch), 2);
  });

  test('replaceAll заменяет набор целиком и сохраняет порядок списка', () {
    db.upsertCard(card('old'));
    db.replaceAllCards([card('x'), card('y'), card('z')]);
    expect(db.allCards().map((c) => c.id).toList(), ['x', 'y', 'z']);
  });

  test('колоды и паки: upsert/delete/count', () {
    db.upsertDeck(deck('d1'));
    db.upsertDeck(deck('d2'));
    db.upsertPack(Pack(
        id: 'p1', languageCode: 'en', name: 'P', colorValue: 1, createdAt: 0));
    expect(db.deckCount(), 2);
    expect(db.allPacks().length, 1);
    db.deleteDeck('d1');
    expect(db.allDecks().map((d) => d.id).toList(), ['d2']);
  });

  test('данные переживают закрытие и повторное открытие файла', () async {
    db.upsertDeck(deck('keep'));
    db.upsertCard(card('k1', deckId: 'keep'));
    db.close();
    final db2 = LocalDb(path: path);
    await db2.open();
    expect(db2.allDecks().map((d) => d.id).toList(), ['keep']);
    expect(db2.allCards().map((c) => c.id).toList(), ['k1']);
    db2.close();
  });
}
