import 'dart:async';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/locale_controller.dart';
import '../l10n/strings.dart';
import '../language_picker_sheet.dart';
import '../models/deck.dart';
import '../services/book_analysis.dart';
import '../services/deck_repository.dart';
import '../services/language_registry.dart';
import '../services/pos.dart';
import '../services/source_library.dart';
import '../services/translation/translation_manager.dart';
import '../study/word_lookup_sheet.dart';
import '../theme/app_theme.dart';
import '../widgets/batch_progress_dialog.dart';
import '../widgets/goal_ring.dart';
import '../widgets/language_check_card.dart';
import '../widgets/pressable.dart';
import '../widgets/reveal.dart';
import 'add_target.dart';
import 'subtitle.dart';
import 'video_study_screen.dart';

/// Страница видео (аналог страницы книги): превью и метаданные, проверка языка,
/// умный анализ словаря субтитров (сколько слов зритель помнит / учит / не знает
/// + покрытие) и список частых незнакомых слов для быстрого добавления. Кнопка
/// «Смотреть и учить» открывает караоке-разбор ([VideoStudyScreen]).
class VideoScreen extends StatefulWidget {
  final LibrarySource source;
  const VideoScreen({super.key, required this.source});

  @override
  State<VideoScreen> createState() => _VideoScreenState();
}

class _VideoScreenState extends State<VideoScreen> {
  static const Color _knownColor = Color(0xFF2E9E6B);
  static const Color _learningColor = Color(0xFFDDA13F);
  static const Color _unknownColor = Color(0xFF5B8DEF);

  final SourceLibrary _library = SourceLibrary.instance;
  final DeckRepository _repo = DeckRepository.instance;

  late LibrarySource _src = widget.source;
  VideoTranscript? _transcript;
  String? _text;
  String? _lowerText;
  bool _loading = true;
  BookAnalysis? _analysis;
  bool _analyzing = false;
  BookTokens? _tokens;
  Timer? _recomputeTimer;
  Deck? _targetDeck;

