import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:fern/models/word_card.dart';
import 'package:fern/services/reading_horizon.dart';
import 'package:fern/services/source_library.dart';
import 'package:fern/study/study_models.dart';

import 'test_helpers.dart';

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  final String dir;
  _FakePathProvider(this.dir);
  @override
  Future<String?> getApplicationDocumentsPath() async => dir;
}

WordCard _new(String id, String front) =>
    WordCard(id: id, deckId: 'd1', front: front, back: 'перевод');

WordCard _due(
  String id,
  String front, {
  required double stability,
  required int elapsedDays,
}) {
  final at = DateTime.now().subtract(Duration(days: elapsedDays));
  return WordCard(
    id: id,
    deckId: 'd1',
    front: front,
    back: 'перевод',
    review: ReviewState(
      stability: stability,
      difficulty: 5,
      state: FsrsState.review,
      reps: 3,
      lastReview: at,
      due: at.add(Duration(days: stability.round())),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;

  setUp(() async {
    await resetStorage();
    ReadingHorizon.resetCache();
    tmp = Directory.systemTemp.createTempSync('fern_horizon');
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('горизонт собирает слова со следующих страниц', () async {
    final library = SourceLibrary.instance;
    final id = await library.saveBook(
      title: 'Книга',
      text: List.generate(10, (i) => 'paragraph $i with lantern and river')
          .join('\n'),
      languageCode: 'en',
      format: 'txt',
    );
    expect(id, isNotNull);
    await library.setBookPosition(id!, 1);

    final stems = await ReadingHorizon.upcoming('en');
    expect(stems, contains('lantern'));
    expect(stems, contains('river'));
  });

  test('книга на другом языке в горизонт не идёт', () async {
    final library = SourceLibrary.instance;
    final id = await library.saveBook(
      title: 'Libro',
      text: 'la linterna junto al rio\n' * 5,
      languageCode: 'es',
      format: 'txt',
    );
    await library.setBookPosition(id!, 1);
    expect(await ReadingHorizon.upcoming('en'), isEmpty);
  });

  test('без открытых книг горизонт пуст', () async {
    expect(await ReadingHorizon.upcoming('en'), isEmpty);
  });

  group('Влияние горизонта на сессию', () {
    test('новые слова из книги вводятся первыми', () {
      final builder = SessionBuilder()
        ..setReadingHorizon({'lantern'}, 'en');
      final queue = builder.build(
        StudyMode.flashcards,
        [_new('c1', 'table'), _new('c2', 'lantern'), _new('c3', 'window')],
        DateTime.now(),
        newAllowed: 1,
      );
      expect(queue.single.card.front, 'lantern');
    });

    test('без горизонта порядок новых прежний', () {
      final queue = SessionBuilder().build(
        StudyMode.flashcards,
        [_new('c1', 'table'), _new('c2', 'lantern')],
        DateTime.now(),
        newAllowed: 1,
      );
      expect(queue.single.card.front, 'table');
    });

    test('повтор из книги обгоняет равного по срочности', () {
      final builder = SessionBuilder()..setReadingHorizon({'lantern'}, 'en');
      final queue = builder.build(
        StudyMode.flashcards,
        [
          _due('c1', 'table', stability: 10, elapsedDays: 20),
          _due('c2', 'lantern', stability: 10, elapsedDays: 20),
        ],
        DateTime.now(),
      );
      expect(queue.first.card.front, 'lantern');
    });

    test('горячее к забыванию слово горизонт не вытесняет', () {
      final builder = SessionBuilder()..setReadingHorizon({'lantern'}, 'en');
      final queue = builder.build(
        StudyMode.flashcards,
        [
          // Это на грани забывания — важнее удачного совпадения с книгой.
          _due('c1', 'table', stability: 10, elapsedDays: 100),
          // А это ещё крепко держится, просто срок подошёл.
          _due('c2', 'lantern', stability: 10, elapsedDays: 11),
        ],
        DateTime.now(),
      );
      expect(queue.first.card.front, 'table');
    });
  });
}
