import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../l10n/locale_controller.dart';
import '../l10n/strings.dart';
import '../models/book_chapter.dart';
import '../models/deck.dart';
import '../services/deck_repository.dart';
import '../services/lemmatizer.dart';
import '../services/pos.dart';
import '../services/source_library.dart';
import '../services/tts_service.dart';
import '../theme/app_theme.dart';
import '../video/add_target.dart';
import '../widgets/pressable.dart';
import 'reader_settings.dart';
import 'tappable_text.dart';
import 'word_lookup_sheet.dart';

/// Читалка книги в духе Linga: непрерывный текст, тап по слову → перевод и
/// добавление в колоду, подсветка уже известных слов, сохранение позиции,
/// закладки и настраиваемые темы/шрифт чтения.
class BookReaderScreen extends StatefulWidget {
  final String sourceId;
  final String title;
  final String languageCode;
  final String text;

  /// Открыть на конкретном абзаце (напр., переход к главе), иначе — с
  /// сохранённой позиции.
  final int? initialParagraph;

  const BookReaderScreen({
    super.key,
    required this.sourceId,
    required this.title,
    required this.languageCode,
    required this.text,
    this.initialParagraph,
  });

  @override
  State<BookReaderScreen> createState() => _BookReaderScreenState();
}

class _BookReaderScreenState extends State<BookReaderScreen> {
  final ItemScrollController _scroll = ItemScrollController();
  final ItemPositionsListener _positions = ItemPositionsListener.create();
  final ReaderSettings _settings = ReaderSettings.instance;
  final SourceLibrary _library = SourceLibrary.instance;
  final DeckRepository _repo = DeckRepository.instance;

  late final List<String> _paragraphs;
  // Единый текст для постраничного режима + смещения начала каждого абзаца в нём
  // (чтобы переносить позицию чтения между режимами «прокрутка» и «страницы»).
  late final String _fullText;
  late final List<int> _paragraphOffsets;
  late final String _srcLang = widget.languageCode.split('-').first;
  final String _tgtLang = LocaleController.instance.code;

  // Слова, уже бывшие в базе на момент открытия книги (подсвечиваются одним
  // цветом), и слова, добавленные ПРЯМО в этой сессии чтения (другим цветом).
  final Set<String> _known = {};
  final Set<String> _sessionAdded = {};
  int _knownVersion = 0;
  final Set<int> _bookmarks = {};
  final List<BookChapter> _chapters = [];

  // Текущий верхний абзац. Держим и в поле (для сохранения/закладок), и в
  // [ValueNotifier] — чтобы полоса прогресса и футер обновлялись при прокрутке
  // БЕЗ setState на весь экран (иначе список пересобирается на каждый абзац).
  int _topIndex = 0;
  final ValueNotifier<int> _topIndexN = ValueNotifier(0);
  int _startIndex = 0;
  int _addedCount = 0;
  Deck? _targetDeck;
  bool _ready = false;
  Timer? _saveTimer;

  // Чтение вслух: читаем абзацы по очереди, подсвечивая текущий; [_playToken]
  // отменяет цикл при остановке/перезапуске.
  bool _playing = false;
  int _speakingIndex = -1;
  int _playToken = 0;

  // Статистика чтения: время открытого экрана + оценка прочитанных слов
  // (по продвижению «дальше всего прочитанного» абзаца за сессию).
  final DateTime _openedAt = DateTime.now();
  int _furthest = 0;
  int _sessionWords = 0;

  @override
  void initState() {
    super.initState();
    _paragraphs = widget.text
        .split('\n')
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();
    // Абзацы через пустую строку — так же меряем и рисуем в постраничном режиме.
    _fullText = _paragraphs.join('\n\n');
    _paragraphOffsets = _computeParagraphOffsets();
    _settings.addListener(_onSettings);
    _positions.itemPositions.addListener(_onScroll);
    _init();
  }

  Future<void> _init() async {
    await _settings.load();
    // Храним ОСНОВЫ известных слов — подсветка засчитывает словоформы.
    _known.addAll(
      _repo.knownFrontsForLanguage(_srcLang).map(_normalize),
    );
    final src = await _library.get(widget.sourceId);
    if (src != null && _paragraphs.isNotEmpty) {
      _bookmarks.addAll(src.bookmarks);
      _chapters.addAll(src.chapters);
      final start = widget.initialParagraph ?? src.readParagraph;
      _startIndex = start.clamp(0, _paragraphs.length - 1);
      _addedCount = src.wordsAdded;
      _topIndex = _startIndex;
      _topIndexN.value = _startIndex;
      _furthest = _startIndex;
    }
    // Бэкфилл числа абзацев (для прогресса/«книг прочитано» без загрузки текста).
    _library.setParagraphCount(widget.sourceId, _paragraphs.length);
    if (mounted) setState(() => _ready = true);
  }

