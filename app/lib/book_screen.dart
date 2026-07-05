import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'l10n/locale_controller.dart';
import 'l10n/strings.dart';
import 'models/deck.dart';
import 'services/book_analysis.dart';
import 'services/deck_repository.dart';
import 'services/source_library.dart';
import 'study/book_reader_screen.dart';
import 'study/word_lookup_sheet.dart';
import 'theme/app_theme.dart';
import 'video/add_target.dart';
import 'widgets/book_meta_editor.dart';
import 'widgets/goal_ring.dart';
import 'widgets/pressable.dart';
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

  late final LibrarySource _src = widget.source;
  String? _text;
  String? _lowerText;
  int _paraCount = 0;
  bool _loading = true;
  BookAnalysis? _analysis;
  bool _analyzing = false;
  Deck? _targetDeck;

  String get _srcLang => _src.languageCode.split('-').first;

  @override
  void initState() {
    super.initState();
    _library.addListener(_onLibrary);
    _repo.addListener(_onRepo);
    _load();
  }

  @override
  void dispose() {
    _library.removeListener(_onLibrary);
    _repo.removeListener(_onRepo);
    super.dispose();
  }

  void _onLibrary() {
    if (mounted) setState(() {}); // прогресс/метаданные меняются in-place
  }

  void _onRepo() => _recompute(); // словарь изменился — пересчитать анализ

  Future<void> _load() async {
    final text = await _library.loadBookText(_src.id);
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

  /// Пересчитывает анализ словаря (после кадра — чтобы не тормозить отрисовку).
  Future<void> _recompute() async {
    final text = _text;
    if (text == null) return;
    if (mounted) setState(() => _analyzing = true);
    await Future<void>.delayed(Duration.zero);
    final analysis = BookAnalysis.analyze(text, _srcLang);
    if (!mounted) return;
    setState(() {
      _analysis = analysis;
      _analyzing = false;
    });
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
      onAdd: (back, example) => _addWord(word, back, example),
    );
    _recompute();
  }

  Future<LookupAddResult> _addWord(
    String front,
    String back,
    String example,
  ) async {
    _targetDeck ??=
        await VideoDeckTarget.resolveInSourcePack(context, _srcLang, _src.title);
    final deck = _targetDeck;
    if (deck == null) return LookupAddResult.cancelled;
    final ok = await VideoDeckTarget.addWord(
      deck,
      front: front,
      back: back,
      example: example,
      sentence: example,
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
        title: Text(
          _src.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
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
            const SizedBox(height: 20),
            Reveal(
              delay: const Duration(milliseconds: 60),
              child: _progressCard(scheme),
            ),
            const SizedBox(height: 16),
            Reveal(
              delay: const Duration(milliseconds: 100),
              child: _analysisSection(scheme),
            ),
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
          child: Container(
            width: 76,
            height: 100,
            decoration: BoxDecoration(
              color: scheme.tertiaryContainer,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              Icons.menu_book_rounded,
              size: 38,
              color: scheme.onTertiaryContainer,
            ),
          ),
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
                  fontStyle:
                      _src.author.isEmpty ? FontStyle.italic : FontStyle.normal,
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

  String _metaLine() {
    final parts = <String>[];
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
          icon: Icon(started
              ? Icons.play_arrow_rounded
              : Icons.auto_stories_rounded),
          label: Text(
            started ? tr('read_continue') : tr('read_start'),
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: _bucketTile(scheme, _knownColor, a.knownTypes,
              tr('analysis_known'), tr('analysis_known_sub')),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _bucketTile(scheme, _learningColor, a.learningTypes,
              tr('analysis_learning'), tr('analysis_learning_sub')),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _bucketTile(scheme, _unknownColor, a.unknownTypes,
              tr('analysis_unknown'), tr('analysis_unknown_sub')),
        ),
      ],
    );
  }

  Widget _bucketTile(ColorScheme scheme, Color color, int count, String label,
      String sub) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(width: 10, height: 10,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
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
    return Column(
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
          tr('book_study_first_sub'),
          style: TextStyle(
            fontFamily: AppTheme.bodyFont,
            fontSize: 11.5,
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final w in a.topUnknown.take(24))
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
      ],
    );
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
      ColorScheme scheme, String label, List<String> values, Color color) {
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
      builder: (_, v, _) => Text(
        '${_grouped(v.round())}$suffix',
        maxLines: 1,
        style: style,
      ),
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
      final clipped = Rect.fromLTWH(x, 0, w, size.height)
          .intersect(Rect.fromLTWH(0, 0, revealed, size.height));
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
