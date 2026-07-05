import 'dart:ffi';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/open.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:fern/services/deck_import.dart';
import 'package:fern/services/deck_repository.dart';

import 'test_helpers.dart';

void main() {
  final repo = DeckRepository.instance;

  setUpAll(() {
    // На хосте нет unversioned libsqlite3.so — на Android его даёт
    // sqlite3_flutter_libs; в тесте берём версионную .so.0.
    if (Platform.isLinux) {
      open.overrideForAll(() => DynamicLibrary.open('libsqlite3.so.0'));
    }
  });

  setUp(() async {
    await resetStorage();
    await repo.init();
  });

  test('CSV: заголовок пропускается, кавычки разбираются', () async {
    final dir = Directory.systemTemp.createTempSync('fern_csv');
    addTearDown(() => dir.deleteSync(recursive: true));
    final f = File('${dir.path}/deck.csv');
    await f.writeAsString(
      'front,back,example\n'
      'cat,кот,A cat.\n'
      '"hi, there",привет,\n',
    );

    final res = await DeckImport.import(f.path, 'en');
    expect(res.outcome, ImportOutcome.ok);
    expect(res.count, 2);
    final cards = await repo.cardsForDeck(res.deckId!);
    expect(cards.map((c) => c.front), containsAll(['cat', 'hi, there']));
  });

  test('TSV импортируется', () async {
    final dir = Directory.systemTemp.createTempSync('fern_tsv');
    addTearDown(() => dir.deleteSync(recursive: true));
    final f = File('${dir.path}/deck.tsv');
    await f.writeAsString('dog\tсобака\nsun\tсолнце\n');
    final res = await DeckImport.import(f.path, 'en');
    expect(res.count, 2);
  });

  test('Anki .apkg (SQLite collection.anki2) импортируется', () async {
    final dir = Directory.systemTemp.createTempSync('fern_apkg');
    addTearDown(() => dir.deleteSync(recursive: true));

    // Собираем минимальную Anki-базу.
    final dbPath = '${dir.path}/collection.anki2';
    final db = sqlite3.open(dbPath);
    db.execute('CREATE TABLE notes (id INTEGER PRIMARY KEY, flds TEXT)');
    final sep = String.fromCharCode(0x1f);
    final stmt = db.prepare('INSERT INTO notes (flds) VALUES (?)');
    stmt.execute([['cat', 'кот'].join(sep)]);
    stmt.execute([['<b>dog</b>', 'собака'].join(sep)]);
    stmt.dispose();
    db.dispose();

    // Упаковываем в .apkg (zip).
    final dbBytes = File(dbPath).readAsBytesSync();
    final archive = Archive()
      ..addFile(ArchiveFile('collection.anki2', dbBytes.length, dbBytes));
    final apkg = File('${dir.path}/deck.apkg');
    apkg.writeAsBytesSync(ZipEncoder().encode(archive));

    final res = await DeckImport.import(apkg.path, 'en');
    expect(res.outcome, ImportOutcome.ok);
    expect(res.count, 2);
    final cards = await repo.cardsForDeck(res.deckId!);
    // HTML вычищен: «<b>dog</b>» → «dog».
    expect(cards.map((c) => c.front), containsAll(['cat', 'dog']));
  });
}
