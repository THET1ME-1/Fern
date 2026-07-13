import 'dart:convert';

import 'package:fern/models/deck.dart';
import 'package:fern/models/word_card.dart';
import 'package:fern/services/backup_service.dart';
import 'package:fern/services/book_analysis.dart';
import 'package:fern/services/book_import.dart';
import 'package:fern/services/deck_repository.dart';
import 'package:fern/services/local_db.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

/// Проверки на дефекты, найденные перед публичным релизом: они дорого стоили
/// пользователю (каша вместо русского текста, чёрный экран при повреждённой
/// базе, полный пересчёт анализа на каждое добавленное слово).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final repo = DeckRepository.instance;

  setUp(resetStorage);

  group('Импорт книги', () {
    test('русский текст в Windows-1251 читается, а не превращается в кашу', () {
      // «Привет, мир» в cp1251 — ровно так лежат старые .txt и .fb2 из сети.
      const bytes = [
        0xCF, 0xF0, 0xE8, 0xE2, 0xE5, 0xF2, 0x2C, 0x20, // «Привет, »
        0xEC, 0xE8, 0xF0, // «мир»
      ];
      final text = BookImport.debugDecode(bytes);
      expect(text, 'Привет, мир');
      expect(text.contains('�'), isFalse);
    });

    test('UTF-8 по-прежнему читается как UTF-8', () {
      final bytes = utf8.encode('Привет, мир — тире и «кавычки»');
      expect(BookImport.debugDecode(bytes), 'Привет, мир — тире и «кавычки»');
    });
  });

  group('Анализ книги', () {
    test('разбор текста считается один раз и даёт тот же результат', () async {
      const text = 'the cat sat on the mat with a cat';
      final tokens = BookAnalysis.prepare(text, 'en');
      final i = tokens.words.indexOf('cat');
      expect(i, isNot(-1));
      expect(tokens.counts[i], 2, reason: '«cat» встречается дважды');

      final byTokens = BookAnalysis.analyzeTokens(tokens, 'en');
      final full = BookAnalysis.analyze(text, 'en');
      expect(byTokens.totalTokens, full.totalTokens);
      expect(byTokens.uniqueTypes, full.uniqueTypes);
      expect(byTokens.unknownTypes, full.unknownTypes);
    });
  });

  group('Повреждённая база', () {
    test('карантин битого файла даёт запуститься и вернуть слова из копии',
        () async {
      await repo.init();
      await repo.upsertDeck(
        Deck(
          id: 'd1',
          languageCode: 'en',
          name: 'Слова',
          colorValue: 0xFF2E7D5B,
          shapeIndex: 0,
          createdAt: 1,
        ),
      );
      await repo.upsertCard(
        WordCard(id: 'c1', deckId: 'd1', front: 'cat', back: 'кот'),
      );
      expect(await repo.cardsForDeck('d1'), hasLength(1));

      // Снимок есть — теперь «теряем» базу, как при повреждении файла.
      final snapshot = await BackupService.exportJson(includeLibrary: false);
      await repo.recoverFromCorruptedDatabase();
      expect(
        repo.decks.where((d) => d.id == 'd1'),
        isEmpty,
        reason: 'после карантина база пустая — но приложение запускается',
      );

      await BackupService.restore(snapshot);
      final cards = await repo.cardsForDeck('d1');
      expect(cards, hasLength(1));
      expect(cards.first.front, 'cat');
    });

    test('карантин не падает, когда файла базы нет', () async {
      await LocalDb(path: DeckRepository.debugDatabasePath).quarantineFile();
    });
  });
}
