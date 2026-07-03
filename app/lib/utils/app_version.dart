import 'package:flutter/services.dart' show rootBundle;

/// Версия приложения, прочитанная НАПРЯМУЮ из `pubspec.yaml` (он добавлен в
/// assets). Так показываемая версия всегда совпадает с yaml — без хардкода.
///
/// Возвращает, например, `1.2.0` или `1.2.0 (3)` для `version: 1.2.0+3`.
Future<String> appVersionFromPubspec() async {
  final v = await _rawVersion();
  if (v.isEmpty) return '';
  final plus = v.indexOf('+');
  if (plus == -1) return v;
  final name = v.substring(0, plus);
  final build = v.substring(plus + 1);
  return build.isEmpty ? name : '$name ($build)';
}

/// Только имя версии без билда: `1.2.0+3` → `1.2.0`. Для сравнения при проверке
/// обновлений.
Future<String> appVersionName() async {
  final v = await _rawVersion();
  final plus = v.indexOf('+');
  return plus == -1 ? v : v.substring(0, plus);
}

Future<String> _rawVersion() async {
  try {
    final yaml = await rootBundle.loadString('pubspec.yaml');
    for (final raw in yaml.split('\n')) {
      final line = raw.trim();
      if (!line.startsWith('version:')) continue;
      var v = line.substring('version:'.length).trim();
      final hash = v.indexOf('#');
      if (hash != -1) v = v.substring(0, hash).trim();
      return v.replaceAll('"', '').replaceAll("'", '').trim();
    }
  } catch (_) {/* вернём пусто — экран покажет запасной вариант */}
  return '';
}
