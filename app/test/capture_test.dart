import 'package:flutter_test/flutter_test.dart';

import 'package:fern/services/ocr_service.dart';
import 'package:fern/share/share_import.dart';

void main() {
  group('Поделиться: слово + ссылка', () {
    test('вытаскивает слово, ссылку убирает в источник', () {
      final (w1, u1) = ShareImport.wordAndUrl(
          '"Togetherly" https://play.google.com/console/x');
      expect(w1, 'Togetherly');
      expect(u1, 'https://play.google.com/console/x');

      final (w2, u2) = ShareImport.wordAndUrl(
          '(PREORDER) Voodoo Cards https://roomonecards.com/p?x=1#a');
      expect(w2, '(PREORDER) Voodoo Cards');
      expect(u2, 'https://roomonecards.com/p?x=1#a');
    });

    test('без ссылки — слово как есть', () {
      final (w, u) = ShareImport.wordAndUrl('perro');
      expect(w, 'perro');
      expect(u, '');
    });
  });

  group('OCR: поддерживаемые алфавиты', () {
    test('латиница да, кириллица/арабица/CJK нет', () {
      expect(OcrService.supports('es'), true);
      expect(OcrService.supports('en'), true);
      expect(OcrService.supports('de'), true);
      expect(OcrService.supports('ru'), false);
      expect(OcrService.supports('uk'), false);
      expect(OcrService.supports('ar'), false);
      expect(OcrService.supports('zh'), false);
      expect(OcrService.supports('ja'), false);
    });
  });
}
