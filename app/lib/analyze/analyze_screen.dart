import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/locale_controller.dart';
import '../l10n/strings.dart';
import '../models/deck.dart';
import '../services/construction_catalog.dart';
import '../services/constructions.dart';
import '../services/deck_repository.dart';
import '../services/grammar_deck.dart';
import '../services/lemmatizer.dart';
import '../services/pos.dart';
import '../services/source_library.dart';
import '../services/text_analysis.dart';
import '../services/translation/translation_manager.dart';
import '../study/reader_settings.dart' show HighlightMode;
import '../study/tappable_text.dart';
import '../study/word_lookup_sheet.dart';
import '../theme/app_theme.dart';
import '../video/add_target.dart';
import '../widgets/batch_progress_dialog.dart';
import '../widgets/empty_state.dart';
import '../widgets/morph_shapes.dart';
import '../widgets/pressable.dart';
import '../widgets/reveal.dart';
import 'reply_screen.dart';
import 'rule_card_tile.dart';

/// Экран «Разбор»: вставил чужое сообщение — получил перевод, слова по статусу
/// и грамматику этого самого текста.
///
/// Отличие от разбора книги: там частоты и «что учить в первую очередь», здесь
/// текст читается целиком и на своих местах. Сюда же приходит текст из системного
/// «Поделиться» и из меню выделения в чужом приложении.
class AnalyzeScreen extends StatefulWidget {
  /// Текст, с которым экран открыли (из «Поделиться» или меню выделения).
  final String? initialText;

  const AnalyzeScreen({super.key, this.initialText});

  @override
  State<AnalyzeScreen> createState() => _AnalyzeScreenState();
}

class _AnalyzeScreenState extends State<AnalyzeScreen> {
  final TextEditingController _controller = TextEditingController();
  final DeckRepository _repo = DeckRepository.instance;

  /// Разбор длиннее этого сохраняется книгой, а не заметкой: это уже не
  /// сообщение из чата, и место ему в Библиотеке по общим правилам.
  static const int _snippetLimit = 1200;

  String _lang = 'en';
  TextAnalysis? _analysis;
  List<ConstructionHit> _hits = const [];
  String _translation = '';
  bool _busy = false;
  bool _translating = false;
  int _highlight = 0;
  final Set<String> _added = {};
  final Set<String> _learnedRules = {};
  Deck? _target;

  @override
  void initState() {
    super.initState();
    _controller.text = widget.initialText ?? '';
    _init();
  }

