import 'dart:async';

import '../translation_service.dart';
import 'translation_provider.dart';

/// Провайдер на базе Google ML Kit on-device — дефолтный **лёгкий офлайн**
/// вариант и последнее звено fallback-цепочки. Обёртка над существующим
/// [TranslationService].
///
/// Модели языков (десятки мегабайт) не качаются посреди перевода: пока их нет,
/// звено пропускается, ход переходит онлайн-провайдеру, а загрузка идёт фоном.
class MlKitProvider extends TranslationProvider {
  @override
  String get id => 'mlkit';

  @override
  String get name => 'ML Kit';

  @override
  bool get isOffline => true;

  @override
  String get kindLabel => 'offline';

  @override
  bool supportsPair(String from, String to) =>
      TranslationService.canTranslate(from, to);

  @override
  Future<bool> isReady(String from, String to) =>
      TranslationService.modelsReady(from, to);

  @override
  Future<TransResult?> translate(
    String text,
    String from,
    String to, {
    String? context,
  }) async {
    if (!await TranslationService.modelsReady(from, to)) {
      unawaited(TranslationService.ensureModels(from, to));
      return null;
    }
    final r = await TranslationService.translate(text, from, to);
    if (r == null || r.trim().isEmpty) return null;
    return TransResult(primary: r.trim(), sourceId: id);
  }
}
