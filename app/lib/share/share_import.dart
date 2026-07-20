import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import '../book_screen.dart';
import '../l10n/locale_controller.dart';
import '../l10n/strings.dart';
import '../services/article_import.dart';
import '../services/deck_repository.dart';
import '../services/language_detect.dart';
import '../services/pos.dart';
import '../services/source_library.dart';
import '../study/word_lookup_sheet.dart';
import '../theme/app_theme.dart';
import '../video/add_target.dart';
import '../video/video_import_screen.dart';
import '../services/pro.dart';
import '../widgets/pro_sheet.dart';

/// Приём контента из других приложений через «Поделиться»: YouTube-ссылка →
/// разбор видео; короткий текст → слово в колоду; длинный → книга в Библиотеку.
/// Слушатель запускается один раз из корневого экрана.
class ShareImport {
  ShareImport._();

  static StreamSubscription<List<SharedMediaFile>>? _sub;
  static bool _started = false;

  static bool get _supported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// Запускает приём (начальный интент + поток). [context] — живой контекст
  /// корневого экрана (для навигации).
  static void start(BuildContext context) {
    if (_started || !_supported) return;
    _started = true;
    try {
      ReceiveSharingIntent.instance.getInitialMedia().then((list) {
        // Контекст корневого экрана; актуальность проверяется в _handle.
        // ignore: use_build_context_synchronously
        _handle(context, list);
        ReceiveSharingIntent.instance.reset();
      });
      _sub = ReceiveSharingIntent.instance.getMediaStream().listen(
        // ignore: use_build_context_synchronously
        (list) => _handle(context, list),
      );
    } catch (e) {
      debugPrint('ShareImport start failed: $e');
    }
  }

  static void dispose() {
    _sub?.cancel();
    _sub = null;
    _started = false;
  }

  static void _handle(BuildContext context, List<SharedMediaFile> list) {
    if (list.isEmpty || !context.mounted) return;
    final f = list.firstWhere(
      (e) =>
          e.type == SharedMediaType.text || e.type == SharedMediaType.url,
      orElse: () => list.first,
    );
    final text = f.path.trim();
    if (text.isEmpty) return;
    // Навигация — после кадра (Navigator готов на старте).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.mounted) route(context, text);
    });
  }

  static final RegExp _youtube = RegExp(
    r'(youtube\.com/watch|youtu\.be/|youtube\.com/shorts/)',
    caseSensitive: false,
  );

  /// Маршрутизирует полученный текст. Публичный — можно звать и из тестов.
  static Future<void> route(BuildContext context, String text) async {
    // Ссылка, прилетевшая из «Поделиться», обходит интерфейс библиотеки —
    // поэтому проверка Pro нужна и здесь, иначе гейт дырявый.
    if (!await requirePro(context, ProFeature.library)) return;
    if (!context.mounted) return;
    if (_youtube.hasMatch(text)) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => VideoImportScreen(initialUrl: text)),
      );
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => _ShareSheet(text: text),
    );
  }

  // ------------------------------- Действия -------------------------------

  static final RegExp _urlRe = RegExp(r'https?://\S+', caseSensitive: false);

  /// Выделяет из общего текста слово/фразу (без ссылок и кавычек) и первую
  /// ссылку отдельно — чтобы в карточку шло только слово, а ссылка в источник.
  @visibleForTesting
  static (String word, String url) wordAndUrl(String text) {
    final url = _urlRe.firstMatch(text)?.group(0) ?? '';
    var word = text
        .replaceAll(_urlRe, ' ')
        .replaceAll(RegExp(r'''["«»“”‘’]'''), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (word.isEmpty) word = text.trim(); // на случай «только ссылка»
    return (word, url);
  }

  static Future<void> addAsWord(BuildContext context, String text) async {
    final (word, url) = wordAndUrl(text);
    final lang = await DeckRepository.instance.selectedLanguageCode() ?? 'en';
    if (!context.mounted) return;
    final deck = await VideoDeckTarget.resolveInSourcePack(
        context, lang, tr('share_source'));
    if (deck == null || !context.mounted) return;
    await showWordLookup(
      context,
      word: word,
      sentence: '',
      sourceLang: lang,
      targetLang: LocaleController.instance.code,
      alreadyKnown: false,
      onAdd: (back, example, pos) async {
        final ok = await VideoDeckTarget.addWord(
          deck,
          front: word,
          back: back,
          example: example,
          sentence: example,
          sourceUrl: url, // ссылка — в источник карточки, не в само слово
          pos: PosDetect.detect(word, dictPos: pos, languageCode: lang),
        );
        return ok ? LookupAddResult.added : LookupAddResult.duplicate;
      },
    );
  }

  static Future<void> addAsBook(BuildContext context, String text) async {
    final lang = LanguageDetect.detect(text) ??
        await DeckRepository.instance.selectedLanguageCode() ??
        'en';
    final title = _titleFrom(text);
    final id = await SourceLibrary.instance.saveBook(
      title: title,
      languageCode: lang,
      format: 'txt',
      text: text,
    );
    if (id == null || !context.mounted) return;
    final src = await SourceLibrary.instance.get(id);
    if (src == null || !context.mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => BookScreen(source: src)),
    );
  }

  /// Загружает статью по ссылке [url] и открывает её как книгу в Библиотеке.
  static Future<void> importArticle(BuildContext context, String url) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(tr('article_fetching'))));
    final article = await ArticleImport.fetch(url);
    if (!context.mounted) return;
    if (article == null || !article.hasText) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(tr('article_failed'))));
      return;
    }
    final lang = LanguageDetect.detect(article.text) ??
        await DeckRepository.instance.selectedLanguageCode() ??
        'en';
    final id = await SourceLibrary.instance.saveBook(
      title: article.title,
      languageCode: lang,
      format: 'web',
      text: article.text,
    );
    if (id == null || !context.mounted) return;
    final src = await SourceLibrary.instance.get(id);
    if (src == null || !context.mounted) return;
    messenger.hideCurrentSnackBar();
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => BookScreen(source: src)),
    );
  }

  static String _titleFrom(String text) {
    final firstLine = text.split('\n').first.trim();
    final base = firstLine.isEmpty ? text.trim() : firstLine;
    final words = base.split(RegExp(r'\s+')).take(6).join(' ');
    return words.length > 60 ? '${words.substring(0, 60)}…' : words;
  }
}

