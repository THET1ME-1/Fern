import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:fern/services/construction_stats.dart';
import 'package:fern/services/deck_repository.dart';
import 'package:fern/services/source_library.dart';

import 'test_helpers.dart';

/// Библиотека держит тексты файлами — в тестах подсовываем временный каталог.
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
    final dir = await Directory.systemTemp.createTemp('fern_stats_');
    PathProviderPlatform.instance = _FakePathProvider(dir.path);
    ConstructionStats.invalidate();
  });

  test('считает встречи конструкций по источникам библиотеки', () async {
    await SourceLibrary.instance.saveBook(
      title: 'Первый',
      languageCode: 'en',
      format: 'txt',
      text: 'She has written a letter. The house was built in 1920.',
    );
    await SourceLibrary.instance.saveBook(
      title: 'Второй',
      languageCode: 'en',
      format: 'txt',
      text: 'He has finished the work.',
    );

    final stats = await ConstructionStats.forLanguage('en', refresh: true);

    expect(stats['present_perfect']?.hits, 2);
    expect(stats['present_perfect']?.sources, 2);
    expect(stats['passive_past']?.hits, 1);
    expect(stats['passive_past']?.sources, 1);
  });

  test('язык без разбора грамматики отдаёт пусто', () async {
    await SourceLibrary.instance.saveBook(
      title: 'Buch',
      languageCode: 'de',
      format: 'txt',
      text: 'Ich habe ein Buch gelesen.',
    );
    final stats = await ConstructionStats.forLanguage('de', refresh: true);
    expect(stats, isEmpty);
  });
}

