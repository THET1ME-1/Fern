import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';

/// Офлайн-перевод (Google ML Kit, on-device). Помощник при создании карточек:
/// заполняет перевод по введённому слову. Модели языков скачиваются на
/// устройство отдельно ([ensureModels]) — сам перевод их не ждёт.
///
/// Только Android/iOS; на десктопе/в тестах методы возвращают null.
class TranslationService {
  TranslationService._();

  static bool get supported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  static final OnDeviceTranslatorModelManager _models =
      OnDeviceTranslatorModelManager();

  /// Языки, чьи модели качаются прямо сейчас: повторный промах не плодит
  /// вторую загрузку того же файла.
  static final Set<String> _downloading = <String>{};

  /// Сколько ждём загрузку модели, прежде чем считать её несостоявшейся.
  /// Загрузка идёт фоном, поэтому потолок щедрый — он только освобождает флаг.
  static const Duration _downloadTimeout = Duration(minutes: 5);

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

  /// Докачивает недостающие модели пары. Зовётся В ФОНЕ — перевод её не ждёт.
  ///
  /// `isWifiRequired: false` намеренно: с дефолтом пакета (`true`) на мобильном
  /// интернете ML Kit ставит загрузку в очередь до появления Wi-Fi и НЕ
  /// завершает Task ни успехом, ни ошибкой — вызов висел вечно.
  static Future<bool> ensureModels(String fromCode, String toCode) async {
    if (!supported) return false;
    final codes = <String>[];
    for (final raw in [fromCode, toCode]) {
      final code = BCP47Code.fromRawValue(raw);
      if (code == null) return false;
      codes.add(code.bcpCode);
    }
    var ok = true;
    for (final code in codes) {
      if (_downloading.contains(code)) {
        ok = false;
        continue;
      }
      _downloading.add(code);
      try {
        if (!await _models.isModelDownloaded(code)) {
          await _models
              .downloadModel(code, isWifiRequired: false)
              .timeout(_downloadTimeout);
        }
      } catch (e) {
        debugPrint('model download failed ($code): $e');
        ok = false;
      } finally {
        _downloading.remove(code);
      }
    }
    return ok;
  }

  /// Переводит [text] с [fromCode] на [toCode] на УЖЕ скачанных моделях.
  /// Модели нет — возвращает null сразу, не задерживая цепочку провайдеров.
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
        if (!await _models.isModelDownloaded(lang.bcpCode)) return null;
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
