import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'book_screen.dart';
import 'l10n/strings.dart';
import 'services/pro.dart';
import 'widgets/pro_sheet.dart';
import 'services/book_import.dart';
import 'services/deck_repository.dart';
import 'services/language_detect.dart';
import 'services/source_library.dart';
import 'theme/app_theme.dart';
import 'ocr/ocr_screen.dart';
import 'share/share_import.dart';
import 'video/subtitle.dart';
import 'video/video_import_screen.dart';
import 'video/video_screen.dart';
import 'widgets/pressable.dart';
import 'widgets/reveal.dart';

/// Сортировка библиотеки.
enum LibrarySort { recent, progress, known }

/// Библиотека: вход в разбор видео и импорт книг + история всех разобранных
/// источников. Всё сохраняется — можно вернуться к видео/книге позже.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final SourceLibrary _library = SourceLibrary.instance;
  final TextEditingController _search = TextEditingController();
  List<LibrarySource> _sources = [];
  final Map<String, String> _covers = {}; // id → путь к обложке
  String _query = '';
  LibrarySort _sort = LibrarySort.recent;
  final Set<String> _filters = {}; // активные жанры/теги
  bool _loading = true;
  bool _importing = false;

  @override
  void initState() {
    super.initState();
    _library.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    _library.removeListener(_load);
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final sources = await _library.list();
    // Пути обложек для книг, у которых они есть.
    final covers = <String, String>{};
    for (final s in sources.where((s) => s.isBook && s.hasCover)) {
      final p = await _library.coverPath(s.id);
      if (p != null) covers[s.id] = p;
    }
    if (!mounted) return;
    setState(() {
      _sources = sources;
      _covers
        ..clear()
        ..addAll(covers);
      // Убираем фильтры, которых больше нет.
      _filters.removeWhere((f) => !_allTags.contains(f));
      _loading = false;
    });
  }

  // ------------------------------- Данные экрана -------------------------------

  /// Все жанры и теги книг (для фильтр-чипов), по алфавиту.
  List<String> get _allTags {
    final set = <String>{};
    for (final s in _sources) {
      set.addAll(s.genres);
      set.addAll(s.tags);
    }
    final list = set.toList()..sort();
    return list;
  }

  /// Начатые, но не дочитанные книги — для полки «Читаю сейчас».
  List<LibrarySource> get _readingNow {
    final list = _sources
        .where((s) => s.isBook && s.isStarted && !s.isFinished)
        .toList()
      ..sort((a, b) => b.readProgress.compareTo(a.readProgress));
    return list;
  }

  /// Источники после поиска, фильтров и сортировки.
  List<LibrarySource> get _visible {
    final q = _query.trim().toLowerCase();
    var list = _sources.where((s) {
      if (q.isNotEmpty) {
        final hay = [
          s.title,
          s.author,
          ...s.genres,
          ...s.tags,
        ].join(' ').toLowerCase();
        if (!hay.contains(q)) return false;
      }
      if (_filters.isNotEmpty) {
        final tags = {...s.genres, ...s.tags};
        if (!_filters.any(tags.contains)) return false;
      }
      return true;
    }).toList();

    switch (_sort) {
      case LibrarySort.recent:
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      case LibrarySort.progress:
        list.sort((a, b) => b.readProgress.compareTo(a.readProgress));
      case LibrarySort.known:
        list.sort((a, b) => b.knownPercent.compareTo(a.knownPercent));
    }
    return list;
  }

  // ------------------------------- Действия -------------------------------

  Future<void> _openVideoImport() async {
    if (!await requirePro(context, ProFeature.library)) return;
    if (!mounted) return;
    HapticFeedback.selectionClick();
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const VideoImportScreen()),
    );
  }

  Future<void> _importBook() async {
    if (_importing) return;
    if (!await requirePro(context, ProFeature.library)) return;
    if (!mounted) return;
    HapticFeedback.selectionClick();
    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: BookImport.supportedExtensions,
      );
    } catch (_) {
      result = await FilePicker.platform.pickFiles(type: FileType.any);
    }
    final path = result?.files.single.path;
    if (path == null) return;

    setState(() => _importing = true);
    final book = await BookImport.extract(path);
    if (!mounted) return;
    if (book == null || book.isEmpty) {
      setState(() => _importing = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(tr('book_import_failed'))));
      return;
    }
    // Язык книги определяем по её тексту (а не по текущему языку изучения),
    // иначе анализ/подсветка сверялись бы не с тем словарём.
    final lang = LanguageDetect.detect(book.text) ??
        await DeckRepository.instance.selectedLanguageCode() ??
        'en';
    final id = await _library.saveBook(
      title: book.title,
      languageCode: lang,
      format: BookImport.extensionOf(path),
      text: book.text,
      chapters: book.chapters,
      cover: book.cover,
    );
    if (!mounted) return;
    setState(() => _importing = false);
    if (id == null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(tr('book_import_failed'))));
      return;
    }
    final src = await _library.get(id);
    if (!mounted || src == null) return;
    _openBookScreen(src);
  }

  void _openBookScreen(LibrarySource s) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => BookScreen(source: s)),
    );
  }

  Future<void> _openSource(LibrarySource s) async {
    if (s.isBook) {
      _openBookScreen(s);
      return;
    }
    // Видео без транскрипта в кэше перекачивается по ссылке — это секунды. Без
    // флага занятости тап выглядел как «ничего не произошло», а повторные тапы
    // запускали параллельные загрузки и несколько переходов подряд.
    if (_importing) return;
    setState(() => _importing = true);
    VideoTranscript? t;
    try {
      t = await _library.loadVideo(s.id);
      if (t == null && (s.url != null || s.videoId != null)) {
        final res = await VideoService.fetch(
          s.url ?? s.videoId!,
          preferLang: s.languageCode,
        );
        if (res.isOk) {
          t = res.transcript;
          await _library.saveVideo(t!);
        }
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
    if (!mounted) return;
    if (t == null) {
      _notOpenable();
      return;
    }
    final cur = await _library.get(s.id) ?? s;
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => VideoScreen(source: cur)),
    );
  }

  void _notOpenable() {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(tr('source_open_failed'))));
  }

  Future<void> _delete(LibrarySource s) async {
    HapticFeedback.mediumImpact();
    await _library.delete(s.id);
  }

  // ------------------------------- UI -------------------------------

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final reading = _readingNow;
    final visible = _visible;
    final tags = _allTags;
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('library_title')),
        actions: [
          if (_sources.length > 1)
            PopupMenuButton<LibrarySort>(
              icon: const Icon(Icons.sort_rounded),
              tooltip: tr('sort_by'),
              initialValue: _sort,
              onSelected: (s) => setState(() => _sort = s),
              itemBuilder: (_) => [
                _sortItem(LibrarySort.recent, tr('sort_recent')),
                _sortItem(LibrarySort.progress, tr('sort_progress')),
                _sortItem(LibrarySort.known, tr('sort_known')),
              ],
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                Reveal(child: _actionRow(scheme)),
                if (reading.isNotEmpty) ...[
                  const SizedBox(height: 22),
                  Reveal(
                    delay: const Duration(milliseconds: 60),
                    child: _sectionTitle(tr('reading_now'), scheme),
                  ),
                  const SizedBox(height: 12),
                  Reveal(
                    delay: const Duration(milliseconds: 80),
                    child: _readingShelf(reading, scheme),
                  ),
                ],
                const SizedBox(height: 22),
                if (_sources.isEmpty)
                  _emptyState(scheme)
                else ...[
                  Reveal(
                    delay: const Duration(milliseconds: 100),
                    child: _searchField(scheme),
                  ),
                  if (tags.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Reveal(
                      delay: const Duration(milliseconds: 120),
                      child: _filterChips(tags, scheme),
                    ),
                  ],
                  const SizedBox(height: 14),
                  if (visible.isEmpty)
                    _noMatches(scheme)
                  else
                    for (var i = 0; i < visible.length; i++)
                      Reveal(
                        delay: Duration(milliseconds: 120 + 30 * i),
                        child: _sourceTile(visible[i], scheme),
                      ),
                ],
              ],
            ),
    );
  }

  PopupMenuItem<LibrarySort> _sortItem(LibrarySort s, String label) {
    return PopupMenuItem<LibrarySort>(
      value: s,
      child: Row(
        children: [
          Icon(
            _sort == s ? Icons.radio_button_checked : Icons.radio_button_off,
            size: 18,
          ),
          const SizedBox(width: 10),
          Text(label),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text, ColorScheme scheme) => Text(
        text,
        style: TextStyle(
          fontFamily: AppTheme.displayFont,
          fontWeight: FontWeight.w700,
          fontSize: 16,
          color: scheme.primary,
        ),
      );

  // ------------------------------- Полка «Читаю сейчас» -------------------------------

  Widget _readingShelf(List<LibrarySource> books, ColorScheme scheme) {
    return SizedBox(
      height: 210,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        itemCount: books.length,
        separatorBuilder: (_, _) => const SizedBox(width: 14),
        itemBuilder: (_, i) => _shelfCard(books[i], scheme),
      ),
    );
  }

  Widget _shelfCard(LibrarySource s, ColorScheme scheme) {
    return PressableScale(
      child: GestureDetector(
        onTap: () => _openBookScreen(s),
        child: SizedBox(
          width: 116,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Отдельный тег: та же книга может быть и в списке ниже (Hero
              // 'src-cover-…') — одинаковые теги на одном экране запрещены.
              Hero(
                tag: 'shelf-cover-${s.id}',
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.20),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: _bookCover(s, scheme, 116, 154),
                ),
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(end: s.readProgress),
                  duration: const Duration(milliseconds: 700),
                  curve: AppTheme.emphasizedDecelerate,
                  builder: (_, v, _) => LinearProgressIndicator(
                    value: v,
                    minHeight: 4,
                    backgroundColor: scheme.surfaceContainerHighest,
                    valueColor: AlwaysStoppedAnimation(scheme.tertiary),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                s.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: AppTheme.bodyFont,
                  fontWeight: FontWeight.w600,
                  fontSize: 12.5,
                  height: 1.15,
                  color: scheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ------------------------------- Поиск и фильтры -------------------------------

  Widget _searchField(ColorScheme scheme) {
    return TextField(
      controller: _search,
      onChanged: (v) => setState(() => _query = v),
      decoration: InputDecoration(
        hintText: tr('library_search_hint'),
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: _query.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () {
                  _search.clear();
                  setState(() => _query = '');
                },
              ),
        isDense: true,
        filled: true,
        fillColor: scheme.surfaceContainerHigh,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _filterChips(List<String> tags, ColorScheme scheme) {
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: tags.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final tag = tags[i];
          final selected = _filters.contains(tag);
          return FilterChip(
            label: Text(tag),
            selected: selected,
            visualDensity: VisualDensity.compact,
            onSelected: (sel) => setState(() {
              if (sel) {
                _filters.add(tag);
              } else {
                _filters.remove(tag);
              }
            }),
          );
        },
      ),
    );
  }

  Widget _noMatches(ColorScheme scheme) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Center(
          child: Text(
            tr('no_matches'),
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
        ),
      );

  Widget _actionRow(ColorScheme scheme) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _actionCard(
                title: tr('video_banner_title'),
                subtitle: tr('library_video_sub'),
                icon: Icons.subtitles_rounded,
                bg: scheme.primaryContainer,
                fg: scheme.onPrimaryContainer,
                onTap: _openVideoImport,
                busy: false,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _actionCard(
                title: tr('library_add_book'),
                subtitle: tr('library_book_sub'),
                icon: Icons.menu_book_rounded,
                bg: scheme.tertiaryContainer,
                fg: scheme.onTertiaryContainer,
                onTap: _importBook,
                busy: _importing,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _actionCard(
                title: tr('ocr_hub_title'),
                subtitle: tr('ocr_hub_sub'),
                icon: Icons.document_scanner_rounded,
                bg: scheme.secondaryContainer,
                fg: scheme.onSecondaryContainer,
                onTap: _openOcr,
                busy: false,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _actionCard(
                title: tr('article_import_title'),
                subtitle: tr('article_import_sub'),
                icon: Icons.article_rounded,
                bg: scheme.surfaceContainerHighest,
                fg: scheme.onSurface,
                onTap: _addArticle,
                busy: false,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _addArticle() async {
    if (!await requirePro(context, ProFeature.library)) return;
    if (!mounted) return;
    final url = await _askUrl();
    if (url == null || url.trim().isEmpty || !mounted) return;
    await ShareImport.importArticle(context, url.trim());
  }

  /// Диалог ввода ссылки на статью (с кнопкой «Вставить» из буфера).
  Future<String?> _askUrl() {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('article_import_title')),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.url,
          decoration: InputDecoration(
            hintText: tr('article_paste_url'),
            suffixIcon: IconButton(
              icon: const Icon(Icons.content_paste_rounded),
              onPressed: () async {
                final data = await Clipboard.getData(Clipboard.kTextPlain);
                if (data?.text != null) controller.text = data!.text!.trim();
              },
            ),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: Text(tr('video_parse')),
          ),
        ],
      ),
    );
  }

  Future<void> _openOcr() async {
    if (!await requirePro(context, ProFeature.library)) return;
    if (!mounted) return;
    HapticFeedback.selectionClick();
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const OcrScreen()),
    );
  }

  Widget _actionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color bg,
    required Color fg,
    required VoidCallback onTap,
    required bool busy,
  }) {
    return PressableScale(
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: busy ? null : onTap,
          child: Container(
            height: 148,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: fg.withValues(alpha: 0.14),
                    shape: BoxShape.circle,
                  ),
                  child: busy
                      ? Padding(
                          padding: const EdgeInsets.all(12),
                          child: CircularProgressIndicator(
                              strokeWidth: 2.4, color: fg),
                        )
                      : Icon(icon, color: fg),
                ),
                const Spacer(),
                Text(
                  title,
                  style: TextStyle(
                    fontFamily: AppTheme.displayFont,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    height: 1.1,
                    color: fg,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontFamily: AppTheme.bodyFont,
                    fontSize: 12,
                    color: fg.withValues(alpha: 0.82),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sourceTile(LibrarySource s, ColorScheme scheme) {
    final isVideo = s.isVideo;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Dismissible(
        key: ValueKey(s.id),
        direction: DismissDirection.endToStart,
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 22),
          decoration: BoxDecoration(
            color: scheme.errorContainer,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Icon(Icons.delete_rounded, color: scheme.onErrorContainer),
        ),
        onDismissed: (_) => _delete(s),
        child: Material(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(20),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => _openSource(s),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  _leadingCover(s, isVideo, scheme),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: AppTheme.displayFont,
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            color: scheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _subtitleFor(s),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: AppTheme.bodyFont,
                            fontSize: 12.5,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        // Тонкий индикатор прогресса чтения для начатых книг.
                        if (s.isBook && s.isStarted && !s.isFinished) ...[
                          const SizedBox(height: 7),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: TweenAnimationBuilder<double>(
                              tween: Tween(end: s.readProgress),
                              duration: const Duration(milliseconds: 700),
                              curve: AppTheme.emphasizedDecelerate,
                              builder: (_, v, _) => LinearProgressIndicator(
                                value: v,
                                minHeight: 4,
                                backgroundColor: scheme.surfaceContainerHighest,
                                valueColor:
                                    AlwaysStoppedAnimation(scheme.tertiary),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.chevron_right_rounded,
                      color: scheme.onSurfaceVariant),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Обложка источника в плитке. Видео — квадратная иконка; книга — вертикальная
  /// обложка (картинка или заглушка) в Hero, чтобы «улететь» в страницу книги.
  Widget _leadingCover(LibrarySource s, bool isVideo, ColorScheme scheme) {
    if (isVideo) return _coverBox(s, scheme, 52, 52);
    return Hero(
      tag: 'src-cover-${s.id}',
      child: _bookCover(s, scheme, 46, 62),
    );
  }

  /// Обложка книги: картинка (если извлечена из epub/fb2) либо заглушка.
  Widget _bookCover(LibrarySource s, ColorScheme scheme, double w, double h) {
    final path = _covers[s.id];
    if (path != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.file(
          File(path),
          width: w,
          height: h,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _coverBox(s, scheme, w, h),
        ),
      );
    }
    return _coverBox(s, scheme, w, h);
  }

  Widget _coverBox(LibrarySource s, ColorScheme scheme, double w, double h) {
    final isVideo = s.isVideo;
    return Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: (isVideo ? scheme.primary : scheme.tertiary)
            .withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(
        isVideo ? Icons.play_circle_fill_rounded : Icons.auto_stories_rounded,
        color: isVideo ? scheme.primary : scheme.tertiary,
        size: w * 0.42,
      ),
    );
  }

  String _subtitleFor(LibrarySource s) {
    final parts = <String>[
      s.isVideo
          ? tr('source_kind_video')
          : (s.author.isNotEmpty ? s.author : tr('source_kind_book')),
    ];
    if (s.isBook && s.format != null) parts.add(s.format!.toUpperCase());
    if (s.isBook && s.isFinished) parts.add(tr('book_finished'));
    if (s.wordsAdded > 0) parts.add(trf('source_words_added', {'n': s.wordsAdded}));
    return parts.join(' · ');
  }

  Widget _emptyState(ColorScheme scheme) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          Icon(Icons.auto_stories_rounded,
              size: 56, color: scheme.primary.withValues(alpha: 0.7)),
          const SizedBox(height: 16),
          Text(
            tr('library_empty_title'),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: AppTheme.displayFont,
              fontWeight: FontWeight.w700,
              fontSize: 18,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            tr('library_empty_sub'),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: AppTheme.bodyFont,
              fontSize: 13,
              height: 1.4,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
