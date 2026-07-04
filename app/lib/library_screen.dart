import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'l10n/strings.dart';
import 'services/book_import.dart';
import 'services/deck_repository.dart';
import 'services/source_library.dart';
import 'study/book_reader_screen.dart';
import 'theme/app_theme.dart';
import 'video/subtitle.dart';
import 'video/video_import_screen.dart';
import 'video/video_study_screen.dart';
import 'widgets/pressable.dart';
import 'widgets/reveal.dart';

/// Библиотека: вход в разбор видео и импорт книг + история всех разобранных
/// источников. Всё сохраняется — можно вернуться к видео/книге позже.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final SourceLibrary _library = SourceLibrary.instance;
  List<LibrarySource> _sources = [];
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
    super.dispose();
  }

  Future<void> _load() async {
    final sources = await _library.list();
    if (!mounted) return;
    setState(() {
      _sources = sources;
      _loading = false;
    });
  }

  // ------------------------------- Действия -------------------------------

  void _openVideoImport() {
    HapticFeedback.selectionClick();
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const VideoImportScreen()),
    );
  }

  Future<void> _importBook() async {
    if (_importing) return;
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
    final lang =
        await DeckRepository.instance.selectedLanguageCode() ?? 'en';
    final id = await _library.saveBook(
      title: book.title,
      languageCode: lang,
      format: BookImport.extensionOf(path),
      text: book.text,
    );
    if (!mounted) return;
    setState(() => _importing = false);
    if (id == null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(tr('book_import_failed'))));
      return;
    }
    _openBook(id, book.title, lang, book.text);
  }

  void _openBook(String id, String title, String lang, String text) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BookReaderScreen(
          sourceId: id,
          title: title,
          languageCode: lang,
          text: text,
        ),
      ),
    );
  }

  Future<void> _openSource(LibrarySource s) async {
    if (s.isBook) {
      final text = await _library.loadBookText(s.id);
      if (!mounted) return;
      if (text == null) {
        _notOpenable();
        return;
      }
      _openBook(s.id, s.title, s.languageCode, text);
      return;
    }
    // Видео: пробуем из кэша, иначе перезагружаем по ссылке.
    VideoTranscript? t = await _library.loadVideo(s.id);
    if (t == null && (s.url != null || s.videoId != null)) {
      final res =
          await VideoService.fetch(s.url ?? s.videoId!, preferLang: s.languageCode);
      if (res.isOk) {
        t = res.transcript;
        await _library.saveVideo(t!);
      }
    }
    if (!mounted) return;
    if (t == null) {
      _notOpenable();
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VideoStudyScreen(transcript: t!, sourceId: s.id),
      ),
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
    return Scaffold(
      appBar: AppBar(title: Text(tr('library_title'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                Reveal(child: _actionRow(scheme)),
                const SizedBox(height: 22),
                Reveal(
                  delay: const Duration(milliseconds: 80),
                  child: Text(
                    tr('library_recent'),
                    style: TextStyle(
                      fontFamily: AppTheme.displayFont,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: scheme.primary,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if (_sources.isEmpty)
                  _emptyState(scheme)
                else
                  for (var i = 0; i < _sources.length; i++)
                    Reveal(
                      delay: Duration(milliseconds: 100 + 40 * i),
                      child: _sourceTile(_sources[i], scheme),
                    ),
              ],
            ),
    );
  }

  Widget _actionRow(ColorScheme scheme) {
    return Row(
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
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: (isVideo ? scheme.primary : scheme.tertiary)
                          .withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Icon(
                      isVideo
                          ? Icons.play_circle_fill_rounded
                          : Icons.menu_book_rounded,
                      color: isVideo ? scheme.primary : scheme.tertiary,
                      size: 26,
                    ),
                  ),
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

  String _subtitleFor(LibrarySource s) {
    final kind = s.isVideo ? tr('source_kind_video') : tr('source_kind_book');
    final parts = <String>[kind];
    if (s.isBook && s.format != null) parts.add(s.format!.toUpperCase());
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
