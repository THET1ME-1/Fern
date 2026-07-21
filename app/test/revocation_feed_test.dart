import 'package:flutter_test/flutter_test.dart';
import 'package:fern/services/revocation_feed.dart';

import 'test_helpers.dart';

/// Список отозванных лицензий, лежащий файлом в репозитории.
///
/// Вшитый в код список едет только с релизом: утёкший ключ работал бы месяцами.
/// Файл на GitHub — тот же адрес, откуда качается само приложение, никакой
/// серверной части. Нет сети — остаётся вшитый список, офлайн не страдает.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await resetStorage();
    RevocationFeed.debugNow = null;
  });

  tearDown(() => RevocationFeed.debugNow = null);

  group('разбор ответа', () {
    test('номера читаются', () {
      expect(RevocationFeed.parse('{"revoked": [7, 42, 1001]}'), {7, 42, 1001});
    });

    test('лишние поля не мешают', () {
      expect(
        RevocationFeed.parse('{"updated": "2026-07-21", "revoked": [5]}'),
        {5},
      );
    });

    test('пустой список — пустое множество, а не отказ', () {
      expect(RevocationFeed.parse('{"revoked": []}'), isEmpty);
    });

    test('мусор и обрезанный ответ ничего не отзывают', () {
      for (final junk in ['', 'not json', '{"revoked": 7}', '{"revoked": ["a"]}',
          '<html>404</html>', '{"rev']) {
        expect(RevocationFeed.parse(junk), isNull, reason: junk);
      }
    });

    test('чужие типы внутри списка отбрасываются целиком', () {
      // Половинчатый разбор опаснее отказа: пропущенный номер значит
      // работающий утёкший ключ.
      expect(RevocationFeed.parse('{"revoked": [1, "2", 3]}'), isNull);
    });
  });

  group('когда ходить за списком', () {
    test('в первый раз — сразу', () async {
      expect(await RevocationFeed.isDue(), isTrue);
    });

    test('сразу после удачной загрузки — нет', () async {
      RevocationFeed.debugNow = DateTime.utc(2026, 7, 21);
      await RevocationFeed.remember({7});
      expect(await RevocationFeed.isDue(), isFalse);
    });

    test('через трое суток — снова пора', () async {
      RevocationFeed.debugNow = DateTime.utc(2026, 7, 21);
      await RevocationFeed.remember({7});
      RevocationFeed.debugNow = DateTime.utc(2026, 7, 24, 1);
      expect(await RevocationFeed.isDue(), isTrue);
    });
  });

  group('память между запусками', () {
    test('загруженный список переживает перезапуск', () async {
      await RevocationFeed.remember({7, 42});
      expect(await RevocationFeed.stored(), {7, 42});
    });

    test('без загрузок список пуст', () async {
      expect(await RevocationFeed.stored(), isEmpty);
    });
  });
}
