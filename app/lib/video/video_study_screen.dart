import 'dart:async';

import 'package:flutter/material.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../l10n/locale_controller.dart';
import '../l10n/strings.dart';
import '../models/deck.dart';
import '../services/deck_repository.dart';
import '../services/source_library.dart';
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

  const VideoStudyScreen({
    super.key,
    required this.transcript,
    this.sourceId,
  });

  @override
  State<VideoStudyScreen> createState() => _VideoStudyScreenState();
}

class _VideoStudyScreenState extends State<VideoStudyScreen> {
  late final YoutubePlayerController _controller;
  StreamSubscription<YoutubeVideoState>? _sub;
  final ScrollController _scroll = ScrollController();
  late final List<GlobalKey> _lineKeys;

  int _active = -1;
  int _added = 0;
  final Set<String> _addedWords = {};

  /// Слова, которые УЖЕ есть в любой колоде этого языка (системной или
  /// пользовательской) — подсвечиваем, чтобы не добавлять повторно.
  final Set<String> _known = {};

  Deck? _targetDeck;
  String _pendingWord = '';

  late final String _srcLang = widget.transcript.langCode.split('-').first;
  final String _tgtLang = LocaleController.instance.code;

  @override
  void initState() {
    super.initState();
    _known.addAll(DeckRepository.instance.knownFrontsForLanguage(_srcLang));
    _lineKeys = List.generate(widget.transcript.lines.length, (_) => GlobalKey());
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
    final pos = state.position;
    final lines = widget.transcript.lines;
    // Ищем активную реплику рядом с текущей (обычно соседняя — дёшево).
    int found = -1;
    for (var i = 0; i < lines.length; i++) {
      if (pos >= lines[i].start && pos <= lines[i].end) {
        found = i;
        break;
      }
    }
    if (found != -1 && found != _active) {
      setState(() => _active = found);
      _scrollToActive(found);
    }
  }

  void _scrollToActive(int index) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _lineKeys[index].currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          alignment: 0.35,
          duration: const Duration(milliseconds: 320),
          curve: AppTheme.emphasizedDecelerate,
        );
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _controller.close();
    _scroll.dispose();
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

  void _onWordTap(SubLine line, String token) {
    final clean = _clean(token);
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
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      itemCount: lines.length,
      itemBuilder: (context, i) {
        final line = lines[i];
        final active = i == _active;
        return Container(
          key: _lineKeys[i],
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 220),
            opacity: active ? 1 : 0.55,
            child: Wrap(
              spacing: 2,
              runSpacing: 2,
              children: [
                for (final token in line.text.split(RegExp(r'\s+')))
                  if (token.isNotEmpty)
                    _WordChip(
                      token: token,
                      active: active,
                      added: _addedWords.contains(_clean(token).toLowerCase()) ||
                          _known.contains(_clean(token).toLowerCase()),
                      onTap: () => _onWordTap(line, token),
                    ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Одно тап-слово субтитра. Активная реплика — крупнее; добавленные слова
/// подчёркнуты цветом.
class _WordChip extends StatelessWidget {
  final String token;
  final bool active;
  final bool added;
  final VoidCallback onTap;

  const _WordChip({
    required this.token,
    required this.active,
    required this.added,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
        decoration: added
            ? BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: scheme.tertiary, width: 2),
                ),
              )
            : null,
        child: AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 220),
          curve: AppTheme.emphasizedDecelerate,
          style: TextStyle(
            fontFamily: AppTheme.bodyFont,
            fontSize: active ? 20 : 16,
            height: 1.35,
            fontWeight: active ? FontWeight.w600 : FontWeight.w400,
            color: added
                ? scheme.tertiary
                : active
                    ? scheme.onSurface
                    : scheme.onSurfaceVariant,
          ),
          child: Text(token),
        ),
      ),
    );
  }
}
