import 'dart:async';

import 'package:flutter/material.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../l10n/locale_controller.dart';
import '../l10n/strings.dart';
import '../models/deck.dart';
import '../services/deck_repository.dart';
import '../services/source_library.dart';
import '../study/tappable_text.dart';
import '../theme/app_theme.dart';
import '../widgets/count_up_number.dart';
import 'add_target.dart';
import 'subtitle.dart';
import 'word_bubble.dart';

/// Экран разбора видео: сверху плеер, снизу «караоке»-субтитры. Активная реплика
/// подсвечивается и подкручивается по ходу воспроизведения; тап по слову
/// открывает «пузырь слова» (перевод + озвучка + добавление в колоду).
class VideoStudyScreen extends StatefulWidget {
  final VideoTranscript transcript;

  /// Id записи в библиотеке (если видео уже сохранено) — для счётчика
  /// добавленных слов. Может быть null (например, если сохранение не удалось).
  final String? sourceId;

  /// Язык субтитров, если пользователь исправил автоопределение на странице
  /// видео. Если null — берём язык из самого транскрипта.
  final String? languageOverride;

  const VideoStudyScreen({
    super.key,
    required this.transcript,
    this.sourceId,
    this.languageOverride,
  });

  @override
  State<VideoStudyScreen> createState() => _VideoStudyScreenState();
}

class _VideoStudyScreenState extends State<VideoStudyScreen> {
  late final YoutubePlayerController _controller;
  StreamSubscription<YoutubeVideoState>? _sub;
  // Именно ScrollablePositionedList: обычный ListView строит только видимые
  // строки, и после перемотки видео на 20 минут вперёд нужной строки в дереве
  // нет — автоскролл караоке молча переставал работать.
  final ItemScrollController _scroll = ItemScrollController();

  int _active = -1;
  int _added = 0;
  final Set<String> _addedWords = {};

  /// Слова, которые УЖЕ есть в любой колоде этого языка (системной или
  /// пользовательской) — подсвечиваем, чтобы не добавлять повторно.
  final Set<String> _known = {};

  Deck? _targetDeck;
  String _pendingWord = '';

  late final String _srcLang =
      (widget.languageOverride ?? widget.transcript.langCode).split('-').first;
  final String _tgtLang = LocaleController.instance.code;

  @override
  void initState() {
    super.initState();
    _known.addAll(DeckRepository.instance.knownFrontsForLanguage(_srcLang));
    _controller = YoutubePlayerController.fromVideoId(
      videoId: widget.transcript.videoId,
      autoPlay: false,
      params: const YoutubePlayerParams(
        showControls: true,
        showFullscreenButton: true,
        enableCaption: false,
        playsInline: true,
      ),
    );
    _sub = _controller.videoStateStream.listen(_onTick);
  }

  void _onTick(YoutubeVideoState state) {
    final found = _lineAt(state.position);
    if (found != -1 && found != _active) {
      setState(() => _active = found);
      _scrollToActive(found);
    }
  }

