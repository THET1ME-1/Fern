import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fern/models/word_card.dart';
import 'package:fern/services/article_import.dart';
import 'package:fern/services/vocab_export.dart';

/// Внешние данные, которые приложение принимает без спроса: чужая колода в
/// экспортируемом словаре и произвольная ссылка на «статью».
void main() {
  group('CSV-экспорт против формул', () {
    test('ячейка-формула нейтрализуется апострофом', () {
      final cards = [
        WordCard(
          id: '1',
          deckId: 'd',
          front: '=HYPERLINK("http://evil","x")',
          back: '@SUM(1)',
          example: '+1',
        ),
        WordCard(id: '2', deckId: 'd', front: '-ing', back: 'суффикс'),
        WordCard(id: '3', deckId: 'd', front: 'cat', back: 'кот'),
      ];
      final csv = VocabExport.build(VocabFormat.csv, cards);
      final lines = csv.trim().split('\n');
      expect(lines[1], startsWith('''"'=HYPERLINK'''),
          reason: 'формула обязана стать текстом');
      expect(lines[1], contains("'@SUM"));
      expect(lines[1], contains("'+1"));
      expect(lines[2], startsWith("'-ing"),
          reason: 'иначе Excel показывает #NAME? вместо суффикса');
      expect(lines[3], 'cat,кот,',
          reason: 'обычные слова не трогаем');
    });

    test('Anki-TSV не трогаем — его читает Anki, а не таблицы', () {
      final cards = [
        WordCard(id: '1', deckId: 'd', front: '-ing', back: 'суффикс'),
      ];
      final tsv = VocabExport.build(VocabFormat.ankiTsv, cards);
      expect(tsv, startsWith('-ing\t'));
    });
  });

  group('потолок скачивания статьи', () {
    MockClient streamOf(Stream<List<int>> Function() body) =>
        MockClient.streaming((req, _) async => http.StreamedResponse(
              body(),
              200,
              headers: {'content-type': 'text/html; charset=utf-8'},
            ));

    test('бесконечное тело останавливается на потолке, а не в OOM', () async {
      final chunk = utf8.encode('<p>${'слово ' * 2000}</p>');
      final client = streamOf(() async* {
        // В два раза больше потолка — досюда чтение дойти не должно.
        final n = (ArticleImport.maxBytes * 2 / chunk.length).ceil();
        for (var i = 0; i < n; i++) {
          yield chunk;
        }
      });
      expect(
        await ArticleImport.fetch('https://example.com/a', client: client),
        isNull,
      );
    });

    test('обычная статья проходит', () async {
      final client = streamOf(() => Stream.value(utf8.encode(
          '<html><head><title>Заголовок</title></head>'
          '<body><article><p>${'Текст статьи. ' * 20}</p></article>'
          '</body></html>')));
      final a =
          await ArticleImport.fetch('https://example.com/a', client: client);
      expect(a?.title, 'Заголовок');
      expect(a?.hasText, isTrue);
    });
  });
}