  Future<void> _init() async {
    _lang = await _repo.selectedLanguageCode() ?? 'en';
    if (!mounted) return;
    setState(() {});
    if (_controller.text.trim().isNotEmpty) _run();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // ------------------------------- Разбор -------------------------------

  Future<void> _run() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _busy) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _translation = '';
    });
    await ConstructionCatalog.instance.ensureLoaded(_lang);
    final analysis = TextParse.analyze(text, _lang);
    final hits = Constructions.find(analysis, _lang);
    if (!mounted) return;
    setState(() {
      _analysis = analysis;
      _hits = hits;
      _busy = false;
      _translating = true;
    });
    // Перевод идёт отдельно и позже: движок может быть офлайн-моделью или
    // сервером, а разбор по словам обязан появиться сразу.
    final res = await TranslationManager.instance.translate(
      text,
      _lang,
      LocaleController.instance.code,
    );
    if (!mounted) return;
    setState(() {
      _translation = res?.primary ?? '';
      _translating = false;
    });
  }

  /// Правила, найденные в тексте, без повторов: одно правило показывается раз,
  /// с первым своим оборотом.
  List<(Construction, String)> get _rules {
    final seen = <String>{};
    final out = <(Construction, String)>[];
    for (final h in _hits) {
      if (!seen.add(h.code)) continue;
      final rule = ConstructionCatalog.instance.byCode(h.code, _lang);
      if (rule != null) out.add((rule, h.snippet));
    }
    return out;
  }

  // ------------------------------- Слова -------------------------------

  Future<Deck?> _deck() async {
    if (_target != null) return _target;
    if (!mounted) return null;
    final deck = await VideoDeckTarget.resolveInSourcePack(
        context, _lang, tr('analyze_source_pack'));
    _target = deck;
    return deck;
  }

  Future<void> _openWord(String word) async {
    final analysis = _analysis;
    if (analysis == null) return;
    final lower = word.toLowerCase();
    final stem = Lemmatizer.stem(lower, _lang);
    final token = analysis.tokens
        .where((t) => t.surface.toLowerCase() == lower)
        .firstOrNull;
    final sentence = token == null ? '' : analysis.sentenceOf(token);
    final known = token?.status == WordStatus.known ||
        token?.status == WordStatus.learning ||
        _added.contains(stem);
    if (!mounted) return;
    await showWordLookup(
      context,
      word: word,
      sentence: sentence,
      sourceLang: _lang,
      targetLang: LocaleController.instance.code,
      alreadyKnown: known,
      onAdd: (back, example, pos) async {
        final deck = await _deck();
        if (deck == null) return LookupAddResult.cancelled;
        final ok = await VideoDeckTarget.addWord(
          deck,
          front: word,
          back: back,
          example: example,
          sentence: sentence,
          pos: PosDetect.detect(word, dictPos: pos, languageCode: _lang),
        );
        if (ok && mounted) {
          setState(() {
            _added.add(stem);
            _highlight++;
          });
        }
        return ok ? LookupAddResult.added : LookupAddResult.duplicate;
      },
    );
  }

  /// Добавляет все незнакомые слова разом: перевод каждого плюс карточка.
  Future<void> _addAllUnknown() async {
    final analysis = _analysis;
    if (analysis == null) return;
    final words = [
      for (final w in analysis.unknownWords)
        if (!_added.contains(Lemmatizer.stem(w, _lang))) w,
    ];
    if (words.isEmpty) return;
    final deck = await _deck();
    if (deck == null || !mounted) return;

    final progress = ValueNotifier<int>(0);
    var cancelled = false;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => BatchProgressDialog(
        total: words.length,
        progress: progress,
        onCancel: () => cancelled = true,
      ),
    );
    final ui = LocaleController.instance.code;
    var added = 0;
    for (final word in words) {
      if (cancelled) break;
      final token = analysis.tokens
          .where((t) => t.surface.toLowerCase() == word)
          .firstOrNull;
      final sentence = token == null ? '' : analysis.sentenceOf(token);
      final res = await TranslationManager.instance
          .translate(word, _lang, ui, context: sentence);
      final back = res?.primary.trim() ?? '';
      if (back.isNotEmpty) {
        final ok = await VideoDeckTarget.addWord(
          deck,
          front: word,
          back: back,
          example: sentence,
          sentence: sentence,
          pos: PosDetect.detect(word,
              dictPos: res?.partOfSpeech, languageCode: _lang),
        );
        if (ok) {
          added++;
          _added.add(Lemmatizer.stem(word, _lang));
        }
      }
      progress.value++;
    }
    if (!mounted) return;
    Navigator.pop(context);
    setState(() => _highlight++);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(trn('n_words_added', added))));
  }

  // ------------------------------- Правила -------------------------------

  Future<void> _learnRule(Construction rule, String snippet) async {
    final analysis = _analysis;
    final hit = _hits.where((h) => h.code == rule.code).firstOrNull;
    final example = hit != null && analysis != null
        ? analysis.sentences[hit.sentence].text
        : (rule.examples.isNotEmpty ? rule.examples.first : snippet);
    await GrammarDeck.add(
      languageCode: _lang,
      code: rule.code,
      name: rule.name,
      hint: rule.hint(),
      example: example,
    );
    if (!mounted) return;
    setState(() => _learnedRules.add(rule.code));
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(tr('rule_added'))));
  }

  // ------------------------------ Сохранение ------------------------------

  Future<void> _save() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    final id = await SourceLibrary.instance.saveBook(
      title: _title(text),
      languageCode: _lang,
      format: text.length > _snippetLimit ? 'txt' : 'snip',
      text: text,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(id == null ? tr('save_failed') : tr('analyze_saved')),
      ));
  }

  String _title(String text) {
    final words = text.split(RegExp(r'\s+')).take(6).join(' ');
    return words.length > 50 ? '${words.substring(0, 50)}…' : words;
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty || !mounted) return;
    setState(() => _controller.text = text);
    _run();
  }

  // -------------------------------- Экран --------------------------------

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('analyze_title')),
        actions: [
          IconButton(
            tooltip: tr('reply_title'),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ReplyScreen()),
            ),
            icon: const Icon(Icons.reply_rounded),
          ),
          if (_analysis != null)
            IconButton(
              tooltip: tr('save'),
              onPressed: _save,
              icon: const Icon(Icons.bookmark_add_rounded),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _input(scheme),
          const SizedBox(height: 16),
          if (_busy)
            const Center(child: Padding(
              padding: EdgeInsets.all(28),
              child: Waiting(size: 34),
            ))
          else if (_analysis == null)
            EmptyState(
              icon: Icons.translate_rounded,
              title: tr('analyze_empty_title'),
              subtitle: tr('analyze_empty_sub'),
            )
          else
            ..._result(scheme, _analysis!),
        ],
      ),
    );
  }

  Widget _input(ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _controller,
            maxLines: 6,
            minLines: 3,
            textInputAction: TextInputAction.newline,
            style: TextStyle(
              fontFamily: AppTheme.wordFont,
              fontSize: 16,
              height: 1.4,
              color: scheme.onSurface,
            ),
            decoration: InputDecoration(
              hintText: tr('analyze_hint'),
              border: InputBorder.none,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              TextButton.icon(
                onPressed: _paste,
                icon: const Icon(Icons.content_paste_rounded, size: 18),
                label: Text(tr('analyze_paste')),
              ),
              const Spacer(),
              PressableScale(
                child: FilledButton.icon(
                  onPressed: _busy ? null : _run,
                  icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                  label: Text(tr('analyze_run')),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _result(ColorScheme scheme, TextAnalysis a) {
    final known = <String>{
      for (final t in a.tokens)
        if (t.status == WordStatus.known || t.status == WordStatus.learning)
          t.lemma,
    };
    final rules = _rules;
    final unknownLeft = [
      for (final w in a.unknownWords)
        if (!_added.contains(Lemmatizer.stem(w, _lang))) w,
    ];

    return [
      Reveal(child: _stats(scheme, a)),
      const SizedBox(height: 16),
      Reveal(
        delay: const Duration(milliseconds: 60),
        child: _textCard(scheme, a, known),
      ),
      if (_translating || _translation.isNotEmpty) ...[
        const SizedBox(height: 12),
        Reveal(
          delay: const Duration(milliseconds: 90),
          child: _translationCard(scheme),
        ),
      ],
      if (unknownLeft.isNotEmpty) ...[
        const SizedBox(height: 20),
        _sectionTitle(tr('analyze_unknown'), scheme),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final w in unknownLeft)
              ActionChip(
                label: Text(w),
                onPressed: () => _openWord(w),
              ),
          ],
        ),
        const SizedBox(height: 12),
        PressableScale(
          child: FilledButton.tonalIcon(
            onPressed: _addAllUnknown,
            icon: const Icon(Icons.playlist_add_rounded, size: 20),
            label: Text(trf('analyze_add_all', {'n': '${unknownLeft.length}'})),
          ),
        ),
      ],
      if (rules.isNotEmpty) ...[
        const SizedBox(height: 24),
        _sectionTitle(tr('analyze_rules'), scheme),
        const SizedBox(height: 10),
        for (final (rule, snippet) in rules) ...[
          RuleCardTile(
            rule: rule,
            snippet: snippet,
            learned: _learnedRules.contains(rule.code) ||
                GrammarDeck.find(rule.code, _lang) != null,
            onLearn: () => _learnRule(rule, snippet),
          ),
          const SizedBox(height: 10),
        ],
      ],
    ];
  }

  Widget _stats(ColorScheme scheme, TextAnalysis a) {
    final total = a.totalWords;
    Widget cell(String label, int n, Color color) => Expanded(
          child: Column(
            children: [
              Text(
                '$n',
                style: TextStyle(
                  fontFamily: AppTheme.displayFont,
                  fontWeight: FontWeight.w700,
                  fontSize: 22,
                  color: color,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: AppTheme.bodyFont,
                  fontSize: 12,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        );

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          Text(
            trf('analyze_coverage', {
              'p': '${(a.coverage * 100).round()}',
            }),
            style: TextStyle(
              fontFamily: AppTheme.bodyFont,
              fontSize: 13,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              cell(tr('analysis_known'), a.knownCount, scheme.primary),
              cell(tr('analysis_learning'), a.learningCount, scheme.tertiary),
              cell(tr('analysis_unknown'), a.unknownCount, scheme.onSurface),
              cell(tr('analyze_words'), total, scheme.onSurfaceVariant),
            ],
          ),
        ],
      ),
    );
  }

  Widget _textCard(ColorScheme scheme, TextAnalysis a, Set<String> known) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(24),
      ),
      child: TappableText(
        text: a.text,
        style: TextStyle(
          fontFamily: AppTheme.wordFont,
          fontSize: 18,
          height: 1.5,
          color: scheme.onSurface,
        ),
        known: known,
        sessionAdded: _added,
        highlightVersion: _highlight,
        knownColor: scheme.primary,
        addedColor: scheme.tertiary,
        highlightMode: HighlightMode.known,
        normalize: (w) => Lemmatizer.stem(w, _lang),
        onWord: _openWord,
      ),
    );
  }

  Widget _translationCard(ColorScheme scheme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 15),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(22),
      ),
      child: _translating
          ? Row(
              children: [
                const Waiting(size: 18),
                const SizedBox(width: 12),
                Text(
                  tr('translating'),
                  style: TextStyle(
                    fontFamily: AppTheme.bodyFont,
                    color: scheme.onSecondaryContainer,
                  ),
                ),
              ],
            )
          : Text(
              _translation,
              style: TextStyle(
                fontFamily: AppTheme.bodyFont,
                fontSize: 15,
                height: 1.4,
                color: scheme.onSecondaryContainer,
              ),
            ),
    );
  }

  Widget _sectionTitle(String text, ColorScheme scheme) => Text(
        text,
        style: TextStyle(
          fontFamily: AppTheme.displayFont,
          fontWeight: FontWeight.w700,
          fontSize: 17,
          color: scheme.onSurface,
        ),
      );
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}

