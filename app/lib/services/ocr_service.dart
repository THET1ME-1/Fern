import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// Распознавание текста с фото (офлайн, Google ML Kit). В сборку входит только
/// распознаватель ЛАТИНИЦЫ, поэтому языки на других алфавитах (кириллица,
/// арабица, CJK, деванагари…) движком не читаются — это честно проверяется через
/// [supports]. Всё в try/catch + гейт платформы: на десктопе/в тестах молча
/// возвращает пусто, а не падает.
class OcrService {
  OcrService._();
  static final OcrService instance = OcrService._();

  static bool get _platformOk =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// Языки на НЕ-латинских алфавитах — их бандленный латинский распознаватель
  /// ML Kit не читает. (CJK/деванагари тоже требуют своих моделей, которых в
  /// сборке нет; кириллицу/арабицу ML Kit не поддерживает вовсе.)
  static const Set<String> _nonLatin = {
    // кириллица
    'ru', 'uk', 'be', 'bg', 'sr', 'mk', 'kk', 'ky', 'tg', 'mn', 'tt', 'ba',
    // греческий
    'el',
    // арабица / иврит
    'ar', 'fa', 'ur', 'ps', 'sd', 'he', 'yi',
    // CJK (нет модели в сборке)
    'zh', 'ja', 'ko',
    // индийские / SEA
    'hi', 'bn', 'ta', 'te', 'mr', 'ne', 'pa', 'gu', 'kn', 'ml', 'si', 'or',
    'th', 'lo', 'km', 'my',
    // кавказ / прочее
    'ka', 'hy', 'am',
  };

  /// Поддерживает ли офлайн-распознавание алфавит языка [lang] (латиница).
  static bool supports(String lang) =>
      !_nonLatin.contains(lang.split('-').first.toLowerCase());

  /// Распознаёт текст с изображения [imagePath] для языка [languageCode].
  /// Пустая строка — если алфавит не поддерживается, платформа не та или текст
  /// не распознан. Проверяй [supports] заранее, чтобы показать понятное
  /// сообщение вместо пустого результата.
  Future<String> recognize(String imagePath, String languageCode) async {
    if (!_platformOk || !supports(languageCode)) return '';
    TextRecognizer? recognizer;
    try {
      recognizer = TextRecognizer(script: TextRecognitionScript.latin);
      final result =
          await recognizer.processImage(InputImage.fromFilePath(imagePath));
      return result.text;
    } catch (e) {
      debugPrint('OCR failed: $e');
      return '';
    } finally {
      await recognizer?.close();
    }
  }
}
