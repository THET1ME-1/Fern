import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:fern/models/deck.dart';
import 'package:fern/models/word_card.dart';
import 'package:fern/services/backup_service.dart';
import 'package:fern/services/card_images.dart';
import 'package:fern/services/deck_repository.dart';

import 'test_helpers.dart';

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  final String dir;
  _FakePathProvider(this.dir);
  @override
  Future<String?> getApplicationDocumentsPath() async => dir;
}

/// Крошечный валидный PNG (1×1, прозрачный) — чтобы файл был настоящей
/// картинкой, а не просто байтами.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk'
  'YPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final repo = DeckRepository.instance;
  late Directory tmp;

  Future<String> makeSource(String name) async {
    final f = File('${tmp.path}/$name');
    await f.writeAsBytes(_png);
    return f.path;
  }

  setUp(() async {
    await resetStorage();
    CardImages.resetForTest();
    tmp = Directory.systemTemp.createTempSync('fern_img_test');
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);
    await CardImages.init();
    await repo.init();
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('картинка кладётся под именем карточки и находится', () async {
    final name = await CardImages.save('c1', await makeSource('photo.png'));
    expect(name, 'c1.png');
    final path = CardImages.resolve(name!);
    expect(path, isNotNull);
    expect(File(path!).readAsBytesSync().length, _png.length);
  });

  test('новая картинка вытесняет прежнюю, даже с другим расширением', () async {
    await CardImages.save('c1', await makeSource('a.png'));
    final second = await CardImages.save('c1', await makeSource('b.jpg'));

    expect(second, 'c1.jpg');
    expect(CardImages.resolve('c1.png'), isNull,
        reason: 'старый файл не должен оставаться мусором');
    expect(CardImages.resolve('c1.jpg'), isNotNull);
  });

  test('удаление карточки уносит её картинку', () async {
    final deck = Deck(
      id: 'd1',
      languageCode: 'en',
      name: 'D',
      colorValue: 0xFF2E7D5B,
      shapeIndex: 0,
      createdAt: 1,
    );
    final name = await CardImages.save('c1', await makeSource('p.png'));
    await repo.upsertDeck(deck);
    await repo.upsertCard(WordCard(
      id: 'c1',
      deckId: 'd1',
      front: 'pillow',
      back: 'подушка',
      image: name!,
    ));

    expect(CardImages.resolve(name), isNotNull);
    await repo.deleteCard('c1');
    expect(CardImages.resolve(name), isNull);
  });

  test('картинка переживает бэкап и восстановление', () async {
    final deck = Deck(
      id: 'd1',
      languageCode: 'en',
      name: 'D',
      colorValue: 0xFF2E7D5B,
      shapeIndex: 0,
      createdAt: 1,
    );
    final name = await CardImages.save('c1', await makeSource('p.png'));
    await repo.upsertDeck(deck);
    await repo.upsertCard(WordCard(
      id: 'c1',
      deckId: 'd1',
      front: 'pillow',
      back: 'подушка',
      mnemonic: 'Под подушкой спрятана пила',
      image: name!,
    ));

    final json = await BackupService.exportJson();
    expect(json.contains('cardImages'), true);

    await repo.wipeAllData();
    expect(CardImages.resolve(name), isNull);

    await BackupService.restore(json);
    final restored = (await repo.cardsForDeck('d1')).single;
    expect(restored.mnemonic, 'Под подушкой спрятана пила');
    expect(restored.image, name);
    expect(CardImages.resolve(name), isNotNull,
        reason: 'файл картинки должен вернуться вместе с карточкой');
  });

  test('авто-бэкап остаётся лёгким — без картинок', () async {
    final light = await BackupService.exportJson(includeLibrary: false);
    expect(light.contains('cardImages'), false);
  });
}