  int _wordsIn(String p) =>
      p.split(RegExp(r'\s+')).where((w) => w.trim().isNotEmpty).length;

  void _onSettings() {
    if (mounted) setState(() {});
  }

  void _onScroll() {
    final positions = _positions.itemPositions.value;
    if (positions.isEmpty) return;
    final visible = positions.where((p) => p.itemTrailingEdge > 0);
    if (visible.isEmpty) return;
    final top = visible.reduce((a, b) => a.index < b.index ? a : b).index;
    _updateTop(top);
  }

  /// Единая точка обновления «текущего абзаца» (из прокрутки или из страницы) +
  /// отложенное сохранение позиции. Пишем в [ValueNotifier] (обновит прогресс
  /// без пересборки списка) и отдельно кэшируем в поле для закладок/сохранения.
  void _updateTop(int index) {
    if (index == _topIndex) return;
    // Слова абзацев, впервые прочитанных за эту сессию (продвижение вперёд).
    if (index > _furthest) {
      for (var i = _furthest + 1; i <= index && i < _paragraphs.length; i++) {
        _sessionWords += _wordsIn(_paragraphs[i]);
      }
      _furthest = index;
    }
    _topIndex = index;
    _topIndexN.value = index;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), () {
      _library.setBookPosition(widget.sourceId, _topIndex);
    });
  }

  List<int> _computeParagraphOffsets() {
    final offsets = <int>[];
    var acc = 0;
    for (final p in _paragraphs) {
      offsets.add(acc);
      acc += p.length + 2; // + разделитель '\n\n'
    }
    return offsets;
  }

  /// Индекс абзаца по символьному смещению в [_fullText].
  int _paragraphAtOffset(int offset) {
    var p = 0;
    for (var i = 0; i < _paragraphOffsets.length; i++) {
      if (_paragraphOffsets[i] <= offset) {
        p = i;
      } else {
        break;
      }
    }
    return p;
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _playToken++;
    TtsService.instance.stop();
    // Итог сессии чтения в общую статистику.
    final seconds = DateTime.now().difference(_openedAt).inSeconds;
    _repo.addReading(seconds: seconds, words: _sessionWords);
    _library.setBookPosition(widget.sourceId, _topIndex);
    _positions.itemPositions.removeListener(_onScroll);
    _settings.removeListener(_onSettings);
    _topIndexN.dispose();
    super.dispose();
  }

  // ------------------------------- Слова -------------------------------

  static final RegExp _edge = RegExp(
    r'^[^\p{L}\p{N}]+|[^\p{L}\p{N}]+$',
    unicode: true,
  );
  String _clean(String s) => s.replaceAll(_edge, '');

  /// Ключ сверки слова (лемматизация) — общий для подсветки и добавления.
  String _normalize(String w) => Lemmatizer.stem(w, _srcLang);

  /// Предложение, содержащее слово (для контекста и озвучки).
  String _sentenceFor(String paragraph, String word) {
    final sentences = paragraph.split(RegExp(r'(?<=[.!?…])\s+'));
    final w = word.toLowerCase();
    for (final s in sentences) {
      if (s.toLowerCase().contains(w)) {
        return s.trim().length > 220 ? word : s.trim();
      }
    }
    return paragraph.length > 220 ? word : paragraph;
  }

  Future<void> _onWordTap(String token, String paragraph) async {
    final clean = _clean(token);
    if (clean.isEmpty) return;
    if (_playing) _stopRead(); // не мешаем озвучку слова с чтением вслух
    HapticFeedback.selectionClick();
    await showWordLookup(
      context,
      word: clean,
      sentence: _sentenceFor(paragraph, clean),
      sourceLang: _srcLang,
      targetLang: _tgtLang,
      alreadyKnown: _known.contains(_normalize(clean)) ||
          _sessionAdded.contains(_normalize(clean)),
      onAdd: (back, example, pos) => _addWord(clean, back, example, paragraph, pos),
    );
  }

  Future<LookupAddResult> _addWord(
    String front,
    String back,
    String example,
    String paragraph,
    String? dictPos,
  ) async {
    _targetDeck ??= await _resolveDeck();
    final deck = _targetDeck;
    if (deck == null) return LookupAddResult.cancelled;
    final ok = await VideoDeckTarget.addWord(
      deck,
      front: front,
      back: back,
      example: _sentenceFor(paragraph, front),
      sentence: _sentenceFor(paragraph, front),
      pos: PosDetect.detect(front, dictPos: dictPos, languageCode: _srcLang),
    );
    if (!ok) return LookupAddResult.duplicate;
    await _library.bumpWordsAdded(widget.sourceId);
    if (mounted) {
      setState(() {
        _sessionAdded.add(_normalize(front));
        _knownVersion++;
        _addedCount++;
      });
    }
    return LookupAddResult.added;
  }

  /// Перевод выделенной фразы (long-press + drag) → карточка (front = фраза).
  Future<void> _onPhrase(String selected) async {
    var phrase = selected.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (phrase.isEmpty) return;
    if (phrase.length > 120) phrase = phrase.substring(0, 120);
    if (_playing) _stopRead();
    HapticFeedback.selectionClick();
    if (!mounted) return;
    await showWordLookup(
      context,
      word: phrase,
      sentence: phrase,
      sourceLang: _srcLang,
      targetLang: _tgtLang,
      alreadyKnown: false,
      onAdd: (back, example, pos) => _addPhrase(phrase, back),
    );
  }

  Future<LookupAddResult> _addPhrase(String front, String back) async {
    _targetDeck ??= await _resolveDeck();
    final deck = _targetDeck;
    if (deck == null) return LookupAddResult.cancelled;
    final ok = await VideoDeckTarget.addWord(
      deck,
      front: front,
      back: back,
      example: front,
      sentence: front,
    );
    if (!ok) return LookupAddResult.duplicate;
    await _library.bumpWordsAdded(widget.sourceId);
    if (mounted) setState(() => _addedCount++);
    return LookupAddResult.added;
  }

  /// Целевая колода для слов книги. У КАЖДОЙ книги — свой ПАК (папка с названием
  /// книги, создаётся один раз, без дублей); внутри выбираем/создаём колоду.
  /// Кэшируется на сессию — выбор спрашивается один раз за чтение.
  Future<Deck?> _resolveDeck() async {
    if (!mounted) return null;
    return VideoDeckTarget.resolveInSourcePack(context, _srcLang, widget.title);
  }

  // ------------------------------- Закладки -------------------------------

  Future<void> _toggleBookmark() async {
    HapticFeedback.mediumImpact();
    final now = await _library.toggleBookmark(widget.sourceId, _topIndex);
    if (!mounted) return;
    setState(() {
      if (now) {
        _bookmarks.add(_topIndex);
      } else {
        _bookmarks.remove(_topIndex);
      }
    });
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(now ? tr('bookmark_added') : tr('bookmark_removed')),
          duration: const Duration(seconds: 1),
        ),
      );
  }

  void _jumpTo(int index) {
    _scroll.scrollTo(
      index: index,
      duration: const Duration(milliseconds: 420),
      curve: AppTheme.emphasizedDecelerate,
      alignment: 0.02,
    );
  }

  // ------------------------------- Чтение вслух -------------------------------

  Future<void> _toggleRead() async {
    HapticFeedback.selectionClick();
    if (_playing) {
      _stopRead();
      return;
    }
    // Чтение — это «следование» по тексту, поэтому в постраничном режиме
    // переключаемся на прокрутку.
    if (_settings.horizontalPaging) {
      await _settings.setHorizontalPaging(false);
      await Future<void>.delayed(const Duration(milliseconds: 60));
    }
    if (!await TtsService.instance.isAvailable(_srcLang)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(tr('tts_unavailable'))));
      return;
    }
    _startRead();
  }

  void _stopRead() {
    _playToken++;
    TtsService.instance.stop();
    if (mounted) {
      setState(() {
        _playing = false;
        _speakingIndex = -1;
      });
    } else {
      _playing = false;
      _speakingIndex = -1;
    }
  }

  Future<void> _startRead() async {
    final token = ++_playToken;
    if (mounted) setState(() => _playing = true);
    final start = _topIndex.clamp(0, _paragraphs.length - 1);
    for (var i = start; i < _paragraphs.length; i++) {
      if (!_playing || token != _playToken || !mounted) return;
      setState(() => _speakingIndex = i);
      _updateTop(i);
      if (_scroll.isAttached) {
        _scroll.scrollTo(
          index: i,
          duration: const Duration(milliseconds: 400),
          curve: AppTheme.emphasizedDecelerate,
          alignment: 0.16,
        );
      }
      await TtsService.instance.speak(_paragraphs[i], _srcLang);
    }
    if (mounted && token == _playToken) {
      setState(() {
        _playing = false;
        _speakingIndex = -1;
      });
    }
  }

  // ------------------------------- UI -------------------------------

  @override
  Widget build(BuildContext context) {
    final t = _settings.theme;
    final barColor = t.background;

    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(
        backgroundColor: barColor,
        surfaceTintColor: Colors.transparent,
        foregroundColor: t.text,
        elevation: 0,
        title: Text(
          widget.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: AppTheme.displayFont,
            fontWeight: FontWeight.w700,
            fontSize: 16,
            color: t.text,
          ),
        ),
        actions: [
          IconButton(
            tooltip: tr('read_aloud'),
            onPressed: _ready ? _toggleRead : null,
            icon: Icon(
              _playing ? Icons.stop_circle_rounded : Icons.headphones_rounded,
              color: _playing ? t.accent : t.text,
            ),
          ),
          if (_addedCount > 0)
            Center(
              child: Container(
                margin: const EdgeInsets.only(right: 4),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: t.accent.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.style_rounded, size: 14, color: t.accent),
                    const SizedBox(width: 5),
                    Text(
                      '$_addedCount',
                      style: TextStyle(
                        fontFamily: AppTheme.displayFont,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        color: t.accent,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ValueListenableBuilder<int>(
            valueListenable: _topIndexN,
            builder: (_, top, _) {
              final isBookmarked = _bookmarks.contains(top);
              return IconButton(
                tooltip: tr('bookmark'),
                onPressed: _ready ? _toggleBookmark : null,
                icon: Icon(
                  isBookmarked
                      ? Icons.bookmark_rounded
                      : Icons.bookmark_border_rounded,
                  color: isBookmarked ? t.accent : t.text,
                ),
              );
            },
          ),
          IconButton(
            tooltip: tr('bookmarks'),
            onPressed: _ready ? _openBookmarks : null,
            icon: Icon(Icons.bookmarks_outlined, color: t.text),
          ),
          if (_chapters.isNotEmpty)
            IconButton(
              tooltip: tr('chapters'),
              onPressed: _ready ? _openChapters : null,
              icon: Icon(Icons.toc_rounded, color: t.text),
            ),
          IconButton(
            tooltip: tr('reader_settings'),
            onPressed: _ready ? _openReaderSettings : null,
            icon: Icon(Icons.text_fields_rounded, color: t.text),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(3),
          child: ValueListenableBuilder<int>(
            valueListenable: _topIndexN,
            builder: (_, top, _) {
              final progress = _paragraphs.length <= 1
                  ? 1.0
                  : (top / (_paragraphs.length - 1)).clamp(0.0, 1.0);
              return TweenAnimationBuilder<double>(
                tween: Tween(end: progress),
                duration: const Duration(milliseconds: 300),
                builder: (_, v, _) => LinearProgressIndicator(
                  value: v,
                  minHeight: 3,
                  backgroundColor: t.faint.withValues(alpha: 0.18),
                  valueColor: AlwaysStoppedAnimation(t.accent),
                ),
              );
            },
          ),
        ),
      ),
      body: !_ready
          ? Center(child: CircularProgressIndicator(color: t.accent))
          : _reader(t),
    );
  }

  Widget _reader(ReaderTheme t) {
    final baseStyle = TextStyle(
      fontFamily: _settings.fontFamily,
      fontSize: 18 * _settings.fontScale,
      height: _settings.lineHeight,
      color: t.text,
    );
    // Горизонтальный режим — листаем страницы тапами слева/справа (как книгу).
    if (_settings.horizontalPaging) {
      final startOffset = _paragraphOffsets.isEmpty
          ? 0
          : _paragraphOffsets[
              _topIndex.clamp(0, _paragraphOffsets.length - 1)];
      return _PagedReader(
        key: ValueKey(
            'paged-${_settings.fontScale}-${_settings.lineHeight}-${_settings.font}'),
        fullText: _fullText,
        style: baseStyle,
        theme: t,
        known: _known,
        sessionAdded: _sessionAdded,
        knownVersion: _knownVersion,
        initialOffset: startOffset,
        onWord: (w, pageText) => _onWordTap(w, pageText),
        onParagraph: (offset) => _updateTop(_paragraphAtOffset(offset)),
        onPhrase: _onPhrase,
        normalize: _normalize,
        highlightMode: _settings.highlight,
      );
    }
    return Column(
      children: [
        Expanded(child: _scrollList(t, baseStyle)),
        ValueListenableBuilder<int>(
          valueListenable: _topIndexN,
          builder: (_, top, _) => _readFooter(
            t,
            _percentFor(top),
            _chapters.isEmpty ? null : _chapters[_chapterAt(top)].title,
          ),
        ),
      ],
    );
  }

  /// Прогресс чтения в процентах для абзаца, видимого сверху.
  int _percentFor(int top) {
    if (_paragraphs.length <= 1) return 100;
    return (top / (_paragraphs.length - 1) * 100).clamp(0, 100).round();
  }

  /// Нижняя плашка с процентом прочитанного + текущая глава (режим прокрутки).
  Widget _readFooter(ReaderTheme t, int percent, String? chapter) {
    final line = chapter == null || chapter.isEmpty
        ? trf('read_progress', {'p': percent})
        : '${trf('read_progress', {'p': percent})}  ·  $chapter';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20).copyWith(
        bottom: 8,
        top: 4,
      ),
      alignment: Alignment.center,
      child: Text(
        line,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontFamily: AppTheme.bodyFont,
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          color: t.faint,
        ),
      ),
    );
  }

  Widget _scrollList(ReaderTheme t, TextStyle baseStyle) {
    return ScrollablePositionedList.builder(
      itemScrollController: _scroll,
      itemPositionsListener: _positions,
      initialScrollIndex: _startIndex,
      padding: const EdgeInsets.fromLTRB(22, 14, 22, 120),
      itemCount: _paragraphs.length,
      itemBuilder: (context, i) {
        final para = _paragraphs[i];
        final bookmarked = _bookmarks.contains(i);
        final speaking = i == _speakingIndex;
        Widget content = Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: bookmarked
              ? BoxDecoration(
                  border: Border(
                    left: BorderSide(color: t.accent, width: 3),
                  ),
                )
              : null,
          child: Padding(
            padding: EdgeInsets.only(left: bookmarked ? 12 : 0),
            child: TappableText(
              key: ValueKey('p$i'),
              text: para,
              style: baseStyle,
              known: _known,
              sessionAdded: _sessionAdded,
              highlightVersion: _knownVersion,
              knownColor: t.accent,
              addedColor: t.added,
              highlightMode: _settings.highlight,
              onWord: (w) => _onWordTap(w, para),
              onPhrase: _onPhrase,
              normalize: _normalize,
            ),
          ),
        );
        // Подсветка абзаца, который сейчас читается вслух.
        if (speaking) {
          content = Container(
            decoration: BoxDecoration(
              color: t.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: content,
          );
        }
        // RepaintBoundary изолирует перерисовку абзаца — прокрутка не гоняет
        // растеризацию соседей.
        return RepaintBoundary(child: content);
      },
    );
  }

  // ------------------------------- Закладки: лист -------------------------------

  void _openBookmarks() {
    final t = _settings.theme;
    final sorted = _bookmarks.toList()..sort();
    showModalBottomSheet(
      context: context,
      backgroundColor: t.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _grabber(t),
              const SizedBox(height: 14),
              Text(
                tr('bookmarks'),
                style: TextStyle(
                  fontFamily: AppTheme.displayFont,
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                  color: t.text,
                ),
              ),
              const SizedBox(height: 12),
              if (sorted.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    tr('bookmarks_empty'),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: t.faint),
                  ),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: sorted.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final idx = sorted[i];
                      final snippet = _paragraphs[idx].length > 90
                          ? '${_paragraphs[idx].substring(0, 90)}…'
                          : _paragraphs[idx];
                      return Material(
                        color: t.faint.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(16),
                        clipBehavior: Clip.antiAlias,
                        child: ListTile(
                          leading: Icon(Icons.bookmark_rounded, color: t.accent),
                          title: Text(
                            snippet,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 13.5, color: t.text),
                          ),
                          onTap: () {
                            Navigator.pop(ctx);
                            _jumpTo(idx);
                          },
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ------------------------------- Главы -------------------------------

  /// Индекс текущей главы по абзацу [para] (последняя, начавшаяся до него).
  int _chapterAt(int para) {
    var idx = 0;
    for (var i = 0; i < _chapters.length; i++) {
      if (_chapters[i].startParagraph <= para) {
        idx = i;
      } else {
        break;
      }
    }
    return idx;
  }

  void _openChapters() {
    final t = _settings.theme;
    final current = _chapterAt(_topIndex);
    showModalBottomSheet(
      context: context,
      backgroundColor: t.background,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.72,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _grabber(t),
                const SizedBox(height: 14),
                Text(
                  tr('chapters'),
                  style: TextStyle(
                    fontFamily: AppTheme.displayFont,
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                    color: t.text,
                  ),
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _chapters.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 6),
                    itemBuilder: (_, i) {
                      final c = _chapters[i];
                      final isCurrent = i == current;
                      final isRead = c.startParagraph < _topIndex && !isCurrent;
                      return Material(
                        color: isCurrent
                            ? t.accent.withValues(alpha: 0.16)
                            : t.faint.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(14),
                        clipBehavior: Clip.antiAlias,
                        child: ListTile(
                          dense: true,
                          leading: Icon(
                            isCurrent
                                ? Icons.play_arrow_rounded
                                : isRead
                                    ? Icons.check_rounded
                                    : Icons.circle_outlined,
                            size: 18,
                            color: isCurrent ? t.accent : t.faint,
                          ),
                          title: Text(
                            c.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: isCurrent
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: t.text,
                            ),
                          ),
                          onTap: () {
                            Navigator.pop(ctx);
                            _jumpTo(c.startParagraph);
                          },
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ------------------------------- Настройки чтения -------------------------------

  void _openReaderSettings() {
    showModalBottomSheet(
      context: context,
      backgroundColor: _settings.theme.background,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => AnimatedBuilder(
        animation: _settings,
        builder: (ctx, _) => _ReaderSettingsSheet(settings: _settings),
      ),
    );
  }

  Widget _grabber(ReaderTheme t) => Center(
        child: Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: t.faint.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      );
}

/// Постраничная читалка (режим «как книга»): текст разбивается на страницы под
/// размер экрана; тап слева — назад, справа — вперёд; тап по слову — перевод.
/// Внизу — номер страницы.
class _PagedReader extends StatefulWidget {
  final String fullText;
  final TextStyle style;
  final ReaderTheme theme;
  final Set<String> known;
  final Set<String> sessionAdded;
  final int knownVersion;
  final int initialOffset;
  final void Function(String word, String pageText) onWord;
  final void Function(int startOffset) onParagraph;
  final ValueChanged<String> onPhrase;
  final String Function(String lower) normalize;
  final HighlightMode highlightMode;

  const _PagedReader({
    super.key,
    required this.fullText,
    required this.style,
    required this.theme,
    required this.known,
    required this.sessionAdded,
    required this.knownVersion,
    required this.initialOffset,
    required this.onWord,
    required this.onParagraph,
    required this.onPhrase,
    required this.normalize,
    required this.highlightMode,
  });

  @override
  State<_PagedReader> createState() => _PagedReaderState();
}

class _PagedReaderState extends State<_PagedReader> {
  static const double _hPad = 24;
  static const double _vPad = 14;

  PageController? _controller;
  List<int> _starts = const [0];
  String _sig = '';
  int _page = 0;

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  /// Разбивает текст на страницы: раскладывает целиком и режет по строкам,
  /// когда следующая строка не помещается в высоту страницы. Возвращает
  /// символьные смещения начала каждой страницы.
  List<int> _paginate(String text, TextStyle style, Size size) {
    if (text.isEmpty || size.width <= 0 || size.height <= 0) return const [0];
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: size.width);
    final lines = tp.computeLineMetrics();
    if (lines.isEmpty) return const [0];
    final starts = <int>[0];
    var pageTop = 0.0;
    for (final lm in lines) {
      final lineTop = lm.baseline - lm.ascent;
      final lineBottom = lm.baseline + lm.descent;
      if (lm.lineNumber > 0 && lineBottom - pageTop > size.height) {
        final off = tp
            .getPositionForOffset(Offset(1, lineTop + lm.height / 2))
            .offset;
        if (off > starts.last) {
          starts.add(off);
          pageTop = lineTop;
        }
      }
    }
    return starts;
  }

  int _pageForOffset(int offset) {
    var p = 0;
    for (var i = 0; i < _starts.length; i++) {
      if (_starts[i] <= offset) {
        p = i;
      } else {
        break;
      }
    }
    return p;
  }

  void _prev() {
    HapticFeedback.selectionClick();
    _controller?.previousPage(
      duration: const Duration(milliseconds: 240),
      curve: AppTheme.emphasizedDecelerate,
    );
  }

  void _next() {
    HapticFeedback.selectionClick();
    _controller?.nextPage(
      duration: const Duration(milliseconds: 240),
      curve: AppTheme.emphasizedDecelerate,
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final pageSize = Size(
          constraints.maxWidth - _hPad * 2,
          constraints.maxHeight - _vPad * 2 - 34, // место под номер страницы
        );
        final sig =
            '${constraints.maxWidth.toStringAsFixed(1)}x${constraints.maxHeight.toStringAsFixed(1)}'
            '-${widget.style.fontSize}-${widget.style.height}-${widget.style.fontFamily}';

        if (_controller == null) {
          _starts = _paginate(widget.fullText, widget.style, pageSize);
          _sig = sig;
          _page = _pageForOffset(widget.initialOffset);
          _controller = PageController(initialPage: _page);
        } else if (sig != _sig) {
          final curOffset = _starts[_page.clamp(0, _starts.length - 1)];
          _starts = _paginate(widget.fullText, widget.style, pageSize);
          _sig = sig;
          _page = _pageForOffset(curOffset);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && (_controller?.hasClients ?? false)) {
              _controller!.jumpToPage(_page);
            }
          });
        }

        final pages = _starts.length;
        return Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: pages,
                onPageChanged: (i) {
                  setState(() => _page = i);
                  widget.onParagraph(_starts[i]);
                },
                itemBuilder: (context, i) {
                  final start = _starts[i];
                  final end =
                      i + 1 < pages ? _starts[i + 1] : widget.fullText.length;
                  final pageText = widget.fullText.substring(start, end).trim();
                  return _pageView(pageText);
                },
              ),
            ),
            _pageNumber(pages),
          ],
        );
      },
    );
  }

  Widget _pageView(String pageText) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Тап-зоны листания ПОД текстом: тап по пустому месту слева/справа
        // проваливается сюда, а тап по слову ловит распознаватель слова сверху.
        Row(
          children: [
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _prev,
              ),
            ),
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _next,
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: _hPad, vertical: _vPad),
          child: Align(
            alignment: Alignment.topLeft,
            child: TappableText(
              text: pageText,
              style: widget.style,
              known: widget.known,
              sessionAdded: widget.sessionAdded,
              highlightVersion: widget.knownVersion,
              knownColor: widget.theme.accent,
              addedColor: widget.theme.added,
              highlightMode: widget.highlightMode,
              onWord: (w) => widget.onWord(w, pageText),
              onPhrase: widget.onPhrase,
              normalize: widget.normalize,
              // Тап мимо слова = листание: левая половина назад, правая вперёд.
              onMiss: (local, width) => local.dx < width / 2 ? _prev() : _next(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _pageNumber(int pages) {
    final percent =
        pages <= 1 ? 100 : (_page / (pages - 1) * 100).clamp(0, 100).round();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 2),
      child: Text(
        '${_page + 1} / $pages  ·  $percent%',
        style: TextStyle(
          fontFamily: AppTheme.bodyFont,
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          color: widget.theme.faint,
        ),
      ),
    );
  }
}

