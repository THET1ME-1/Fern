import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:sqlite3/sqlite3.dart';

import '../models/deck.dart';
import '../models/word_card.dart';
import 'deck_repository.dart';

/// Итог импорта колоды из внешнего файла.
enum ImportOutcome { ok, unsupported, empty, failed }

class ImportResult {
  final int count;
  final String? deckId;
  final String deckName;
  final ImportOutcome outcome;
  const ImportResult({
    this.count = 0,
    this.deckId,
    this.deckName = '',
    this.outcome = ImportOutcome.ok,
  });
}

/// Одна распарсенная карточка (перёд/зад/пример).
class _Row {
  final String front;
  final String back;
  final String example;
  const _Row(this.front, this.back, this.example);
}

class _UnsupportedApkg implements Exception {}

/// Импорт колод из Anki (`.apkg`) и текстовых списков (`csv`/`tsv`/`txt`).
///
/// `.apkg` — это ZIP с SQLite-базой (`collection.anki2`/`collection.anki21`);
/// читаем таблицу `notes`, поля разделены U+001F, берём первые два как
/// слово/перевод. НОВЫЙ формат `collection.anki21b` (zstd) не поддержан —
/// просим экспортировать в старый формат или CSV.
class DeckImport {
  const DeckImport._();

  static const List<String> supportedExtensions = [
    'apkg', 'csv', 'tsv', 'txt', 'tab', 'text',
  ];

  static Future<ImportResult> import(String path, String languageCode) async {
    try {
      final ext = _ext(path);
      final List<_Row> rows;
      if (ext == 'apkg') {
        rows = await _parseApkg(path);
      } else {
        rows = _parseDelimited(await File(path).readAsString());
      }
      if (rows.isEmpty) return const ImportResult(outcome: ImportOutcome.empty);
      final name = _baseName(path);
      final id = await _createDeck(name, languageCode, rows);
      return ImportResult(
        count: rows.length,
        deckId: id,
        deckName: name,
        outcome: id == null ? ImportOutcome.failed : ImportOutcome.ok,
      );
    } on _UnsupportedApkg {
      return const ImportResult(outcome: ImportOutcome.unsupported);
    } catch (e) {
      debugPrint('DeckImport failed: $e');
      return const ImportResult(outcome: ImportOutcome.failed);
    }
  }

  // ------------------------------- Anki .apkg -------------------------------

  static Future<List<_Row>> _parseApkg(String path) async {
    final archive = ZipDecoder().decodeBytes(await File(path).readAsBytes());
    ArchiveFile? dbFile;
    for (final want in const ['collection.anki21', 'collection.anki2']) {
      for (final f in archive.files) {
        if (f.isFile && f.name == want) {
          dbFile = f;
          break;
        }
      }
      if (dbFile != null) break;
    }
    if (dbFile == null) {
      final hasZstd = archive.files.any((f) => f.name == 'collection.anki21b');
      if (hasZstd) throw _UnsupportedApkg();
      throw Exception('collection.anki2 not found');
    }

    // Пишем базу во временный файл и открываем через sqlite3.
    final tmp = File(
      '${Directory.systemTemp.path}/fern_anki_${DateTime.now().microsecondsSinceEpoch}.sqlite',
    );
    await tmp.writeAsBytes(dbFile.content as List<int>);
    final out = <_Row>[];
    Database? db;
    try {
      db = sqlite3.open(tmp.path);
      final rows = db.select('SELECT flds FROM notes');
      for (final r in rows) {
        final flds = (r['flds'] as String).split(String.fromCharCode(0x1f));
        if (flds.length < 2) continue;
        final front = _cleanHtml(flds[0]);
        final back = _cleanHtml(flds[1]);
        if (front.isEmpty || back.isEmpty) continue;
        out.add(_Row(front, back, ''));
      }
    } finally {
      db?.dispose();
      try {
        await tmp.delete();
      } catch (_) {/* временный файл — не критично */}
    }
    return out;
  }

