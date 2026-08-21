import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Google Play запрещает READ_MEDIA_IMAGES/READ_MEDIA_VIDEO там, где хватает
/// системного «Выбора фото» (правило «Фото и видео»). В Fern их не просит ни
/// одна кнопка — разрешения приезжают транзитивно из манифестов плагинов и
/// вырезаются в android/app/src/main/AndroidManifest.xml через
/// tools:node="remove".
///
/// Страж следит именно за корнем беды: обходит манифесты всех зависимостей и
/// падает, как только новый (или обновлённый) плагин принесёт медиа-разрешение,
/// которое мы не вырезали. Проверка строки в своём манифесте от такого не
/// спасает — плагин добавляет разрешение молча, а узнаём мы об этом письмом с
/// проверки.
void main() {
  const mediaPermissions = <String>{
    'android.permission.READ_MEDIA_IMAGES',
    'android.permission.READ_MEDIA_VIDEO',
    'android.permission.READ_MEDIA_AUDIO',
  };

  final manifestFile = File('android/app/src/main/AndroidManifest.xml');
  final manifest = manifestFile.readAsStringSync();

  final declared = RegExp(
    r'<uses-permission\b[^>]*?android:name="([^"]+)"[^>]*?>',
    dotAll: true,
  ).allMatches(manifest);

  final removed = <String>{};
  final kept = <String>{};
  for (final m in declared) {
    (m.group(0)!.contains('tools:node="remove"') ? removed : kept)
        .add(m.group(1)!);
  }

  test('свой манифест не объявляет медиа-разрешения живьём', () {
    expect(
      kept.intersection(mediaPermissions),
      isEmpty,
      reason: 'READ_MEDIA_* можно только вырезать (tools:node="remove"), '
          'просить их приложению нечем и незачем',
    );
  });

  test('медиа-разрешения плагинов вырезаны из итогового манифеста', () {
    final cache = _pubCache();
    if (cache == null) {
      markTestSkipped('кэш pub не найден — проверять манифесты плагинов негде');
      return;
    }

    final offenders = <String, Set<String>>{};
    for (final entry in _hostedPackages().entries) {
      final pluginManifest = File(
        '${cache.path}/hosted/pub.dev/${entry.key}-${entry.value}'
        '/android/src/main/AndroidManifest.xml',
      );
      if (!pluginManifest.existsSync()) continue;

      final perms = RegExp(r'android:name="([^"]+)"')
          .allMatches(pluginManifest.readAsStringSync())
          .map((m) => m.group(1)!)
          .toSet()
          .intersection(mediaPermissions)
          .difference(removed);
      if (perms.isNotEmpty) offenders['${entry.key}-${entry.value}'] = perms;
    }

    expect(
      offenders,
      isEmpty,
      reason: 'плагин приносит медиа-разрешение, которого нет в списке '
          'tools:node="remove" — Play отклонит сборку по правилу «Фото и видео»',
    );
  });
}

Directory? _pubCache() {
  final fromEnv = Platform.environment['PUB_CACHE'];
  final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
  for (final path in [fromEnv, if (home != null) '$home/.pub-cache']) {
    if (path == null) continue;
    final dir = Directory(path);
    if (dir.existsSync()) return dir;
  }
  return null;
}

/// Пакеты из pubspec.lock вместе с версиями: без разбора YAML-библиотекой,
/// формат lock-файла стабилен и плоский.
Map<String, String> _hostedPackages() {
  final lines = File('pubspec.lock').readAsLinesSync();
  final packages = <String, String>{};
  String? current;
  for (final line in lines) {
    final name = RegExp(r'^  ([a-z0-9_]+):$').firstMatch(line);
    if (name != null) {
      current = name.group(1);
      continue;
    }
    final version = RegExp(r'^    version: "(.+)"$').firstMatch(line);
    if (version != null && current != null) {
      packages[current] = version.group(1)!;
      current = null;
    }
  }
  return packages;
}
