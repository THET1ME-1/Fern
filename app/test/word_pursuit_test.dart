import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:fern/models/deck.dart';
import 'package:fern/models/word_card.dart';
import 'package:fern/services/deck_repository.dart';
import 'package:fern/services/source_library.dart';
import 'package:fern/services/word_pursuit.dart';

import 'test_helpers.dart';

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  final String path;
  _FakePathProvider(this.path);

  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final repo = DeckRepository.instance;

  setUp(() async {
    await resetStorage();
    await repo.init();
    final dir = await Directory.systemTemp.createTemp('fern_pursuit_');
    PathProviderPlatform.instance = _FakePathProvider(dir.path);
  });

  Future<void> book(String title, String text) => SourceLibrary.instance
      .saveBook(title: title, languageCode: 'en', format: 'txt', text: text)
      .then((_) {});

  test('слово из нескольких источников выходит вперёд', () async {
    await book('Первый', 'The interregnum lasted for years. Periphery was quiet.');
    await book('Второй', 'Another interregnum began. Nothing else happened.');

    final list = await WordPursuit.forLanguage('en');

    expect(list.first.word, 'interregnum');
    expect(list.first.sources, 2);
    expect(list.first.count, 2);
    // Слово из одного источника преследователем не считается.
    expect(list.any((w) => w.word == 'periphery'), isFalse);
  });

  test('служебные слова не попадают в список', () async {
    await book('Первый', 'The house and the tree were there.');
    await book('Второй', 'The road and the river were there.');

    final list = await WordPursuit.forLanguage('en');
    expect(list.map((w) => w.word), isNot(contains('the')));
    expect(list.map((w) => w.word), isNot(contains('and')));
  });

  test('выученное слово из списка уходит', () async {
    await repo.upsertDeck(Deck(
      id: 'd1',
      languageCode: 'en',
      name: 'EN',
      colorValue: 0xFF2E7D5B,
      shapeIndex: 0,
      createdAt: 1,
    ));
    await repo.upsertCard(WordCard(
      id: 'c1',
      deckId: 'd1',
      front: 'interregnum',
      back: 'междуцарствие',
    ));
    await book('Первый', 'The interregnum lasted for years.');
    await book('Второй', 'Another interregnum began.');

    final list = await WordPursuit.forLanguage('en');
    expect(list.any((w) => w.word == 'interregnum'), isFalse);
  });
}