  /// Реплика, звучащая в момент [pos]. Двоичный поиск: реплики упорядочены по
  /// времени, а тик приходит несколько раз в секунду — линейный скан часового
  /// видео (2000+ реплик) грел процессор впустую.
  int _lineAt(Duration pos) {
    final lines = widget.transcript.lines;
    var lo = 0, hi = lines.length - 1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (pos < lines[mid].start) {
        hi = mid - 1;
      } else if (pos > lines[mid].end) {
        lo = mid + 1;
      } else {
        return mid;
      }
    }
    return -1;
  }

  void _scrollToActive(int index) {
    if (!_scroll.isAttached) return;
    _scroll.scrollTo(
      index: index,
      alignment: 0.35,
      duration: const Duration(milliseconds: 320),
      curve: AppTheme.emphasizedDecelerate,
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    _controller.close();
    super.dispose();
  }

  // ------------------------------- Добавление -------------------------------

  Future<AddResult> _onAdd(
    String back,
    String sentence,
    int? cs,
    int? ce,
  ) async {
    _targetDeck ??= await VideoDeckTarget.resolveInSourcePack(
        context, _srcLang, widget.transcript.title);
    final deck = _targetDeck;
    if (deck == null) return AddResult.cancelled;
    final ok = await VideoDeckTarget.addWord(
      deck,
      front: _pendingWord,
      back: back,
      example: sentence,
      sentence: sentence,
      sourceUrl: widget.transcript.url,
      clipStartMs: cs,
      clipEndMs: ce,
    );
    if (!ok) return AddResult.duplicate;
    if (widget.sourceId != null) {
      await SourceLibrary.instance.bumpWordsAdded(widget.sourceId!);
    }
    if (mounted) {
      setState(() {
        _added++;
        _addedWords.add(_pendingWord.toLowerCase());
        _known.add(_pendingWord.toLowerCase());
      });
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(trf('word_added_to', {'deck': deck.name})),
            duration: const Duration(seconds: 2),
          ),
        );
    }
    return AddResult.added;
  }

  void _onWordTap(SubLine line, String word) {
    final clean = _clean(word);
    if (clean.isEmpty) return;
    _pendingWord = clean;
    final sub = _findWord(line, clean);
    Duration? ws, we;
    if (sub != null) {
      final span = line.wordSpan(sub);
      ws = span.$1;
      we = span.$2;
    }
    showWordBubble(
      context,
      word: clean,
      sentence: line.text,
      sourceLang: _srcLang,
      targetLang: _tgtLang,
      controller: _controller,
      sentStart: line.start,
      sentEnd: line.end,
      wordStart: ws,
      wordEnd: we,
      onAdd: _onAdd,
    );
  }

  /// Выделение фразы удержанием и протяжкой — то же, что в читалке книг.
  /// Целая реплика в карточке полезнее отдельного слова: `give up`, `по мере
  /// того как` по словам не собираются.
  void _onPhrase(SubLine line, String selected) {
    var phrase = selected.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (phrase.isEmpty) return;
    if (phrase.length > 120) phrase = phrase.substring(0, 120);
    _pendingWord = phrase;
    final span = line.phraseSpan(phrase);
    showWordBubble(
      context,
      word: phrase,
      sentence: line.text,
      sourceLang: _srcLang,
      targetLang: _tgtLang,
      controller: _controller,
      sentStart: line.start,
      sentEnd: line.end,
      wordStart: span?.$1,
      wordEnd: span?.$2,
      onAdd: _onAdd,
    );
  }

  SubWord? _findWord(SubLine line, String clean) {
    for (final w in line.words) {
      if (_clean(w.text).toLowerCase() == clean.toLowerCase()) return w;
    }
    return null;
  }

  static final RegExp _edge = RegExp(
    r'^[^\p{L}\p{N}]+|[^\p{L}\p{N}]+$',
    unicode: true,
  );
  String _clean(String s) => s.replaceAll(_edge, '');

  // ------------------------------- UI -------------------------------

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return YoutubePlayerControllerProvider(
      controller: _controller,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.transcript.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          actions: [_progressPill(scheme)],
        ),
        body: Column(
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: YoutubePlayer(controller: _controller),
            ),
            const SizedBox(height: 4),
            Expanded(child: _subtitles(scheme)),
          ],
        ),
      ),
    );
  }

  Widget _progressPill(ColorScheme scheme) {
    return Center(
      child: Container(
        margin: const EdgeInsets.only(right: 14),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: scheme.secondaryContainer,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.style_rounded,
                size: 16, color: scheme.onSecondaryContainer),
            const SizedBox(width: 6),
            CountUpNumber(
              value: _added,
              style: TextStyle(
                fontFamily: AppTheme.displayFont,
                fontWeight: FontWeight.w800,
                fontSize: 14,
                color: scheme.onSecondaryContainer,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _subtitles(ColorScheme scheme) {
    final lines = widget.transcript.lines;
    return ScrollablePositionedList.builder(
      itemScrollController: _scroll,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      itemCount: lines.length,
      itemBuilder: (context, i) {
        final line = lines[i];
        final active = i == _active;
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 220),
            opacity: active ? 1 : 0.55,
            // Реплика — один TappableText, а не Wrap из чипов-слов: так
            // работает удержание с протяжкой (фраза целиком), и заодно на
            // строку приходится один распознаватель жестов вместо десятка.
            // Тем же путём читалка книг избавилась от лагов.
            child: TweenAnimationBuilder<double>(
              duration: const Duration(milliseconds: 220),
              curve: AppTheme.emphasizedDecelerate,
              tween: Tween(end: active ? 20 : 16),
              builder: (context, size, _) => TappableText(
                text: line.text,
                style: TextStyle(
                  fontFamily: AppTheme.bodyFont,
                  fontSize: size,
                  height: 1.35,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                  color: active ? scheme.onSurface : scheme.onSurfaceVariant,
                ),
                known: _known,
                sessionAdded: _addedWords,
                highlightVersion: _added,
                knownColor: scheme.tertiary,
                addedColor: scheme.tertiary,
                onWord: (word) => _onWordTap(line, word),
                onPhrase: (phrase) => _onPhrase(line, phrase),
              ),
            ),
          ),
        );
      },
    );
  }
}
