import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../video/subtitle.dart';

/// Тип разобранного источника в библиотеке.
enum SourceKind { video, book }

/// Запись библиотеки — разобранное видео или добавленная книга. Метаданные
/// хранятся в prefs (быстрый список), а «тяжёлый» контент (транскрипт видео /
/// текст книги) — отдельным файлом на диске (`library/<id>.json|txt`).
class LibrarySource {
  final String id;
  final SourceKind kind;
  String title;

  /// Изучаемый язык источника (для сверки слов и перевода).
  final String languageCode;

  /// Момент добавления (мс от эпохи) — сортировка «сначала новые».
  final int createdAt;

  /// Сколько слов уже добавлено из этого источника в колоды.
  int wordsAdded;

  /// Книга: редактируемые метаданные — автор, описание, теги, жанры.
  String author;
  String description;
  List<String> tags;
  List<String> genres;

  /// Видео: id ролика YouTube и ссылка. Книга: null.
  final String? videoId;
  final String? url;

  /// Книга: расширение исходного файла (txt/epub/…) и размер в символах.
  final String? format;
  final int? charCount;

  /// Книга: индекс абзаца, на котором остановился читатель (восстановление
  /// позиции), и список абзацев-закладок.
  int readParagraph;
  List<int> bookmarks;

  LibrarySource({
    required this.id,
    required this.kind,
    required this.title,
    required this.languageCode,
    required this.createdAt,
    this.wordsAdded = 0,
    this.videoId,
    this.url,
    this.format,
    this.charCount,
    this.readParagraph = 0,
    List<int>? bookmarks,
    this.author = '',
    this.description = '',
    List<String>? tags,
    List<String>? genres,
  })  : bookmarks = bookmarks ?? [],
        tags = tags ?? [],
        genres = genres ?? [];

  bool get isVideo => kind == SourceKind.video;
  bool get isBook => kind == SourceKind.book;

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        'title': title,
        'lang': languageCode,
        'createdAt': createdAt,
        'added': wordsAdded,
        if (videoId != null) 'vid': videoId,
        if (url != null) 'url': url,
        if (format != null) 'fmt': format,
        if (charCount != null) 'chars': charCount,
        if (readParagraph > 0) 'pos': readParagraph,
        if (bookmarks.isNotEmpty) 'bm': bookmarks,
        if (author.isNotEmpty) 'author': author,
        if (description.isNotEmpty) 'desc': description,
        if (tags.isNotEmpty) 'tags': tags,
        if (genres.isNotEmpty) 'genres': genres,
      };

  factory LibrarySource.fromJson(Map<String, dynamic> j) => LibrarySource(
        id: j['id'] as String,
        kind: (j['kind'] as String?) == 'book'
            ? SourceKind.book
            : SourceKind.video,
        title: j['title'] as String? ?? '',
        languageCode: j['lang'] as String? ?? 'en',
        createdAt: (j['createdAt'] as num?)?.toInt() ?? 0,
        wordsAdded: (j['added'] as num?)?.toInt() ?? 0,
        videoId: j['vid'] as String?,
        url: j['url'] as String?,
        format: j['fmt'] as String?,
        charCount: (j['chars'] as num?)?.toInt(),
        readParagraph: (j['pos'] as num?)?.toInt() ?? 0,
        bookmarks: [
          for (final b in (j['bm'] as List? ?? const []))
            if (b is num) b.toInt(),
        ],
        author: j['author'] as String? ?? '',
        description: j['desc'] as String? ?? '',
        tags: [
          for (final t in (j['tags'] as List? ?? const []))
            if (t is String) t,
        ],
        genres: [
          for (final g in (j['genres'] as List? ?? const []))
            if (g is String) g,
        ],
      );
}

/// Библиотека разобранных источников (видео и книги). Синглтон-[ChangeNotifier]:
/// экраны слушают и обновляются. Данные переживают перезапуск приложения —
/// пользователь может вернуться к разобранному видео/книге, не загружая заново.
class SourceLibrary extends ChangeNotifier {
  SourceLibrary._();
  static final SourceLibrary instance = SourceLibrary._();

  static const String _kSources = 'librarySources';

  SharedPreferencesAsync get _prefs => SharedPreferencesAsync();

