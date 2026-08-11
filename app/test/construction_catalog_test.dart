import 'package:flutter_test/flutter_test.dart';

import 'package:fern/services/construction_catalog.dart';
import 'package:fern/services/constructions.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final catalog = ConstructionCatalog.instance;

  setUp(() => catalog.resetForTest());

  test('каталог английского читается из ассета', () async {
    await catalog.ensureLoaded('en');
    final all = catalog.all('en');
    expect(all.length, greaterThanOrEqualTo(20));
    expect(catalog.byCode('present_perfect', 'en')?.name, 'Present Perfect');
  });

  test('у каждого кода детектора есть описание', () async {
    await catalog.ensureLoaded('en');
    final missing = [
      for (final code in Constructions.knownCodes)
        if (catalog.byCode(code, 'en') == null) code,
    ];
    expect(missing, isEmpty,
        reason: 'код без объяснения выглядит на экране загадочной меткой');
  });

  test('объяснение есть на всех семи языках интерфейса', () async {
    await catalog.ensureLoaded('en');
    const langs = ['ru', 'en', 'de', 'fr', 'es', 'it', 'pt'];
    final gaps = <String>[];
    for (final rule in catalog.all('en')) {
      for (final lang in langs) {
        if (rule.hint(lang).trim().isEmpty) gaps.add('${rule.code}/$lang');
      }
      if (rule.examples.isEmpty) gaps.add('${rule.code}/примеры');
    }
    expect(gaps, isEmpty);
  });

  test('правила идут по возрастанию уровня', () async {
    await catalog.ensureLoaded('en');
    final levels = [
      for (final r in catalog.all('en')) ConstructionCatalog.levels.indexOf(r.level),
    ];
    final sorted = [...levels]..sort();
    expect(levels, sorted);
  });

  test('язык без каталога не роняет загрузку', () async {
    await catalog.ensureLoaded('zz');
    expect(catalog.all('zz'), isEmpty);
    expect(catalog.isLoaded('zz'), isTrue);
  });
}

