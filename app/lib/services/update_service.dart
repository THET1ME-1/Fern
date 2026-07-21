import 'dart:convert';
import 'dart:ffi' show Abi;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Данные о доступном обновлении с GitHub Releases.
class UpdateInfo {
  final String version; // тег без «v», напр. «1.2.0»
  final String notes; // тело релиза (описание)
  final String? apkUrl; // прямая ссылка на .apk-ассет (или null)
  final String releaseUrl; // страница релиза на GitHub

  const UpdateInfo({
    required this.version,
    required this.notes,
    required this.apkUrl,
    required this.releaseUrl,
  });
}

/// Итог проверки обновлений.
///
/// «Обновлений нет» и «проверить не удалось» — разные вещи: раньше оба случая
/// возвращали null, и человек без интернета получал бодрое «установлена
/// последняя версия», после чего не обновлялся никогда.
class UpdateCheck {
  final UpdateInfo? info;
  final bool failed;

  const UpdateCheck.upToDate()
      : info = null,
        failed = false;
  const UpdateCheck.available(UpdateInfo this.info) : failed = false;
  const UpdateCheck.failed()
      : info = null,
        failed = true;

  bool get hasUpdate => info != null;
}

/// Проверка обновлений по последнему релизу на GitHub и загрузка APK для
/// установки (sideload-обновление, без магазинов). ДНК ScoreMaster.
class UpdateService {
  UpdateService._();

  // ОТДЕЛЬНЫЙ ПУБЛИЧНЫЙ репозиторий-канал релизов: в приватном репо ссылки на
  // APK-ассеты требуют авторизации, поэтому авто-скачивание не работало.
  static const String _owner = 'THET1ME-1';
  static const String _repo = 'Fern';

  static Uri get _latestReleaseUri =>
      Uri.parse('https://api.github.com/repos/$_owner/$_repo/releases/latest');

  /// Есть ли релиз новее [currentVersion]. Отдельно сообщает о неудачной
  /// проверке (нет сети, 403 от GitHub) — это не то же самое, что «всё свежее».
  static Future<UpdateCheck> checkForUpdate(String currentVersion) async {
    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 12);
      final request = await client.getUrl(_latestReleaseUri);
      // GitHub API требует User-Agent, иначе 403.
      request.headers.set(HttpHeaders.userAgentHeader, 'Fern-Updater');
      request.headers
          .set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
      final response = await request.close();
      if (response.statusCode != 200) {
        client.close();
        return const UpdateCheck.failed();
      }
      final body = await response.transform(utf8.decoder).join();
      client.close();

      final json = jsonDecode(body) as Map<String, dynamic>;
      final tag = (json['tag_name'] ?? '').toString();
      final latest = _normalize(tag);
      if (latest.isEmpty) return const UpdateCheck.failed();
      if (!_isNewer(latest, _normalize(currentVersion))) {
        return const UpdateCheck.upToDate();
      }

      final assets = json['assets'];
      final apkUrl = assets is List ? pickApkUrl(assets) : null;

      return UpdateCheck.available(
        UpdateInfo(
          version: latest,
          notes: (json['body'] ?? '').toString().trim(),
          apkUrl: (apkUrl != null && apkUrl.isNotEmpty) ? apkUrl : null,
          releaseUrl: (json['html_url'] ??
                  'https://github.com/$_owner/$_repo/releases/latest')
              .toString(),
        ),
      );
    } catch (_) {
      return const UpdateCheck.failed();
    }
  }

  /// Скачивает APK по ссылке во временный файл, дёргая [onProgress] (0..1).
  /// Возвращает путь к файлу или null при ошибке.
  static Future<String?> downloadApk(
    String url, {
    void Function(double progress)? onProgress,
  }) async {
    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 20);
      final request = await client.getUrl(Uri.parse(url));
      request.headers.set(HttpHeaders.userAgentHeader, 'Fern-Updater');
      final response = await request.close(); // редиректы следуются по умолчанию
      if (response.statusCode != 200) {
        client.close();
        return null;
      }

      // Внешняя app-папка надёжнее открывается системным установщиком; если
      // недоступна — временная.
      final dir =
          await getExternalStorageDirectory() ?? await getTemporaryDirectory();
      final file = File('${dir.path}/fern_update.apk');
      if (await file.exists()) await file.delete();
      final sink = file.openWrite();

      final total = response.contentLength; // может быть -1
      var received = 0;
      await for (final chunk in response) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0 && onProgress != null) {
          onProgress((received / total).clamp(0.0, 1.0));
        }
      }
      await sink.flush();
      await sink.close();
      client.close();
      onProgress?.call(1.0);
      return file.path;
    } catch (_) {
      return null;
    }
  }

  /// ABI-метка текущего устройства для выбора нужного сплит-APK.
  static String _deviceAbi() {
    final abi = Abi.current();
    if (abi == Abi.androidArm64) return 'arm64-v8a';
    if (abi == Abi.androidArm) return 'armeabi-v7a';
    if (abi == Abi.androidX64) return 'x86_64';
    if (abi == Abi.androidIA32) return 'x86';
    return '';
  }

  static const List<String> _abiTokens = [
    'arm64-v8a',
    'armeabi-v7a',
    'x86_64',
    'x86',
  ];

  /// ABI-метка в имени файла, либо '' — универсальный APK.
  ///
  /// Берётся самая ДЛИННАЯ подходящая метка: `x86` — подстрока `x86_64`, и по
  /// простому `contains` тридцатидвухбитному устройству доставался
  /// шестидесятичетырёхбитный файл, который не встаёт.
  static String _assetAbi(String name) {
    var found = '';
    for (final token in _abiTokens) {
      if (name.contains(token) && token.length > found.length) found = token;
    }
    return found;
  }

  /// Выбирает APK-ассет под архитектуру устройства. Порядок предпочтения:
  /// точное совпадение ABI → универсальный (без ABI-метки) → первый попавшийся.
  /// Работает и со сплит-релизом (несколько APK), и со старым единым.
  @visibleForTesting
  static String? pickApkUrl(List assets, {String? deviceAbi}) {
    final abi = deviceAbi ?? _deviceAbi();
    String? abiMatch, universal, firstApk;
    for (final a in assets) {
      final name = (a['name'] ?? '').toString().toLowerCase();
      if (!name.endsWith('.apk')) continue;
      final url = (a['browser_download_url'] ?? '').toString();
      if (url.isEmpty) continue;
      firstApk ??= url;
      final assetAbi = _assetAbi(name);
      if (abi.isNotEmpty && assetAbi == abi) {
        abiMatch ??= url;
      } else if (assetAbi.isEmpty) {
        universal ??= url;
      }
    }
    return abiMatch ?? universal ?? firstApk;
  }

  /// «1.0.10» > «1.0.2» (числовое сравнение по компонентам).
  static bool _isNewer(String a, String b) {
    final pa = _parts(a);
    final pb = _parts(b);
    final n = pa.length > pb.length ? pa.length : pb.length;
    for (var i = 0; i < n; i++) {
      final x = i < pa.length ? pa[i] : 0;
      final y = i < pb.length ? pb[i] : 0;
      if (x != y) return x > y;
    }
    return false;
  }

  static List<int> _parts(String v) =>
      v.split('.').map((s) => int.tryParse(s.trim()) ?? 0).toList();

  /// Убираем ведущую «v»: «v1.2.0» → «1.2.0».
  static String _normalize(String v) {
    var s = v.trim();
    if (s.startsWith('v') || s.startsWith('V')) s = s.substring(1);
    return s;
  }
}
