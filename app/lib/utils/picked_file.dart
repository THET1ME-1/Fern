import 'package:file_picker/file_picker.dart';

/// Путь выбранного файла или `null`.
///
/// Отдельная функция, потому что `result.files.single` бросает `StateError` на
/// пустом списке: на части устройств отмена выбора возвращает не `null`, а
/// результат без файлов, и импорт падал вместо тихого выхода.
String? pickedPath(FilePickerResult? result) {
  final files = result?.files ?? const <PlatformFile>[];
  if (files.isEmpty) return null;
  return files.first.path;
}
