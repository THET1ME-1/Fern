import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../l10n/locale_controller.dart';
import '../l10n/strings.dart';
import '../models/deck.dart';
import '../services/deck_repository.dart';
import '../services/source_library.dart';
import '../theme/app_theme.dart';
import '../widgets/count_up_number.dart';
import 'add_target.dart';
import 'karaoke.dart';
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

class _VideoStudyScreenState extends State<VideoStudyScreen>
    with TickerProviderStateMixin {
  late final YoutubePlayerController _controller;
  StreamSubscription<YoutubeVideoState>? _sub;
  StreamSubscription<YoutubePlayerValue>? _valueSub;
  // Именно ScrollablePositionedList: обычный ListView строит только видимые
  // строки, и после перемотки видео на 20 минут вперёд нужной строки в дереве
  // нет — автоскролл караоке молча переставал работать.
  final ItemScrollController _scroll = ItemScrollController();

  /// Реплики по возрастанию начала: [SubLine.activeAt] ищет двоичным поиском.
  late final List<SubLine> _lines;

  /// Часы воспроизведения и их «сейчас». Позиция считается на каждый кадр, а
  /// тики плеера (раз в 100 мс) только подтягивают якорь.
  final PlaybackClock _clock = PlaybackClock();
  final Stopwatch _wall = Stopwatch()..start();
  Ticker? _ticker;

  /// Переезд плашки от прошлого слова к звучащему.
  late final AnimationController _travel;

  int _active = -1;
  int _word = -1;
  List<(int, int)?> _ranges = const [];
  (int, int)? _spoken;
  (int, int)? _previous;

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
    _lines = [...widget.transcript.lines]
      ..sort((a, b) => a.start.compareTo(b.start));
    _known.addAll(DeckRepository.instance.knownFrontsForLanguage(_srcLang));
    _travel = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
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
    _valueSub = _controller.stream.listen(_onPlayerValue);
    _ticker = createTicker(_onFrame);
  }

  /// Позиция от плеера: подтягивает часы, а не двигает подсветку сама.
  void _onTick(YoutubeVideoState state) {
    if (!_clock.playing) _clock.setPlaying(true, _wall.elapsed);
    _clock.sync(state.position, _wall.elapsed);
    if (!(_ticker?.isActive ?? false)) _ticker?.start();
  }

  void _onPlayerValue(YoutubePlayerValue value) {
    _clock.setRate(value.playbackRate, _wall.elapsed);
    final playing = value.playerState == PlayerState.playing;
    if (playing == _clock.playing) return;
    _clock.setPlaying(playing, _wall.elapsed);
    // На паузе тиков от плеера нет вовсе (таймер в player.html живёт только в
    // состоянии «играет»), и держать кадры незачем.
    final ticking = _ticker?.isActive ?? false;
    if (playing && !ticking) {
      _ticker?.start();
    } else if (!playing && ticking) {
      _ticker?.stop();
    }
  }

  /// Каждый кадр: какая реплика звучит и какое слово внутри неё.
  void _onFrame(Duration _) {
    final pos = _clock.positionAt(_wall.elapsed);
    final line = SubLine.activeAt(_lines, pos);
    if (line != _active) {
      final far = _active < 0 || (line - _active).abs() > 6;
      setState(() {
        _active = line;
        _ranges = line < 0 ? const [] : _lines[line].wordCharRanges();
        _word = -1;
        _spoken = null;
        _previous = null;
      });
      if (line >= 0) _scrollToActive(line, jump: far);
      return;
    }
    if (line < 0) return;
    final word = _lines[line].wordAt(pos);
    if (word == _word) return;
    setState(() {
      _word = word;
      _previous = _spoken;
      _spoken = (word >= 0 && word < _ranges.length) ? _ranges[word] : null;
    });
    if (_spoken != null) _travel.forward(from: 0);
  }

  void _scrollToActive(int index, {bool jump = false}) {
    if (!_scroll.isAttached) return;
    // Перемотка через полвидео не должна пролетать через тысячу реплик.
    if (jump) {
      _scroll.jumpTo(index: index, alignment: 0.33);
      return;
    }
    _scroll.scrollTo(
      index: index,
      alignment: 0.33,
      duration: const Duration(milliseconds: 520),
      curve: AppTheme.emphasizedDecelerate,
    );
  }

  @override
  void dispose() {
    // Тикер обязан быть остановлен до dispose, иначе ассерт в отладке.
    _ticker?.stop();
    _ticker?.dispose();
    _travel.dispose();
    _sub?.cancel();
    _valueSub?.cancel();
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
    return ScrollablePositionedList.builder(
      itemScrollController: _scroll,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 32),
      itemCount: _lines.length,
      itemBuilder: (context, i) {
        final line = _lines[i];
        final active = i == _active;
        // Кегль у всех реплик ОДИН. Раньше активная вырастала с 16 до 20, и
        // список перекладывался прямо во время прокрутки — половина рывков была
        // отсюда. Активную реплику выделяют цвет и подложка, они ничего не
        // двигают.
        final style = TextStyle(
          fontFamily: AppTheme.bodyFont,
          fontSize: 18,
          height: 1.4,
          fontWeight: FontWeight.w500,
          color: active ? scheme.onSurface : scheme.onSurfaceVariant,
        );
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 240),
            curve: AppTheme.emphasizedDecelerate,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: active ? scheme.surfaceContainerHigh : Colors.transparent,
              borderRadius: BorderRadius.circular(20),
            ),
            // Реплика — один TappableText, а не Wrap из чипов-слов: так
            // работает удержание с протяжкой (фраза целиком), и заодно на
            // строку приходится один распознаватель жестов вместо десятка.
            // Тем же путём читалка книг избавилась от лагов.
            child: KaraokeLine(
              line: line,
              style: style,
              active: active,
              spoken: _spoken,
              previous: _previous,
              travel: _travel,
              pillColor: scheme.primaryContainer,
              spokenColor: scheme.onPrimaryContainer,
              known: _known,
              sessionAdded: _addedWords,
              highlightVersion: _added,
              knownColor: scheme.tertiary,
              addedColor: scheme.tertiary,
              onWord: (word) => _onWordTap(line, word),
              onPhrase: (phrase) => _onPhrase(line, phrase),
            ),
          ),
        );
      },
    );
  }
}
