import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:fern/models/deck.dart';
import 'package:fern/models/word_card.dart';
import 'package:fern/services/backup_service.dart';
import 'package:fern/services/deck_repository.dart';
import 'package:fern/services/source_library.dart';

import 'test_helpers.dart';

/// Фейковый path_provider — SourceLibrary пишет/читает контент во временную папку.
class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  final String dir;
  _FakePathProvider(this.dir);
  @override
  Future<String?> getApplicationDocumentsPath() async => dir;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final repo = DeckRepository.instance;

  setUp(resetStorage);

  Deck deckOf(String id, {String name = 'D'}) => Deck(
        id: id,
        languageCode: 'en',
        name: name,
        colorValue: 1,
        shapeIndex: 0,
        createdAt: 1,
      );

  test('экспорт → импорт (замена) восстанавливает карты, FSRS, журнал, цель, '
      'рекорды', () async {
    await repo.init();
    await repo.upsertDeck(deckOf('d1'));
    await repo.upsertCard(WordCard(
      id: 'c1',
      deckId: 'd1',
      front: 'sun',
      back: 'солнце',
      review: ReviewState(stability: 9.0, reps: 4),
    ));
    await repo.setDailyGoal(42);
    await repo.recordMatchMillis('d1', 5000);
    await repo.logSession(reviews: 3, correct: 2);

    final json = await BackupService.exportJson();

    // Полностью чистое устройство.
    await resetStorage();
    await repo.init();
    expect(await repo.loadCards(), isEmpty);

    await BackupService.restore(json, merge: false);

    final cards = await repo.cardsForDeck('d1');
    expect(cards.length, 1);
    expect(cards.first.review.reps, 4);
    expect(cards.first.review.stability, 9.0);
    expect(await repo.dailyGoal(), 42);
    expect(repo.bestMatchMillis('d1'), 5000);
    expect(repo.reviewLogSync.totalReviews, 3);
  });

  test('импорт (слияние) добавляет новое и НЕ трогает существующий прогресс',
      () async {
    await repo.init();
    await repo.upsertDeck(deckOf('d1', name: 'Мой'));
    await repo.upsertCard(WordCard(
      id: 'shared',
      deckId: 'd1',
      front: 'a',
      back: 'б',
      review: ReviewState(reps: 5),
    ));

    final snapshot = jsonEncode({
      'decks': [
        deckOf('d1', name: 'ЧУЖОЙ').toJson(), // тот же id — не должен перетереть
        deckOf('d2', name: 'Новая').toJson(),
      ],
      'cards': [
        // shared с нулевым прогрессом — существующий (reps=5) должен выиграть.
        WordCard(id: 'shared', deckId: 'd1', front: 'a', back: 'б').toJson(),
        WordCard(id: 'fresh', deckId: 'd2', front: 'c', back: 'д').toJson(),
      ],
    });

    await repo.importJson(snapshot, merge: true);

    final decks = await repo.loadDecks();
    expect(decks.where((d) => d.id == 'd1').length, 1);
    expect(decks.firstWhere((d) => d.id == 'd1').name, 'Мой',
        reason: 'существующая колода не перезаписывается при слиянии');
    expect(decks.where((d) => d.id == 'd2').length, 1,
        reason: 'новая колода добавлена');

    final cards = await repo.loadCards();
    expect(cards.firstWhere((c) => c.id == 'shared').review.reps, 5,
        reason: 'прогресс существующей карты сохранён');
    expect(cards.where((c) => c.id == 'fresh').length, 1,
        reason: 'новая карта добавлена');
  });

  test('бэкап включает книгу библиотеки и восстанавливает её текст', () async {
    final tmp = Directory.systemTemp.createTempSync('fern_backup_lib');
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);
    addTearDown(() => tmp.deleteSync(recursive: true));
    await repo.init();

    const text = 'The cat sat on the mat. The end.';
    final id = await SourceLibrary.instance.saveBook(
      title: 'Тест',
      languageCode: 'en',
      format: 'txt',
      text: text,
    );
    expect(id, isNotNull);

    final json = await BackupService.exportJson(includeLibrary: true);

    // Удалили книгу — контента больше нет.
    await SourceLibrary.instance.delete(id!);
    expect(await SourceLibrary.instance.loadBookText(id), isNull);

    // Восстановление возвращает и метаданные, и текст.
    await BackupService.restore(json, merge: false);
    final sources = await SourceLibrary.instance.list();
    expect(sources.where((s) => s.id == id).length, 1);
    expect(await SourceLibrary.instance.loadBookText(id), text);
  });
}
