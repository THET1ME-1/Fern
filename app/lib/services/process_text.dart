import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../analyze/analyze_screen.dart';
import '../l10n/locale_controller.dart';
import '../l10n/strings.dart';
import '../study/word_lookup_sheet.dart';
import '../video/add_target.dart';
import 'deck_repository.dart';
import 'pos.dart';

/// Текст, выделенный в ЧУЖОМ приложении и отданный Fern через системное меню
/// выделения (Android `ACTION_PROCESS_TEXT`).
///
/// Зачем: самый частый способ встретить незнакомое слово — увидеть его в
/// переписке или в браузере. «Поделиться» для этого слишком длинный путь, а
/// пункт рядом с «Копировать» стоит одного тапа.
class ProcessText {
  const ProcessText._();

  static const MethodChannel _channel = MethodChannel('fern/process_text');

  static bool _started = false;

  static bool get _supported => !kIsWeb && Platform.isAndroid;

  /// Слов не больше — открываем лист перевода, дальше — экран разбора.
  /// Одно-два слова человек выделяет, чтобы понять слово; предложение целиком —
  /// чтобы понять предложение.
  static const int _wordLimit = 3;

  /// Запускает приём. Зовётся из корневого экрана один раз, рядом с
  /// [ShareImport.start].
  static void start(BuildContext context) {
    if (_started || !_supported) return;
    _started = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onText' && context.mounted) {
        final text = '${call.arguments}'.trim();
        if (text.isNotEmpty) await route(context, text);
      }
      return null;
    });
    // Приложение могли ЗАПУСТИТЬ этим интентом: тогда текст ждёт на нативной
    // стороне и события не будет.
    _channel.invokeMethod<String>('take').then((text) {
      final t = text?.trim() ?? '';
      if (t.isEmpty || !context.mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) route(context, t);
      });
    }).catchError((Object e) {
      debugPrint('ProcessText: $e');
      return null;
    });
  }

  @visibleForTesting
  static void resetForTest() => _started = false;

  /// Сколько слов в тексте (для выбора пути).
  @visibleForTesting
  static int wordCount(String text) =>
      text.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;

  /// Куда вести выделенный текст: короткое — в лист перевода, длинное — в
  /// разбор.
  @visibleForTesting
  static bool looksLikeWord(String text) => wordCount(text) <= _wordLimit;

  /// Открывает подходящий экран для выделенного текста.
  static Future<void> route(BuildContext context, String text) async {
    if (!looksLikeWord(text)) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => AnalyzeScreen(initialText: text)),
      );
      return;
    }
    final lang = await DeckRepository.instance.selectedLanguageCode() ?? 'en';
    if (!context.mounted) return;
    final known =
        DeckRepository.instance.hasWordInLanguage(text.trim(), lang);
    await showWordLookup(
      context,
      word: text.trim(),
      sentence: '',
      sourceLang: lang,
      targetLang: LocaleController.instance.code,
      alreadyKnown: known,
      onAdd: (back, example, pos) async {
        final deck = await VideoDeckTarget.resolveInSourcePack(
            context, lang, tr('selection_source_pack'));
        if (deck == null) return LookupAddResult.cancelled;
        final ok = await VideoDeckTarget.addWord(
          deck,
          front: text.trim(),
          back: back,
          example: example,
          pos: PosDetect.detect(text.trim(),
              dictPos: pos, languageCode: lang),
        );
        return ok ? LookupAddResult.added : LookupAddResult.duplicate;
      },
    );
  }
}

