import 'dart:convert';

import '../models/word_card.dart';

/// Форматы экспорта личного словаря — совместимы с тем, что импортируют другие
/// приложения:
///  * [csv] — запятые + заголовок (Excel/Google Sheets, Quizlet «CSV»);
///  * [ankiTsv] — табы без заголовка (Anki «Notes in Plain Text», Quizlet TSV);
///  * [json] — универсальный машинный формат / бэкап;
///  * [list] — просто слова по одному в строке (для читалок и частотных списков).
enum VocabFormat { csv, ankiTsv, json, list }

class VocabExport {
  const VocabExport._();

  static String extensionFor(VocabFormat f) => switch (f) {
        VocabFormat.csv => 'csv',
        VocabFormat.ankiTsv => 'txt',
        VocabFormat.json => 'json',
        VocabFormat.list => 'txt',
      };

  static String fileBaseName(VocabFormat f) => switch (f) {
        VocabFormat.csv => 'fern_vocab',
        VocabFormat.ankiTsv => 'fern_anki',
        VocabFormat.json => 'fern_vocab',
        VocabFormat.list => 'fern_words',
      };

  /// Собирает содержимое файла экспорта в выбранном формате.
  static String build(VocabFormat format, List<WordCard> cards) {
    switch (format) {
      case VocabFormat.csv:
        return _csv(cards);
      case VocabFormat.ankiTsv:
        return _ankiTsv(cards);
      case VocabFormat.json:
        return _json(cards);
      case VocabFormat.list:
        return _list(cards);
    }
  }

  static String _csv(List<WordCard> cards) {
    final b = StringBuffer('front,back,example\n');
    for (final c in cards) {
      b.writeln('${_csvField(c.front)},${_csvField(c.back)},'
          '${_csvField(c.example)}');
    }
    return b.toString();
  }

  // RFC 4180: оборачиваем в кавычки, если есть запятая/кавычка/перевод строки.
  static String _csvField(String s) {
    if (s.contains(',') || s.contains('"') || s.contains('\n') ||
        s.contains('\r')) {
      return '"${s.replaceAll('"', '""')}"';
    }
    return s;
  }

  static String _ankiTsv(List<WordCard> cards) {
    final b = StringBuffer();
    for (final c in cards) {
      // Anki-поля разделяются табом; переводы строк внутри поля недопустимы.
      final front = _oneLine(c.front);
      final back = _oneLine(c.back);
      final example = _oneLine(c.example);
      b.writeln(
        example.isEmpty ? '$front\t$back' : '$front\t$back\t$example',
      );
    }
    return b.toString();
  }

  static String _json(List<WordCard> cards) {
    return const JsonEncoder.withIndent('  ').convert([
      for (final c in cards)
        {
          'front': c.front,
          'back': c.back,
          if (c.example.trim().isNotEmpty) 'example': c.example,
        },
    ]);
  }

  static String _list(List<WordCard> cards) {
    final seen = <String>{};
    final b = StringBuffer();
    for (final c in cards) {
      final w = c.front.trim();
      if (w.isEmpty) continue;
      if (seen.add(w.toLowerCase())) b.writeln(w);
    }
    return b.toString();
  }

  static String _oneLine(String s) =>
      s.replaceAll(RegExp(r'[\r\n\t]+'), ' ').trim();
}