  final List<LibrarySource> _sources = [];
  bool _loaded = false;

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    final raw = await _prefs.getStringList(_kSources) ?? const [];
    _sources.clear();
    for (final e in raw) {
      try {
        _sources.add(
          LibrarySource.fromJson(jsonDecode(e) as Map<String, dynamic>),
        );
      } catch (_) {
        /* пропускаем битую запись */
      }
    }
    _loaded = true;
  }

  Future<void> _persist() async {
    await _prefs.setStringList(
      _kSources,
      _sources.map((s) => jsonEncode(s.toJson())).toList(),
    );
  }

  /// Все источники, сначала новые.
  Future<List<LibrarySource>> list() async {
    await _ensureLoaded();
    final out = List<LibrarySource>.from(_sources)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return out;
  }

  /// Каталог с «тяжёлым» контентом (`.../library`). null, если недоступен.
  Future<Directory?> _dir() async {
    try {
      final base = await getApplicationDocumentsDirectory();
      final dir = Directory('${base.path}/library');
      if (!await dir.exists()) await dir.create(recursive: true);
      return dir;
    } catch (_) {
      return null;
    }
  }

  File? _payloadFile(Directory dir, LibrarySource s) =>
      File('${dir.path}/${s.id}.${s.isVideo ? 'json' : 'txt'}');

  // ----------------------------- Видео -----------------------------

  /// Сохраняет разобранный транскрипт. Если это видео уже есть — обновляет и
  /// поднимает наверх (по videoId). Возвращает id записи (или null при ошибке).
  Future<String?> saveVideo(VideoTranscript t, {DateTime? now}) async {
    await _ensureLoaded();
    final stamp = (now ?? DateTime.now()).millisecondsSinceEpoch;
    // Дубль по videoId — переиспользуем запись, чтобы не плодить копии.
    final existing =
        _sources.where((s) => s.isVideo && s.videoId == t.videoId).firstOrNull;
    final id = existing?.id ?? 'src_$stamp';
    final dir = await _dir();
    if (dir == null) return null;
    try {
      final source = LibrarySource(
        id: id,
        kind: SourceKind.video,
        title: t.title.isEmpty ? t.videoId : t.title,
        languageCode: t.langCode.split('-').first,
        createdAt: stamp,
        wordsAdded: existing?.wordsAdded ?? 0,
        videoId: t.videoId,
        url: t.url,
      );
      await File('${dir.path}/$id.json')
          .writeAsString(jsonEncode(t.toJson()));
      _sources
        ..removeWhere((s) => s.id == id)
        ..add(source);
      await _persist();
      notifyListeners();
      return id;
    } catch (_) {
      return null;
    }
  }

  Future<VideoTranscript?> loadVideo(String id) async {
    final dir = await _dir();
    if (dir == null) return null;
    try {
      final f = File('${dir.path}/$id.json');
      if (!await f.exists()) return null;
      return VideoTranscript.fromJson(
        jsonDecode(await f.readAsString()) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }

  // ----------------------------- Книги -----------------------------

  /// Сохраняет книгу: текст на диск, метаданные в список. Возвращает id.
  Future<String?> saveBook({
    required String title,
    required String languageCode,
    required String format,
    required String text,
    DateTime? now,
  }) async {
    await _ensureLoaded();
    final stamp = (now ?? DateTime.now()).millisecondsSinceEpoch;
    final id = 'src_$stamp';
    final dir = await _dir();
    if (dir == null) return null;
    try {
      await File('${dir.path}/$id.txt').writeAsString(text);
      _sources.add(
        LibrarySource(
          id: id,
          kind: SourceKind.book,
          title: title,
          languageCode: languageCode,
          createdAt: stamp,
          format: format,
          charCount: text.length,
        ),
      );
      await _persist();
      notifyListeners();
      return id;
    } catch (_) {
      return null;
    }
  }

  Future<String?> loadBookText(String id) async {
    final dir = await _dir();
    if (dir == null) return null;
    try {
      final f = File('${dir.path}/$id.txt');
      if (!await f.exists()) return null;
      return f.readAsString();
    } catch (_) {
      return null;
    }
  }

  // ----------------------------- Общее -----------------------------

  /// Запоминает абзац, на котором остановился читатель (тихо, без notify —
  /// зовётся часто при скролле).
  Future<void> setBookPosition(String id, int paragraph) async {
    await _ensureLoaded();
    final s = _sources.where((e) => e.id == id).firstOrNull;
    if (s == null || s.readParagraph == paragraph) return;
    s.readParagraph = paragraph;
    await _persist();
  }

  /// Переключает закладку на абзаце. Возвращает true, если закладка теперь есть.
  Future<bool> toggleBookmark(String id, int paragraph) async {
    await _ensureLoaded();
    final s = _sources.where((e) => e.id == id).firstOrNull;
    if (s == null) return false;
    final has = s.bookmarks.contains(paragraph);
    if (has) {
      s.bookmarks.remove(paragraph);
    } else {
      s.bookmarks.add(paragraph);
      s.bookmarks.sort();
    }
    await _persist();
    notifyListeners();
    return !has;
  }

  /// Свежая копия метаданных источника из кэша (позиция, закладки, wordsAdded).
  Future<LibrarySource?> get(String id) async {
    await _ensureLoaded();
    return _sources.where((e) => e.id == id).firstOrNull;
  }

  /// Обновляет редактируемые метаданные книги (что передано — то и меняем).
  Future<void> updateBook(
    String id, {
    String? title,
    String? author,
    String? description,
    List<String>? tags,
    List<String>? genres,
  }) async {
    await _ensureLoaded();
    final s = _sources.where((e) => e.id == id).firstOrNull;
    if (s == null) return;
    if (title != null && title.trim().isNotEmpty) s.title = title.trim();
    if (author != null) s.author = author.trim();
    if (description != null) s.description = description.trim();
    if (tags != null) {
      s.tags = [
        for (final t in tags)
          if (t.trim().isNotEmpty) t.trim(),
      ];
    }
    if (genres != null) {
      s.genres = [
        for (final g in genres)
          if (g.trim().isNotEmpty) g.trim(),
      ];
    }
    await _persist();
    notifyListeners();
  }

  /// Увеличивает счётчик добавленных слов у источника.
  Future<void> bumpWordsAdded(String id, [int delta = 1]) async {
    await _ensureLoaded();
    final s = _sources.where((e) => e.id == id).firstOrNull;
    if (s == null) return;
    s.wordsAdded += delta;
    await _persist();
    notifyListeners();
  }

  Future<void> delete(String id) async {
    await _ensureLoaded();
    final s = _sources.where((e) => e.id == id).firstOrNull;
    _sources.removeWhere((e) => e.id == id);
    await _persist();
    final dir = await _dir();
    if (dir != null && s != null) {
      try {
        final f = _payloadFile(dir, s);
        if (f != null && await f.exists()) await f.delete();
      } catch (_) {
        /* файл мог не сохраниться — не критично */
      }
    }
    notifyListeners();
  }
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
