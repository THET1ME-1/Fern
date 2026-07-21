import 'package:flutter_test/flutter_test.dart';

import 'package:fern/services/update_service.dart';

/// Релизы на GitHub выкладываются сплитом по ABI, и апдейтер обязан взять файл
/// ровно под свою архитектуру: чужой APK система откажется ставить, а человек
/// увидит только «установка не удалась».
List<Map<String, String>> _splitRelease(String version) => [
      for (final abi in ['arm64-v8a', 'armeabi-v7a', 'x86_64'])
        {
          'name': 'Fern-$version-$abi.apk',
          'browser_download_url': 'https://example/Fern-$version-$abi.apk',
        },
    ];

void main() {
  test('каждой архитектуре достаётся её файл', () {
    final assets = _splitRelease('1.16.0');
    for (final abi in ['arm64-v8a', 'armeabi-v7a', 'x86_64']) {
      expect(
        UpdateService.pickApkUrl(assets, deviceAbi: abi),
        'https://example/Fern-1.16.0-$abi.apk',
        reason: 'устройство $abi должно получить свой APK',
      );
    }
  });

  // «x86» — подстрока «x86_64»: по простому contains тридцатидвухбитному
  // устройству доставался шестидесятичетырёхбитный файл.
  test('32-битному x86 не подсовывается x86_64', () {
    final picked = UpdateService.pickApkUrl(
      _splitRelease('1.16.0'),
      deviceAbi: 'x86',
    );
    expect(picked, isNot(contains('x86_64')));
  });

  test('единый релиз без ABI-меток подходит всем', () {
    final assets = [
      {
        'name': 'Fern-1.9.0.apk',
        'browser_download_url': 'https://example/Fern-1.9.0.apk',
      },
    ];
    expect(
      UpdateService.pickApkUrl(assets, deviceAbi: 'arm64-v8a'),
      'https://example/Fern-1.9.0.apk',
    );
  });

  test('универсальный APK берётся, когда своего ABI в релизе нет', () {
    final assets = [
      ..._splitRelease('1.16.0').where((a) => !a['name']!.contains('arm64')),
      {
        'name': 'Fern-1.16.0-universal.apk',
        'browser_download_url': 'https://example/universal.apk',
      },
    ];
    expect(
      UpdateService.pickApkUrl(assets, deviceAbi: 'arm64-v8a'),
      'https://example/universal.apk',
    );
  });

  test('не-APK вложения пропускаются', () {
    final assets = [
      {
        'name': 'checksums.txt',
        'browser_download_url': 'https://example/checksums.txt',
      },
      {
        'name': 'Fern-1.16.0-arm64-v8a.apk',
        'browser_download_url': 'https://example/apk',
      },
    ];
    expect(
      UpdateService.pickApkUrl(assets, deviceAbi: 'arm64-v8a'),
      'https://example/apk',
    );
  });
}