  bool _selecting = false;
  final Set<String> _selected = {};

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
    _recomputeTimer?.cancel();
    _library.removeListener(_onLibrary);
    _repo.removeListener(_onRepo);
    super.dispose();
  }

  void _onLibrary() {
    if (mounted) setState(() {});
  }

  /// Словарь изменился. Коалесим: пакетное добавление слов слало уведомление на
  /// каждое слово, и анализ субтитров пересчитывался столько же раз подряд.
  void _onRepo() {
    _recomputeTimer?.cancel();
    _recomputeTimer =
        Timer(const Duration(milliseconds: 350), () => _recompute());
  }

  Future<void> _load() async {
    final t = await _library.loadVideo(_src.id);
    if (!mounted) return;
    setState(() {
      _transcript = t;
      _text = t == null
          ? null
          : [for (final l in t.lines) l.text].join('\n');
      _loading = false;
    });
    _recompute();
  }

  Future<void> _recompute() async {
    final text = _text;
    if (text == null) return;
    if (mounted) setState(() => _analyzing = true);
    // Разбор субтитров не зависит от словаря — считаем один раз в фоне.
    _tokens ??= await compute(prepareBookTokens, (text, _srcLang));
    final analysis = BookAnalysis.analyzeTokens(_tokens!, _srcLang);
    if (!mounted) return;
    setState(() {
      _analysis = analysis;
      _analyzing = false;
    });
    _library.setKnownPercent(_src.id, (analysis.coverage * 100).round());
  }

  // ------------------------------- Действия -------------------------------

  Future<void> _watch() async {
    final t = _transcript;
    if (t == null) return;
    HapticFeedback.selectionClick();
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VideoStudyScreen(
          transcript: t,
          sourceId: _src.id,
          languageOverride: _src.languageCode,
        ),
      ),
    );
    // Могли добавить слова / сменить прогресс — обновим.
    final fresh = await _library.get(_src.id);
    if (fresh != null && mounted) setState(() => _src = fresh);
    _recompute();
  }

  Future<void> _changeLanguage() async {
    final code = await showLanguagePicker(context, _src.languageCode,
        unknownCode: _src.languageCode);
    if (code == null || code == _src.languageCode) return;
    await _library.updateBook(_src.id, languageCode: code);
    final fresh = await _library.get(_src.id);
    if (fresh != null && mounted) setState(() => _src = fresh);
    _targetDeck = null; // язык колоды-цели изменился — пере-выберем
    _tokens = null; // основы слов зависят от языка — разбор больше не годен
    _recompute();
  }

  Future<void> _confirmDelete() async {
    HapticFeedback.mediumImpact();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('video_delete')),
        content: Text(tr('video_delete_confirm')),
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
      sourceUrl: _transcript?.url ?? _src.url ?? '',
      pos: PosDetect.detect(front, dictPos: dictPos, languageCode: _srcLang),
    );
    if (!ok) return LookupAddResult.duplicate;
    await _library.bumpWordsAdded(_src.id);
    return LookupAddResult.added;
  }

  /// Реплика субтитров, содержащая слово (контекст для перевода/примера).
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(_src.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: tr('video_delete'),
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: _confirmDelete,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
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
            Reveal(child: _watchButton(scheme)),
            const SizedBox(height: 16),
            Reveal(
              delay: const Duration(milliseconds: 60),
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
          ],
        ],
      ),
    );
  }

  Widget _unavailable(ColorScheme scheme) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            tr('video_no_transcript'),
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
        ),
      );

  Widget _header(ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _thumbnail(scheme),
        const SizedBox(height: 14),
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
    );
  }

  Widget _thumbnail(ColorScheme scheme) {
    final vid = _src.videoId ?? _transcript?.videoId;
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (vid != null)
              Image.network(
                'https://img.youtube.com/vi/$vid/hqdefault.jpg',
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _thumbPlaceholder(scheme),
              )
            else
              _thumbPlaceholder(scheme),
            Container(color: Colors.black.withValues(alpha: 0.18)),
            Center(
              child: Icon(
                Icons.play_circle_fill_rounded,
                size: 58,
                color: Colors.white.withValues(alpha: 0.92),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _thumbPlaceholder(ColorScheme scheme) => Container(
        color: scheme.primaryContainer,
        alignment: Alignment.center,
        child: Icon(
          Icons.smart_display_rounded,
          size: 48,
          color: scheme.onPrimaryContainer,
        ),
      );

  String _metaLine() {
    final parts = <String>[];
    final lang = LanguageRegistry.instance.byCode(_src.languageCode);
    if (lang != null) parts.add('${lang.emoji} ${lang.name}');
    final words = _analysis?.totalTokens ?? 0;
    if (words > 0) parts.add(trf('words_n', {'n': _grouped(words)}));
    if (_src.wordsAdded > 0) {
      parts.add(trf('source_words_added', {'n': _src.wordsAdded}));
    }
    parts.add(_dateStr(_src.createdAt));
    return parts.join('  ·  ');
  }

  Widget _watchButton(ColorScheme scheme) {
    return SizedBox(
      width: double.infinity,
      child: PressableScale(
        child: FilledButton.icon(
          onPressed: _watch,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          icon: const Icon(Icons.play_arrow_rounded),
          label: Text(
            tr('video_open_study'),
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          ),
        ),
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
    return IntrinsicHeight(
      child: Row(
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
      ),
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
                    _selecting ? tr('tap_to_select') : tr('book_study_first_sub'),
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
                  avatar:
                      Icon(Icons.add_rounded, size: 18, color: scheme.primary),
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
                    onPressed: () => _batchAdd([for (final w in words) w.word]),
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
    final url = _transcript?.url ?? _src.url ?? '';
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
          sourceUrl: url,
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

  // ------------------------------- Утилиты -------------------------------

  Widget _animatedInt(int value, TextStyle style, {String suffix = ''}) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value.toDouble()),
      duration: const Duration(milliseconds: 800),
      curve: AppTheme.emphasizedDecelerate,
      builder: (_, v, _) =>
          Text('${_grouped(v.round())}$suffix', maxLines: 1, style: style),
    );
  }

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

/// Диалог прогресса пакетного добавления слов.
/// Полоса-разбивка на цветные сегменты, «набегает» слева при появлении.
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
  _SegmentBarPainter(
      {required this.segments, required this.track, required this.t});

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
