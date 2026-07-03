import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';

/// Офлайн-перевод (Google ML Kit, on-device). Помощник при создании карточек:
/// заполняет перевод по введённому слову. Модели языков скачиваются на
/// устройство при первом использовании.
///
/// Только Android/iOS; на десктопе/в тестах методы возвращают null.
class TranslationService {
  TranslationService._();

  static bool get supported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  static final OnDeviceTranslatorModelManager _models =
      OnDeviceTranslatorModelManager();

  /// Можно ли перевести с [fromCode] на [toCode] (оба поддержаны и различны).
  static bool canTranslate(String fromCode, String toCode) {
    if (!supported || fromCode == toCode) return false;
    return BCP47Code.fromRawValue(fromCode) != null &&
        BCP47Code.fromRawValue(toCode) != null;
  }

  /// Скачаны ли уже обе языковые модели (чтобы подсказать про загрузку).
  static Future<bool> modelsReady(String fromCode, String toCode) async {
    if (!supported) return false;
    final from = BCP47Code.fromRawValue(fromCode);
    final to = BCP47Code.fromRawValue(toCode);
    if (from == null || to == null) return false;
    try {
      return await _models.isModelDownloaded(from.bcpCode) &&
          await _models.isModelDownloaded(to.bcpCode);
    } catch (_) {
      return false;
    }
  }

  /// Переводит [text] с [fromCode] на [toCode]. Докачивает модели при
  /// необходимости. Возвращает перевод или null при ошибке/недоступности.
  static Future<String?> translate(
    String text,
    String fromCode,
    String toCode,
  ) async {
    final t = text.trim();
    if (t.isEmpty || !supported) return null;
    final from = BCP47Code.fromRawValue(fromCode);
    final to = BCP47Code.fromRawValue(toCode);
    if (from == null || to == null || from == to) return null;
    OnDeviceTranslator? translator;
    try {
      for (final lang in [from, to]) {
        if (!await _models.isModelDownloaded(lang.bcpCode)) {
          await _models.downloadModel(lang.bcpCode);
        }
      }
      translator = OnDeviceTranslator(sourceLanguage: from, targetLanguage: to);
      final result = (await translator.translateText(t)).trim();
      return result.isEmpty ? null : result;
    } catch (e) {
      debugPrint('translate failed: $e');
      return null;
    } finally {
      await translator?.close();
    }
  }
}