/// Панель настроек чтения: тема страницы, размер шрифта, интервал, шрифт.
class _ReaderSettingsSheet extends StatelessWidget {
  final ReaderSettings settings;
  const _ReaderSettingsSheet({required this.settings});

  @override
  Widget build(BuildContext context) {
    final t = settings.theme;
    final isRu = LocaleController.instance.code == 'ru';
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
                  color: t.faint.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            _label(tr('reader_mode'), t),
            const SizedBox(height: 8),
            _modeChoice(t),
            const SizedBox(height: 20),
            _label(tr('highlight_words'), t),
            const SizedBox(height: 8),
            _highlightChoice(t),
            const SizedBox(height: 20),
            _label(tr('reader_theme'), t),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (var i = 0; i < kReaderThemes.length; i++)
                  _themeSwatch(i, isRu, t),
              ],
            ),
            const SizedBox(height: 20),
            _label(tr('reader_font_size'), t),
            const SizedBox(height: 8),
            _stepper(
              t: t,
              value: '${(settings.fontScale * 100).round()}%',
              onMinus: () => settings.setFontScale(settings.fontScale - 0.1),
              onPlus: () => settings.setFontScale(settings.fontScale + 0.1),
              icon: Icons.format_size_rounded,
            ),
            const SizedBox(height: 16),
            _label(tr('reader_line_height'), t),
            const SizedBox(height: 8),
            _stepper(
              t: t,
              value: settings.lineHeight.toStringAsFixed(2),
              onMinus: () => settings.setLineHeight(settings.lineHeight - 0.1),
              onPlus: () => settings.setLineHeight(settings.lineHeight + 0.1),
              icon: Icons.format_line_spacing_rounded,
            ),
            const SizedBox(height: 20),
            _label(tr('reader_font'), t),
            const SizedBox(height: 8),
            _fontChoice(t),
          ],
        ),
      ),
    );
  }

  Widget _label(String text, ReaderTheme t) => Align(
        alignment: Alignment.centerLeft,
        child: Text(
          text,
          style: TextStyle(
            fontFamily: AppTheme.bodyFont,
            fontWeight: FontWeight.w600,
            fontSize: 13,
            color: t.faint,
          ),
        ),
      );

  Widget _themeSwatch(int i, bool isRu, ReaderTheme current) {
    final rt = kReaderThemes[i];
    final selected = i == settings.themeIndex;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        settings.setThemeIndex(i);
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: rt.background,
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? rt.accent : rt.faint.withValues(alpha: 0.4),
                width: selected ? 3 : 1.4,
              ),
            ),
            child: Center(
              child: Text(
                'Aa',
                style: TextStyle(
                  color: rt.text,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            isRu ? rt.labelRu : rt.labelEn,
            style: TextStyle(
              fontSize: 11,
              color: selected ? current.text : current.faint,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }

  Widget _stepper({
    required ReaderTheme t,
    required String value,
    required VoidCallback onMinus,
    required VoidCallback onPlus,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: t.faint.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, color: t.faint, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(value, style: TextStyle(color: t.text, fontSize: 14)),
          ),
          IconButton(
            onPressed: onMinus,
            icon: Icon(Icons.remove_circle_outline_rounded, color: t.text),
          ),
          IconButton(
            onPressed: onPlus,
            icon: Icon(Icons.add_circle_outline_rounded, color: t.text),
          ),
        ],
      ),
    );
  }

  Widget _modeChoice(ReaderTheme t) {
    Widget opt(bool paged, IconData icon, String label) {
      final selected = settings.horizontalPaging == paged;
      return Expanded(
        child: PressableScale(
          child: GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              settings.setHorizontalPaging(paged);
            },
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 3),
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: selected
                    ? t.accent.withValues(alpha: 0.18)
                    : t.faint.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: selected ? t.accent : Colors.transparent,
                  width: 1.6,
                ),
              ),
              child: Column(
                children: [
                  Icon(icon,
                      color: selected ? t.accent : t.text, size: 22),
                  const SizedBox(height: 6),
                  Text(
                    label,
                    style: TextStyle(
                      color: t.text,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        opt(false, Icons.swap_vert_rounded, tr('reader_mode_scroll')),
        opt(true, Icons.menu_book_rounded, tr('reader_mode_paged')),
      ],
    );
  }

  Widget _highlightChoice(ReaderTheme t) {
    Widget opt(HighlightMode mode, IconData icon, String label) {
      final selected = settings.highlight == mode;
      return Expanded(
        child: PressableScale(
          child: GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              settings.setHighlight(mode);
            },
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 3),
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: selected
                    ? t.accent.withValues(alpha: 0.18)
                    : t.faint.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: selected ? t.accent : Colors.transparent,
                  width: 1.6,
                ),
              ),
              child: Column(
                children: [
                  Icon(icon, color: selected ? t.accent : t.text, size: 20),
                  const SizedBox(height: 6),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: t.text,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        opt(HighlightMode.known, Icons.check_circle_outline_rounded,
            tr('highlight_known')),
        opt(HighlightMode.unknown, Icons.help_outline_rounded,
            tr('highlight_unknown')),
        opt(HighlightMode.off, Icons.format_clear_rounded, tr('highlight_off')),
      ],
    );
  }

  Widget _fontChoice(ReaderTheme t) {
    final opts = <(String, String)>[
      ('serif', tr('reader_font_serif')),
      ('sans', tr('reader_font_sans')),
      ('Onest', 'Onest'),
    ];
    return Row(
      children: [
        for (final o in opts) ...[
          Expanded(
            child: PressableScale(
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  settings.setFont(o.$1);
                },
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: settings.font == o.$1
                        ? t.accent.withValues(alpha: 0.18)
                        : t.faint.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: settings.font == o.$1
                          ? t.accent
                          : Colors.transparent,
                      width: 1.6,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      o.$2,
                      style: TextStyle(
                        fontFamily: o.$1 == 'serif'
                            ? 'serif'
                            : o.$1 == 'Onest'
                                ? 'Onest'
                                : null,
                        color: t.text,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
