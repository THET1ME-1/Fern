import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'l10n/locale_controller.dart';
import 'l10n/strings.dart';
import 'language_picker_sheet.dart';
import 'models/deck.dart';
import 'models/word_card.dart';
import 'services/book_analysis.dart';
import 'services/deck_repository.dart';
import 'services/language_registry.dart';
import 'services/lemmatizer.dart';
import 'services/pos.dart';
import 'services/pro.dart';
import 'services/reading_goal.dart';
import 'services/reading_horizon.dart';
import 'services/reading_warmup.dart';
import 'services/source_library.dart';
import 'services/translation/translation_manager.dart';
import 'study/book_reader_screen.dart';
import 'study/session_screen.dart';
import 'study/study_models.dart';
import 'study/word_lookup_sheet.dart';
import 'theme/app_theme.dart';
import 'video/add_target.dart';
import 'widgets/batch_progress_dialog.dart';
import 'widgets/book_meta_editor.dart';
import 'widgets/goal_ring.dart';
import 'widgets/language_check_card.dart';
import 'widgets/pressable.dart';
import 'widgets/pro_sheet.dart';
import 'widgets/reading_goal_card.dart';
import 'widgets/reveal.dart';

/// Страница книги: обложка и метаданные, прогресс чтения, умный анализ словаря
/// (сколько слов читатель помнит / учит / не знает + покрытие текста), список
/// частых незнакомых слов для быстрого добавления, редактирование и удаление.
class BookScreen extends StatefulWidget {
  final LibrarySource source;
  const BookScreen({super.key, required this.source});

  @override
  State<BookScreen> createState() => _BookScreenState();
}

class _BookScreenState extends State<BookScreen> {
  // Цвета трёх групп анализа (не завязаны на схему — читаемы в любой теме).
  static const Color _knownColor = Color(0xFF2E9E6B);
  static const Color _learningColor = Color(0xFFDDA13F);
  static const Color _unknownColor = Color(0xFF5B8DEF);

  final SourceLibrary _library = SourceLibrary.instance;
  final DeckRepository _repo = DeckRepository.instance;
  // Дневной лимит новых слов: из него считается срок в пути к книге. Берётся
  // настоящий, а не круглый для витрины — обещание должно сбываться.
  int _newPerDay = 12;
  List<WordCard> _warmupCards = const [];

  late final LibrarySource _src = widget.source;
  String? _text;
  String? _lowerText;
  String? _coverPath;
  int _paraCount = 0;
  bool _loading = true;
  BookAnalysis? _analysis;
  bool _analyzing = false;
  // Разбор текста книги кэшируется: он не зависит от словаря, а стоит дорого.
  BookTokens? _tokens;
  Timer? _recomputeTimer;
  List<int> _chapterNew = const [];
  Deck? _targetDeck;

  // Мультивыбор в списке «учить в первую очередь».
  bool _selecting = false;
  final Set<String> _selected = {};

  String get _srcLang => _src.languageCode.split('-').first;

  @override
  void initState() {
    super.initState();
    _library.addListener(_onLibrary);
    _repo.addListener(_onRepo);
    _loadPace();
    _loadWarmup();
    _load();
  }

  @override
  void dispose() {
    _recomputeTimer?.cancel();
    _library.removeListener(_onLibrary);
    _repo.removeListener(_onRepo);
    super.dispose();
  }

  void _onLibrary() {
    if (mounted) setState(() {}); // прогресс/метаданные меняются in-place
  }

  /// Словарь изменился — пересчитать анализ, но не на каждое изменение подряд:
  /// пакетное добавление 20 слов слало 20 уведомлений и запускало 20 полных
  /// пересчётов, из-за чего приложение вставало колом.
  void _onRepo() {
    _recomputeTimer?.cancel();
    _recomputeTimer =
        Timer(const Duration(milliseconds: 350), () => _recompute());
  }

  /// Слова ближайших страниц, которые стоит повторить перед чтением.
  Future<void> _loadWarmup() async {
    if (!Pro.active) return;
    final horizon = await ReadingHorizon.upcoming(_srcLang);
    final cards = ReadingWarmup.pick(
      await _repo.cardsForLanguage(_srcLang),
      horizon,
      _srcLang,
    );
    if (mounted) setState(() => _warmupCards = cards);
  }