class _ShareSheet extends StatelessWidget {
  final String text;
  const _ShareSheet({required this.text});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Есть ссылка → предлагаем загрузить статью; иначе слово/чтение по длине.
    final url = ArticleImport.firstUrl(text);
    final hasUrl = url != null;
    final wordCount = text.trim().split(RegExp(r'\s+')).length;
    final looksLikeWord = !hasUrl && wordCount <= 4;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: scheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              tr('share_import_title'),
              style: TextStyle(
                fontFamily: AppTheme.displayFont,
                fontWeight: FontWeight.w700,
                fontSize: 18,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                text.trim(),
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: AppTheme.bodyFont,
                  fontSize: 14,
                  height: 1.35,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (hasUrl) ...[
              _option(
                context,
                scheme,
                icon: Icons.article_rounded,
                title: tr('share_as_article'),
                subtitle: tr('share_as_article_sub'),
                highlight: true,
                onTap: () {
                  Navigator.pop(context);
                  ShareImport.importArticle(context, url);
                },
              ),
              const SizedBox(height: 10),
            ],
            _option(
              context,
              scheme,
              icon: Icons.translate_rounded,
              title: tr('share_as_word'),
              subtitle: tr('share_as_word_sub'),
              highlight: looksLikeWord,
              onTap: () {
                Navigator.pop(context);
                ShareImport.addAsWord(context, text);
              },
            ),
            const SizedBox(height: 10),
            _option(
              context,
              scheme,
              icon: Icons.auto_stories_rounded,
              title: tr('share_as_book'),
              subtitle: tr('share_as_book_sub'),
              highlight: !hasUrl && !looksLikeWord,
              onTap: () {
                Navigator.pop(context);
                ShareImport.addAsBook(context, text);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _option(
    BuildContext context,
    ColorScheme scheme, {
    required IconData icon,
    required String title,
    required String subtitle,
    required bool highlight,
    required VoidCallback onTap,
  }) {
    return Material(
      color: highlight ? scheme.primaryContainer : scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icon,
                  color: highlight
                      ? scheme.onPrimaryContainer
                      : scheme.primary),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontFamily: AppTheme.displayFont,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: highlight
                            ? scheme.onPrimaryContainer
                            : scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontFamily: AppTheme.bodyFont,
                        fontSize: 12.5,
                        color: highlight
                            ? scheme.onPrimaryContainer.withValues(alpha: 0.85)
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
