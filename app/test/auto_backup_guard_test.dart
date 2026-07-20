import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:fern/models/deck.dart';
import 'package:fern/models/word_card.dart';
import 'package:fern/services/backup_service.dart';
import 'package:fern/services/deck_repository.dart';

import 'test_helpers.dart';

/// Фейковый path_provider — снимок пишется во временную папку.
class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  final String dir;
  _FakePathProvider(this.dir);
  @override
  Future<String?> getApplicationDocumentsPath() async => dir;
}

/// Авто-бэкап — последняя линия обороны, и переписывает он единственный файл.
///
/// Аварийный экран предлагает «Начать заново» (база уезжает в карантин, на её
/// месте пустая) и «Восстановить из копии» — из этого самого файла. Порядок в
/// `startFern` таков, что после карантина запуск доходит до конца и дёргает
/// `autoBackupIfDue()`. Прошли сутки с прошлого снимка (а они прошли, раз
/// приложение перед этим падало) — и поверх страховки ложится снимок пустой
/// базы. Обе копии кончаются за один запуск.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;

  setUp(() async {
    await resetStorage();
    tmp = await Directory.systemTemp.createTemp('fern_autobackup');
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);
    addTearDown(() async {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });
  });

  final deck = Deck(
    id: 'd1',
    languageCode: 'en',
    name: 'D',
    colorValue: 0xFF2E7D5B,
    shapeIndex: 0,
    createdAt: 1,
  );

  Future<int> cardsInBackup() async {
    final path = await BackupService.autoBackupPath();
    if (path == null || !await File(path).exists()) return -1;
    final raw = jsonDecode(await File(path).readAsString());
    final cards = (raw as Map)['cards'];
    return cards is List ? cards.length : -1;
  }

  test('пустая база не затирает непустой снимок', () async {
    final repo = DeckRepository.instance;
    await repo.init();
    await repo.upsertDeck(deck);
    await repo.upsertCard(
        WordCard(id: 'c1', deckId: 'd1', front: 'cat', back: 'кот'));

    await BackupService.autoBackupIfDue();
    expect(await cardsInBackup(), 1, reason: 'страховка снята');

    // Аварийный экран: база уехала в карантин, на её месте пустая.
    await repo.recoverFromCorruptedDatabase();
    // Сутки прошли — иначе бы авто-бэкап и не сработал.
    await repo.setLastAutoBackupMs(
        DateTime.now().millisecondsSinceEpoch - const Duration(hours: 48).inMilliseconds);

    await BackupService.autoBackupIfDue();

    expect(await cardsInBackup(), 1,
        reason: 'снимок пустой базы не имеет права затирать страховку');
  });

  test('обрыв записи не оставляет битый снимок', () async {
    final repo = DeckRepository.instance;
    await repo.init();
    await repo.upsertDeck(deck);
    await repo.upsertCard(
        WordCard(id: 'c1', deckId: 'd1', front: 'cat', back: 'кот'));
    await BackupService.autoBackupIfDue();

    final path = (await BackupService.autoBackupPath())!;
    final dir = File(path).parent;
    final leftovers = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.contains('backup_auto') && f.path != path)
        .toList();
    expect(leftovers, isEmpty,
        reason: 'запись идёт через временный файл и убирает его за собой');

    // Файл на месте и читается целиком.
    expect(() => jsonDecode(File(path).readAsStringSync()), returnsNormally);
  });
}
