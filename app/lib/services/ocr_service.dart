import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// Распознавание текста с фото (офлайн, Google ML Kit). Скрипт выбирается по
/// изучаемому языку. Всё в try/catch + гейт платформы — на десктопе/в тестах
/// молча возвращает пусто, а не падает.
class OcrService {
  OcrService._();
  static final OcrService instance = OcrService._();

  static bool get _supported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// Скрипт распознавания. Сейчас в сборку входит только латиница (покрывает
  /// en/es/fr/de/it/pt/nl/pl/tr… и частично кириллицу). CJK/деванагари требуют
  /// отдельных зависимостей `text-recognition-<script>` — задел на будущее, пока
  /// возвращаем латиницу, чтобы не падать на отсутствующих классах.
  static TextRecognitionScript scriptFor(String lang) => TextRecognitionScript.latin;

  /// Распознаёт текст с изображения по пути [imagePath]. Пустая строка — если
  /// не распозналось или платформа не поддерживается.
  Future<String> recognize(String imagePath, String languageCode) async {
    if (!_supported) return '';
    TextRecognizer? recognizer;
    try {
      recognizer = TextRecognizer(script: scriptFor(languageCode));
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