  Widget _warmupButton(ColorScheme scheme) {
    return OutlinedButton.icon(
      onPressed: _startWarmup,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(50),
        shape: const StadiumBorder(),
      ),
      icon: const Icon(Icons.bolt_rounded, size: 20),
      label: Text('${tr('warmup_title')} · ${_warmupCards.length}'),
    );
  }

  Future<void> _startWarmup() async {
    if (_warmupCards.isEmpty) return;
    HapticFeedback.selectionClick();
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SessionScreen(
          deck: _bookDeck,
          mode: StudyMode.learn,
          cards: _warmupCards,
        ),
      ),
    );
    _recompute();
    _loadWarmup();
  }

  /// Синтетическая колода книги: её слова лежат по разным колодам, а учить их
  /// хочется вместе — ради книги всё и затевалось.
  Deck get _bookDeck => Deck(
        id: 'book_${_src.id}',
        languageCode: _srcLang,
        name: _src.title,
        colorValue: 0xFF2E7D5B,
        shapeIndex: 0,
        createdAt: _src.createdAt,
      );

  Future<void> _loadPace() async {
    final pace = await _repo.newPerDay();
    if (mounted) setState(() => _newPerDay = pace);
  }

  /// Сессия по словам этой книги: карточки, чьи основы встречаются в тексте.
  ///
  /// Колода синтетическая, как у пака: слова книги обычно разбросаны по разным
  /// колодам, а учить их хочется вместе — ради книги всё и затевалось.
  Future<void> _studyBookWords() async {
    final tokens = _tokens;
    if (tokens == null) return;
    final stems = tokens.stems.toSet();
    final cards = [
      for (final card in await _repo.cardsForLanguage(_srcLang))
        if (stems.contains(Lemmatizer.stem(card.front, _srcLang))) card,
    ];
    if (!mounted) return;
    if (cards.isEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(tr('empty_deck_sub'))));
      return;
    }
    HapticFeedback.selectionClick();
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SessionScreen(
          deck: _bookDeck,
          mode: StudyMode.learn,
          cards: cards,
        ),
      ),
    );
    _recompute();
  }

  Future<void> _load() async {
    final text = await _library.loadBookText(_src.id);
    if (_src.hasCover) _coverPath = await _library.coverPath(_src.id);
    if (!mounted) return;
    setState(() {
      _text = text;
      _paraCount = text == null
          ? 0
          : text
                .split('\n')
                .map((p) => p.trim())
                .where((p) => p.isNotEmpty)
                .length;
      _loading = false;
    });
    _recompute();
  }

  /// Пересчитывает анализ словаря. Тяжёлая часть (токенизация книги) считается
  /// один раз в фоновом изоляте и кэшируется — дальше остаётся дешёвая сверка
  /// со словарём.
  Future<void> _recompute() async {
    final text = _text;
    if (text == null) return;
    if (mounted) setState(() => _analyzing = true);
    _tokens ??= await compute(prepareBookTokens, (text, _srcLang));
    final analysis = BookAnalysis.analyzeTokens(_tokens!, _srcLang);
    final chapterNew = _src.chapters.isEmpty
        ? const <int>[]
        : BookAnalysis.chapterUnknownCounts(
            text,
            [for (final c in _src.chapters) c.startParagraph],
            _srcLang,
          );
    if (!mounted) return;
    setState(() {
      _analysis = analysis;
      _chapterNew = chapterNew;
      _analyzing = false;
    });
    // Кэшируем долю знакомых слов для сортировки библиотеки.
    _library.setKnownPercent(_src.id, (analysis.coverage * 100).round());
  }

  // ------------------------------- Действия -------------------------------

  Future<void> _openReader() async {
    final text = _text;
    if (text == null) return;
    HapticFeedback.selectionClick();
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BookReaderScreen(
          sourceId: _src.id,
          title: _src.title,
          languageCode: _src.languageCode,
          text: text,
        ),
      ),
    );
    if (mounted) setState(() {}); // прогресс мог измениться
    _recompute();
  }

  Future<void> _edit() async {
    HapticFeedback.selectionClick();
    await showBookMetaEditor(context, _src);
    if (mounted) setState(() {});
    // Язык мог смениться, а основы слов считаются под язык — разбор больше не годен.
    _tokens = null;
    _recompute();
  }

  /// Быстрая смена языка книги из карточки-предупреждения (без полного редактора).
  Future<void> _changeLanguage() async {
    final code = await showLanguagePicker(context, _src.languageCode,
        unknownCode: _src.languageCode);
    if (code == null || code == _src.languageCode) return;
    await _library.updateBook(_src.id, languageCode: code);
    _targetDeck = null; // язык колоды-цели изменился — пере-выберем
    _tokens = null; // основы слов зависят от языка
    if (mounted) setState(() {});
    _recompute();
  }

  Future<void> _confirmDelete() async {
    HapticFeedback.mediumImpact();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('book_delete')),
        content: Text(tr('book_delete_confirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('delete')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _library.delete(_src.id);
    if (mounted) Navigator.pop(context);
  }

  /// Быстрое добавление слова из списка «учить в первую очередь».
  Future<void> _learnWord(String word) async {
    await showWordLookup(
      context,
      word: word,
      sentence: _contextFor(word),
      sourceLang: _srcLang,
      targetLang: LocaleController.instance.code,
      alreadyKnown: false,
      onAdd: (back, example, pos) => _addWord(word, back, example, pos),
    );
    _recompute();
  }

  Future<LookupAddResult> _addWord(
    String front,
    String back,
    String example,
    String? dictPos,
  ) async {
    _targetDeck ??= await VideoDeckTarget.resolveInSourcePack(
      context,
      _srcLang,
      _src.title,
    );
    final deck = _targetDeck;
    if (deck == null) return LookupAddResult.cancelled;
    final ok = await VideoDeckTarget.addWord(
      deck,
      front: front,
      back: back,
      example: example,
      sentence: example,
      pos: PosDetect.detect(front, dictPos: dictPos, languageCode: _srcLang),
    );
    if (!ok) return LookupAddResult.duplicate;
    await _library.bumpWordsAdded(_src.id);
    return LookupAddResult.added;
  }

  /// Предложение из книги, содержащее слово (контекст для перевода/примера).
  String _contextFor(String word) {
    final text = _text;
    if (text == null) return '';
    final lower = _lowerText ??= text.toLowerCase();
    final i = lower.indexOf(word.toLowerCase());
    if (i < 0) return '';
    const stops = '.!?…\n';
    var start = i;
    var end = i + word.length;
    while (start > 0 && !stops.contains(lower[start - 1])) {
      start--;
    }
    while (end < lower.length && !stops.contains(lower[end])) {
      end++;
    }
    final s = text.substring(start, end).trim();
    return s.length > 220 ? '' : s;
  }

  // ------------------------------- UI -------------------------------

  int get _readPercent {
    if (_paraCount <= 1) return _src.readParagraph > 0 ? 100 : 0;
    return (_src.readParagraph / (_paraCount - 1) * 100).clamp(0, 100).round();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(_src.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: tr('book_edit'),
            icon: const Icon(Icons.edit_outlined),
            onPressed: _edit,
          ),
          IconButton(
            tooltip: tr('book_delete'),
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: _confirmDelete,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          // Шапка строится сразу (не ждёт загрузку текста) — чтобы Hero-обложка
          // «долетела» из библиотеки и экран ощущался мгновенным.
          _header(scheme),
          const SizedBox(height: 16),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_text == null)
            _unavailable(scheme)
          else ...[
            Reveal(child: _readButton(scheme)),
            if (_warmupCards.isNotEmpty) ...[
              const SizedBox(height: 10),
              // Разминка стоит прямо под кнопкой чтения: она нужна ровно за
              // минуту до того, как человек откроет книгу.
              Reveal(
                delay: const Duration(milliseconds: 40),
                child: _warmupButton(scheme),
              ),
            ],
            const SizedBox(height: 20),
            Reveal(
              delay: const Duration(milliseconds: 60),
              child: _progressCard(scheme),
            ),
            const SizedBox(height: 16),
            Reveal(
              delay: const Duration(milliseconds: 85),
              child: LanguageCheckCard(
                languageCode: _src.languageCode,
                onChange: _changeLanguage,
              ),
            ),
            const SizedBox(height: 16),
            Reveal(
              delay: const Duration(milliseconds: 100),
              child: _analysisSection(scheme),
            ),
            if (_analysis != null && _analysis!.totalTokens > 0) ...[
              const SizedBox(height: 16),
              // Витрина Pro стоит здесь, сразу под разбором: человек только что
              // увидел, сколько слов книги знает, — и тут же узнаёт, сколько
              // осталось до чтения без словаря.
              Reveal(
                delay: const Duration(milliseconds: 115),
                child: ReadingGoalCard(
                  goal: ReadingGoal.estimate(_analysis!, newPerDay: _newPerDay),
                  pro: Pro.active,
                  newPerDay: _newPerDay,
                  onOpenPro: () => ProSheet.show(
                    context,
                    goal: ReadingGoal.estimate(_analysis!,
                        newPerDay: _newPerDay),
                  ),
                  onStudy: _studyBookWords,
                ),
              ),
            ],
            if (_src.chapters.isNotEmpty) ...[
              const SizedBox(height: 16),
              Reveal(
                delay: const Duration(milliseconds: 130),
                child: _chaptersCard(scheme),
              ),
            ],
            if (_src.description.isNotEmpty ||
                _src.genres.isNotEmpty ||
                _src.tags.isNotEmpty) ...[
              const SizedBox(height: 16),
              Reveal(
                delay: const Duration(milliseconds: 140),
                child: _aboutCard(scheme),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _unavailable(ColorScheme scheme) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Text(
        tr('book_no_text'),
        textAlign: TextAlign.center,
        style: TextStyle(color: scheme.onSurfaceVariant),
      ),
    ),
  );

  Widget _header(ColorScheme scheme) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Hero(
          tag: 'src-cover-${_src.id}',
          child: _coverWidget(scheme),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _src.title,
                style: TextStyle(
                  fontFamily: AppTheme.displayFont,
                  fontWeight: FontWeight.w800,
                  fontSize: 20,
                  height: 1.15,
                  color: scheme.onSurface,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _src.author.isEmpty ? tr('book_unknown_author') : _src.author,
                style: TextStyle(
                  fontFamily: AppTheme.bodyFont,
                  fontSize: 14,
                  fontStyle: _src.author.isEmpty
                      ? FontStyle.italic
                      : FontStyle.normal,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _metaLine(),
                style: TextStyle(
                  fontFamily: AppTheme.bodyFont,
                  fontSize: 12.5,
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.8),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _coverWidget(ColorScheme scheme) {
    const w = 76.0, h = 100.0;
    if (_coverPath != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Image.file(
          File(_coverPath!),
          width: w,
          height: h,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _coverPlaceholder(scheme, w, h),
        ),
      );
    }
    return _coverPlaceholder(scheme, w, h);
  }

  Widget _coverPlaceholder(ColorScheme scheme, double w, double h) => Container(
        width: w,
        height: h,
        decoration: BoxDecoration(
          color: scheme.tertiaryContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Icon(
          Icons.menu_book_rounded,
          size: 38,
          color: scheme.onTertiaryContainer,
        ),
      );

  String _metaLine() {
    final parts = <String>[];
    final lang = LanguageRegistry.instance.byCode(_src.languageCode);
    if (lang != null) parts.add('${lang.emoji} ${lang.name}');
    if (_src.format != null) parts.add(_src.format!.toUpperCase());
    final words = _analysis?.totalTokens ?? 0;
    if (words > 0) parts.add(trf('words_n', {'n': _grouped(words)}));
    parts.add(_dateStr(_src.createdAt));
    return parts.join('  ·  ');
  }

  Widget _readButton(ColorScheme scheme) {
    final started = _src.readParagraph > 0 && _readPercent < 100;
    return SizedBox(
      width: double.infinity,
      child: PressableScale(
        child: FilledButton.icon(
          onPressed: _openReader,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          icon: Icon(
            started ? Icons.play_arrow_rounded : Icons.auto_stories_rounded,
          ),
          label: Text(
            started ? tr('read_continue') : tr('read_start'),
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          ),
        ),
      ),
    );
  }

  Widget _progressCard(ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          GoalRing(
            progress: _readPercent / 100,
            size: 68,
            strokeWidth: 7,
            color: scheme.primary,
            trackColor: scheme.surfaceContainerHighest,
            child: _animatedInt(
              _readPercent,
              TextStyle(
                fontFamily: AppTheme.displayFont,
                fontWeight: FontWeight.w800,
                fontSize: 15,
                color: scheme.onSurface,
              ),
              suffix: '%',
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr('book_reading_progress'),
                  style: TextStyle(
                    fontFamily: AppTheme.displayFont,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  trf('read_progress', {'p': _readPercent}),
                  style: TextStyle(
                    fontFamily: AppTheme.bodyFont,
                    fontSize: 13,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                if (_src.bookmarks.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    trf('book_bookmarks_n', {'n': _src.bookmarks.length}),
                    style: TextStyle(
                      fontFamily: AppTheme.bodyFont,
                      fontSize: 12.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --------------------------- Анализ словаря ---------------------------

  Widget _analysisSection(ColorScheme scheme) {
    final a = _analysis;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.insights_rounded, size: 20, color: scheme.primary),
              const SizedBox(width: 8),
              Text(
                tr('book_analysis_title'),
                style: TextStyle(
                  fontFamily: AppTheme.displayFont,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  color: scheme.onSurface,
                ),
              ),
              const Spacer(),
              if (_analyzing)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (a == null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text(
                  tr('analyzing'),
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ),
            )
          else ...[
            _coverageRow(scheme, a),
            const SizedBox(height: 18),
            _bucketBar(scheme, a),
            const SizedBox(height: 14),
            _bucketLegend(scheme, a),
            const SizedBox(height: 16),
            _vocabLine(scheme, a),
            if (a.topUnknown.isNotEmpty) ...[
              const SizedBox(height: 20),
              _studyFirst(scheme, a),
            ],
          ],
        ],
      ),
    );
  }

  Widget _coverageRow(ColorScheme scheme, BookAnalysis a) {
    final cov = (a.coverage * 100).round();
    return Row(
      children: [
        GoalRing(
          progress: a.coverage,
          size: 72,
          strokeWidth: 8,
          color: _knownColor,
          trackColor: scheme.surfaceContainerHighest,
          child: _animatedInt(
            cov,
            TextStyle(
              fontFamily: AppTheme.displayFont,
              fontWeight: FontWeight.w800,
              fontSize: 16,
              color: scheme.onSurface,
            ),
            suffix: '%',
          ),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                trf('book_coverage', {'p': cov}),
                style: TextStyle(
                  fontFamily: AppTheme.displayFont,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  height: 1.2,
                  color: scheme.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                tr('book_coverage_sub'),
                style: TextStyle(
                  fontFamily: AppTheme.bodyFont,
                  fontSize: 12.5,
                  height: 1.3,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _bucketBar(ColorScheme scheme, BookAnalysis a) {
    if (a.uniqueTypes == 0) return const SizedBox.shrink();
    return _SegmentBar(
      segments: [
        (a.knownTypes, _knownColor),
        (a.learningTypes, _learningColor),
        (a.unknownTypes, _unknownColor),
      ],
      track: scheme.surfaceContainerHighest,
    );
  }

  Widget _bucketLegend(ColorScheme scheme, BookAnalysis a) {
    // IntrinsicHeight даёт Row ограниченную высоту — иначе stretch в Column
    // тянет плитки на бесконечную высоту и ломает всю карточку.
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _bucketTile(
              scheme,
              _knownColor,
              a.knownTypes,
              tr('analysis_known'),
              tr('analysis_known_sub'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _bucketTile(
              scheme,
              _learningColor,
              a.learningTypes,
              tr('analysis_learning'),
              tr('analysis_learning_sub'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _bucketTile(
              scheme,
              _unknownColor,
              a.unknownTypes,
              tr('analysis_unknown'),
              tr('analysis_unknown_sub'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bucketTile(
    ColorScheme scheme,
    Color color,
    int count,
    String label,
    String sub,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(height: 8),
          _animatedInt(
            count,
            TextStyle(
              fontFamily: AppTheme.displayFont,
              fontWeight: FontWeight.w800,
              fontSize: 20,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontFamily: AppTheme.bodyFont,
              fontWeight: FontWeight.w700,
              fontSize: 12.5,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            sub,
            style: TextStyle(
              fontFamily: AppTheme.bodyFont,
              fontSize: 10.5,
              height: 1.2,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _vocabLine(ColorScheme scheme, BookAnalysis a) {
    final share = (a.dictionaryShare * 100).round();
    return Row(
      children: [
        Icon(Icons.abc_rounded, size: 18, color: scheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            trf('book_vocab_line', {
              'unique': _grouped(a.uniqueTypes),
              'indict': _grouped(a.inDictionaryTypes),
              'share': share,
            }),
            style: TextStyle(
              fontFamily: AppTheme.bodyFont,
              fontSize: 12.5,
              height: 1.35,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }

  Widget _studyFirst(ColorScheme scheme, BookAnalysis a) {
    final words = a.topUnknown.take(24).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr('book_study_first'),
                    style: TextStyle(
                      fontFamily: AppTheme.displayFont,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: scheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _selecting
                        ? tr('tap_to_select')
                        : tr('book_study_first_sub'),
                    style: TextStyle(
                      fontFamily: AppTheme.bodyFont,
                      fontSize: 11.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: () => setState(() {
                _selecting = !_selecting;
                _selected.clear();
              }),
              child: Text(_selecting ? tr('cancel') : tr('select')),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final w in words)
              if (_selecting)
                FilterChip(
                  label: Text('${w.word}  ·  ${w.count}'),
                  labelStyle: TextStyle(
                    fontFamily: AppTheme.bodyFont,
                    fontSize: 13,
                    color: scheme.onSurface,
                  ),
                  selected: _selected.contains(w.word),
                  showCheckmark: true,
                  backgroundColor: _unknownColor.withValues(alpha: 0.10),
                  selectedColor: _unknownColor.withValues(alpha: 0.28),
                  side: BorderSide(color: _unknownColor.withValues(alpha: 0.3)),
                  onSelected: (sel) => setState(() {
                    if (sel) {
                      _selected.add(w.word);
                    } else {
                      _selected.remove(w.word);
                    }
                  }),
                )
              else
                ActionChip(
                  label: Text('${w.word}  ·  ${w.count}'),
                  labelStyle: TextStyle(
                    fontFamily: AppTheme.bodyFont,
                    fontSize: 13,
                    color: scheme.onSurface,
                  ),
                  avatar: Icon(Icons.add_rounded, size: 18, color: scheme.primary),
                  backgroundColor: _unknownColor.withValues(alpha: 0.10),
                  side: BorderSide(color: _unknownColor.withValues(alpha: 0.3)),
                  onPressed: () => _learnWord(w.word),
                ),
          ],
        ),
        const SizedBox(height: 12),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 240),
          switchInCurve: AppTheme.emphasizedDecelerate,
          transitionBuilder: (child, anim) =>
              FadeTransition(opacity: anim, child: child),
          child: _selecting
              ? SizedBox(
                  key: const ValueKey('sel'),
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _selected.isEmpty
                        ? null
                        : () => _batchAdd(_selected.toList()),
                    icon: const Icon(Icons.playlist_add_rounded, size: 20),
                    label: Text(
                      trf('add_selected_n', {'n': _selected.length}),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                )
              : SizedBox(
                  key: const ValueKey('all'),
                  width: double.infinity,
                  child: FilledButton.tonalIcon(
                    onPressed: () =>
                        _batchAdd([for (final w in words) w.word]),
                    icon: const Icon(Icons.done_all_rounded, size: 20),
                    label: Text(
                      trf('add_all_n', {'n': words.length}),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  /// Пакетно переводит и добавляет слова в пак книги (без открытия карточки
  /// на каждое). Показывает прогресс, можно отменить.
  Future<void> _batchAdd(List<String> words) async {
    if (words.isEmpty) return;
    HapticFeedback.selectionClick();
    _targetDeck ??= await VideoDeckTarget.resolveInSourcePack(
      context,
      _srcLang,
      _src.title,
    );
    final deck = _targetDeck;
    if (deck == null || !mounted) return;

    final progress = ValueNotifier<int>(0);
    final cancelled = ValueNotifier<bool>(false);
    // Диалог мог уже закрыться (отмена) — тогда закрывать его повторно нельзя,
    // иначе pop снесёт сам экран книги.
    var dialogOpen = true;
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => BatchProgressDialog(
          total: words.length,
          progress: progress,
          onCancel: () => cancelled.value = true,
        ),
      ).whenComplete(() => dialogOpen = false),
    );

    final tgt = LocaleController.instance.code;
    var added = 0;
    for (var i = 0; i < words.length; i++) {
      if (cancelled.value) break;
      final w = words[i];
      final res = await TranslationManager.instance
          .translate(w, _srcLang, tgt, context: _contextFor(w));
      if (res != null && res.primary.trim().isNotEmpty) {
        final ok = await VideoDeckTarget.addWord(
          deck,
          front: w,
          back: res.primary,
          example: _contextFor(w),
          sentence: _contextFor(w),
          pos: PosDetect.detect(
            w,
            dictPos: res.partOfSpeech,
            languageCode: _srcLang,
          ),
        );
        if (ok) {
          added++;
          await _library.bumpWordsAdded(_src.id);
        }
      }
      progress.value = i + 1;
    }

    progress.dispose();
    cancelled.dispose();
    if (mounted) {
      if (dialogOpen) Navigator.of(context, rootNavigator: true).pop();
      setState(() {
        _selecting = false;
        _selected.clear();
      });
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(trf('added_n_cards', {'n': added}))),
        );
    }
    _recompute();
  }

  // ------------------------------- Главы -------------------------------

  int _currentChapterIndex() {
    final para = _src.readParagraph;
    var idx = 0;
    final ch = _src.chapters;
    for (var i = 0; i < ch.length; i++) {
      if (ch[i].startParagraph <= para) {
        idx = i;
      } else {
        break;
      }
    }
    return idx;
  }

  Widget _chaptersCard(ColorScheme scheme) {
    final chapters = _src.chapters;
    final currentIdx = _src.readParagraph > 0 ? _currentChapterIndex() : -1;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.toc_rounded, size: 20, color: scheme.primary),
              const SizedBox(width: 8),
              Text(
                tr('chapters'),
                style: TextStyle(
                  fontFamily: AppTheme.displayFont,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  color: scheme.onSurface,
                ),
              ),
              const Spacer(),
              Text(
                '${chapters.length}',
                style: TextStyle(
                  fontFamily: AppTheme.displayFont,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (var i = 0; i < chapters.length; i++)
            _chapterTile(scheme, i, currentIdx),
        ],
      ),
    );
  }

  Widget _chapterTile(ColorScheme scheme, int i, int currentIdx) {
    final c = _src.chapters[i];
    final isCurrent = i == currentIdx;
    final isRead = currentIdx >= 0 && i < currentIdx;
    final newCount = i < _chapterNew.length ? _chapterNew[i] : -1;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: PressableScale(
        child: Material(
          color: isCurrent
              ? scheme.primary.withValues(alpha: 0.10)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => _openChapterInReader(c.startParagraph),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
              child: Row(
                children: [
                  Icon(
                    isCurrent
                        ? Icons.play_arrow_rounded
                        : isRead
                            ? Icons.check_circle_rounded
                            : Icons.circle_outlined,
                    size: 18,
                    color: isCurrent
                        ? scheme.primary
                        : isRead
                            ? _knownColor
                            : scheme.onSurfaceVariant.withValues(alpha: 0.6),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      c.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: AppTheme.bodyFont,
                        fontSize: 14,
                        fontWeight:
                            isCurrent ? FontWeight.w700 : FontWeight.w500,
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                  if (newCount > 0) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: _unknownColor.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        trf('chapter_new_words', {'n': newCount}),
                        style: TextStyle(
                          fontFamily: AppTheme.bodyFont,
                          fontWeight: FontWeight.w600,
                          fontSize: 11,
                          color: _unknownColor,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openChapterInReader(int startParagraph) async {
    final text = _text;
    if (text == null) return;
    HapticFeedback.selectionClick();
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BookReaderScreen(
          sourceId: _src.id,
          title: _src.title,
          languageCode: _src.languageCode,
          text: text,
          initialParagraph: startParagraph,
        ),
      ),
    );
    if (mounted) setState(() {});
    _recompute();
  }

  // ------------------------------- О книге -------------------------------

  Widget _aboutCard(ColorScheme scheme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr('book_about'),
            style: TextStyle(
              fontFamily: AppTheme.displayFont,
              fontWeight: FontWeight.w700,
              fontSize: 16,
              color: scheme.onSurface,
            ),
          ),
          if (_src.description.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              _src.description,
              style: TextStyle(
                fontFamily: AppTheme.bodyFont,
                fontSize: 13.5,
                height: 1.45,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
          if (_src.genres.isNotEmpty) ...[
            const SizedBox(height: 14),
            _tagWrap(scheme, tr('book_genres'), _src.genres, scheme.primary),
          ],
          if (_src.tags.isNotEmpty) ...[
            const SizedBox(height: 12),
            _tagWrap(scheme, tr('book_tags'), _src.tags, scheme.tertiary),
          ],
        ],
      ),
    );
  }

  Widget _tagWrap(
    ColorScheme scheme,
    String label,
    List<String> values,
    Color color,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontFamily: AppTheme.bodyFont,
            fontWeight: FontWeight.w600,
            fontSize: 12,
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final v in values)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Text(
                  v,
                  style: TextStyle(
                    fontFamily: AppTheme.bodyFont,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  // ------------------------------- Утилиты -------------------------------

  /// Целое, которое «набегает» от 0 при появлении и при смене значения (M3).
  Widget _animatedInt(int value, TextStyle style, {String suffix = ''}) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value.toDouble()),
      duration: const Duration(milliseconds: 800),
      curve: AppTheme.emphasizedDecelerate,
      builder: (_, v, _) =>
          Text('${_grouped(v.round())}$suffix', maxLines: 1, style: style),
    );
  }

  /// Число с разделением тысяч пробелом (1 234).
  String _grouped(int n) {
    final s = n.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  String _dateStr(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.day)}.${two(d.month)}.${d.year}';
  }
}

/// Диалог прогресса пакетного добавления слов (перевод + добавление по одному).
/// Полоса-разбивка на цветные сегменты по счётчикам, «набегает» слева при
/// появлении (M3). Каждый сегмент — своей ширины пропорционально числу.
class _SegmentBar extends StatelessWidget {
  final List<(int, Color)> segments;
  final Color track;
  const _SegmentBar({required this.segments, required this.track});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 850),
      curve: AppTheme.emphasizedDecelerate,
      builder: (_, t, _) => SizedBox(
        height: 12,
        width: double.infinity,
        child: CustomPaint(
          painter: _SegmentBarPainter(segments: segments, track: track, t: t),
        ),
      ),
    );
  }
}

class _SegmentBarPainter extends CustomPainter {
  final List<(int, Color)> segments;
  final Color track;
  final double t;
  _SegmentBarPainter({
    required this.segments,
    required this.track,
    required this.t,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final full = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(size.height / 2),
    );
    canvas.drawRRect(full, Paint()..color = track);

    final total = segments.fold<int>(0, (s, e) => s + e.$1);
    if (total <= 0) return;

    canvas.save();
    canvas.clipRRect(full);
    final revealed = size.width * t;
    var x = 0.0;
    for (final (count, color) in segments) {
      if (count <= 0) continue;
      final w = size.width * count / total;
      final clipped = Rect.fromLTWH(
        x,
        0,
        w,
        size.height,
      ).intersect(Rect.fromLTWH(0, 0, revealed, size.height));
      if (clipped.width > 0) canvas.drawRect(clipped, Paint()..color = color);
      x += w;
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SegmentBarPainter old) =>
      old.t != t || old.track != track || !_same(old.segments, segments);

  bool _same(List<(int, Color)> a, List<(int, Color)> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].$1 != b[i].$1 || a[i].$2 != b[i].$2) return false;
    }
    return true;
  }
}