  static String _cleanHtml(String s) {
    var t = s;
    t = t.replaceAll(RegExp(r'\[sound:[^\]]*\]'), ' ');
    t = t.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), ' ');
    t = t.replaceAll(RegExp(r'<[^>]+>'), ' ');
    t = _entities(t);
    t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
    return t;
  }

  // ------------------------------- CSV / TSV -------------------------------

  static List<_Row> _parseDelimited(String text) {
    final lines = text.split(RegExp(r'\r?\n'));
    final sample = lines.firstWhere(
      (l) => l.trim().isNotEmpty && !l.startsWith('#'),
      orElse: () => '',
    );
    final delim = sample.contains('\t')
        ? '\t'
        : (sample.contains(';') && !sample.contains(',') ? ';' : ',');

    final out = <_Row>[];
    var first = true;
    for (final line in lines) {
      if (line.trim().isEmpty || line.startsWith('#')) continue;
      final fields =
          delim == ',' ? _csvSplit(line) : line.split(delim);
      if (fields.length < 2) continue;
      final front = fields[0].trim();
      final back = fields[1].trim();
      if (front.isEmpty || back.isEmpty) continue;
      if (first && _looksLikeHeader(front, back)) {
        first = false;
        continue;
      }
      first = false;
      out.add(_Row(front, back, fields.length > 2 ? fields[2].trim() : ''));
    }
    return out;
  }

  // Разбор одной CSV-строки с учётом кавычек (RFC 4180).
  static List<String> _csvSplit(String line) {
    final out = <String>[];
    final sb = StringBuffer();
    var inQuotes = false;
    for (var i = 0; i < line.length; i++) {
      final ch = line[i];
      if (inQuotes) {
        if (ch == '"') {
          if (i + 1 < line.length && line[i + 1] == '"') {
            sb.write('"');
            i++;
          } else {
            inQuotes = false;
          }
        } else {
          sb.write(ch);
        }
      } else if (ch == '"') {
        inQuotes = true;
      } else if (ch == ',') {
        out.add(sb.toString());
        sb.clear();
      } else {
        sb.write(ch);
      }
    }
    out.add(sb.toString());
    return out;
  }

  static const Set<String> _headerWords = {
    'front', 'back', 'word', 'term', 'translation', 'question', 'answer',
    'слово', 'перевод', 'фраза', 'термин',
  };

  static bool _looksLikeHeader(String a, String b) =>
      _headerWords.contains(a.toLowerCase()) &&
      _headerWords.contains(b.toLowerCase());

  // ------------------------------- Общее -------------------------------

  static Future<String?> _createDeck(
    String name,
    String lang,
    List<_Row> rows,
  ) async {
    final repo = DeckRepository.instance;
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final id = 'deck_imp_$stamp';
    await repo.upsertDeck(Deck(
      id: id,
      languageCode: lang,
      name: name,
      colorValue: 0xFF3F6FB0,
      shapeIndex: 0,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    ));
    final cards = <WordCard>[];
    final seen = <String>{};
    var i = 0;
    for (final r in rows) {
      if (!seen.add(r.front.toLowerCase())) continue; // дедуп внутри импорта
      cards.add(WordCard(
        id: '${id}_$i',
        deckId: id,
        front: r.front,
        back: r.back,
        example: r.example,
      ));
      i++;
    }
    if (cards.isEmpty) return null;
    await repo.addCards(cards);
    return id;
  }

  static String _ext(String path) {
    final name = path.split(Platform.pathSeparator).last;
    final dot = name.lastIndexOf('.');
    return dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
  }

  static String _baseName(String path) {
    final name = path.split(Platform.pathSeparator).last;
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }

  static String _entities(String s) {
    var r = s;
    const map = {
      '&amp;': '&', '&lt;': '<', '&gt;': '>', '&quot;': '"',
      '&apos;': "'", '&#39;': "'", '&nbsp;': ' ',
    };
    map.forEach((k, v) => r = r.replaceAll(k, v));
    r = r.replaceAllMapped(RegExp(r'&#(\d+);'), (m) {
      final c = int.tryParse(m.group(1)!);
      return c == null ? m.group(0)! : String.fromCharCode(c);
    });
    return r;
  }
}
