import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/locale_controller.dart';
import '../l10n/strings.dart';
import '../models/deck.dart';
import '../services/construction_catalog.dart';
import '../services/constructions.dart';
import '../services/deck_repository.dart';
import '../services/pos.dart';
import '../services/reply_hints.dart';
import '../services/text_analysis.dart';
import '../services/translation/translation_manager.dart';
import '../services/tts_service.dart';
import '../study/word_lookup_sheet.dart';
import '../theme/app_theme.dart';
import '../video/add_target.dart';
import '../widgets/empty_state.dart';
import '../widgets/morph_shapes.dart';
import '../widgets/pressable.dart';
import '../widgets/reveal.dart';
import 'rule_card_tile.dart';

/// Экран «Ответ»: черновик на родном языке — перевод на изучаемый — разбор
/// собственного ответа.
///
/// Продолжение разбора чужого сообщения: понять написанное это полдела, дальше
/// надо ответить. Заодно словарь перестаёт быть складом: видно, какие свои
/// слова пошли в дело и какое выученное слово просилось вместо простого.
class ReplyScreen extends StatefulWidget {
  const ReplyScreen({super.key});

  @override
  State<ReplyScreen> createState() => _ReplyScreenState();
}

class _ReplyScreenState extends State<ReplyScreen> {
  final TextEditingController _controller = TextEditingController();
  final DeckRepository _repo = DeckRepository.instance;

  String _lang = 'en';
  String _translation = '';
  TextAnalysis? _analysis;
  ReplyHints _hints = ReplyHints.empty;
  List<ConstructionHit> _hits = const [];
  bool _busy = false;
  Deck? _target;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _lang = await _repo.selectedLanguageCode() ?? 'en';
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _translate() async {
    final draft = _controller.text.trim();
    if (draft.isEmpty || _busy) return;
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    await ConstructionCatalog.instance.ensureLoaded(_lang);
    final res = await TranslationManager.instance.translate(
      draft,
      LocaleController.instance.code,
      _lang,
    );
    final text = res?.primary.trim() ?? '';
    if (!mounted) return;
    if (text.isEmpty) {
      setState(() => _busy = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(tr('translate_failed'))));
      return;
    }
    final analysis = TextParse.analyze(text, _lang);
    setState(() {
      _translation = text;
      _analysis = analysis;
      _hints = ReplyAnalysis.of(analysis, _lang);
      _hits = Constructions.find(analysis, _lang);
      _busy = false;
    });
  }

  Future<Deck?> _deck() async {
    if (_target != null) return _target;
    final deck = await VideoDeckTarget.resolveInSourcePack(
        context, _lang, tr('reply_source_pack'));
    _target = deck;
    return deck;
  }

  Future<void> _addWord(String word) async {
    final analysis = _analysis;
    final sentence = analysis == null
        ? ''
        : (analysis.sentences.isNotEmpty ? analysis.sentences.first.text : '');
    await showWordLookup(
      context,
      word: word,
      sentence: sentence,
      sourceLang: _lang,
      targetLang: LocaleController.instance.code,
      alreadyKnown: false,
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
        if (ok && mounted && _analysis != null) {
          setState(() {
            _hints = ReplyAnalysis.of(_analysis!, _lang);
          });
        }
        return ok ? LookupAddResult.added : LookupAddResult.duplicate;
      },
    );
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _translation));
    if (!mounted) return;
    HapticFeedback.selectionClick();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(tr('reply_copied'))));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(tr('reply_title'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _draft(scheme),
          const SizedBox(height: 16),
          if (_busy)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(28),
                child: Waiting(size: 34),
              ),
            )
          else if (_translation.isEmpty)
            EmptyState(
              icon: Icons.reply_rounded,
              title: tr('reply_empty_title'),
              subtitle: tr('reply_empty_sub'),
            )
          else
            ..._result(scheme),
        ],
      ),
    );
  }

  Widget _draft(ColorScheme scheme) {
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
            maxLines: 5,
            minLines: 2,
            style: TextStyle(
              fontFamily: AppTheme.bodyFont,
              fontSize: 16,
              height: 1.4,
              color: scheme.onSurface,
            ),
            decoration: InputDecoration(
              hintText: tr('reply_hint'),
              border: InputBorder.none,
            ),
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: PressableScale(
              child: FilledButton.icon(
                onPressed: _busy ? null : _translate,
                icon: const Icon(Icons.east_rounded, size: 18),
                label: Text(tr('reply_build')),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _result(ColorScheme scheme) {
    final rules = <(Construction, String)>[];
    final seen = <String>{};
    for (final h in _hits) {
      if (!seen.add(h.code)) continue;
      final rule = ConstructionCatalog.instance.byCode(h.code, _lang);
      if (rule != null) rules.add((rule, h.snippet));
    }

    return [
      Reveal(child: _translationCard(scheme)),
      if (_hints.upgrades.isNotEmpty) ...[
        const SizedBox(height: 22),
        _sectionTitle(tr('reply_upgrades'), scheme),
        const SizedBox(height: 4),
        Text(
          tr('reply_upgrades_sub'),
          style: TextStyle(
            fontFamily: AppTheme.bodyFont,
            fontSize: 12.5,
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 10),
        for (final u in _hints.upgrades) _upgradeRow(u, scheme),
      ],
      if (_hints.fresh.isNotEmpty) ...[
        const SizedBox(height: 22),
        _sectionTitle(tr('reply_fresh'), scheme),
        const SizedBox(height: 4),
        Text(
          tr('reply_fresh_sub'),
          style: TextStyle(
            fontFamily: AppTheme.bodyFont,
            fontSize: 12.5,
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final w in _hints.fresh)
              ActionChip(label: Text(w), onPressed: () => _addWord(w)),
          ],
        ),
      ],
      if (rules.isNotEmpty) ...[
        const SizedBox(height: 22),
        _sectionTitle(tr('reply_rules'), scheme),
        const SizedBox(height: 10),
        for (final (rule, snippet) in rules) ...[
          RuleCardTile(rule: rule, snippet: snippet),
          const SizedBox(height: 10),
        ],
      ],
    ];
  }

  Widget _translationCard(ColorScheme scheme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _translation,
            style: TextStyle(
              fontFamily: AppTheme.wordFont,
              fontWeight: FontWeight.w600,
              fontSize: 19,
              height: 1.4,
              color: scheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              IconButton(
                tooltip: tr('play_word'),
                onPressed: () =>
                    TtsService.instance.speak(_translation, _lang),
                icon: const Icon(Icons.volume_up_rounded),
                color: scheme.onPrimaryContainer,
              ),
              IconButton(
                tooltip: tr('reply_copy'),
                onPressed: _copy,
                icon: const Icon(Icons.copy_rounded),
                color: scheme.onPrimaryContainer,
              ),
              const Spacer(),
              Text(
                trf('reply_used_n', {'n': '${_hints.used.length}'}),
                style: TextStyle(
                  fontFamily: AppTheme.bodyFont,
                  fontSize: 12.5,
                  color: scheme.onPrimaryContainer.withValues(alpha: 0.85),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _upgradeRow(WordUpgrade u, ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            Text(
              u.used,
              style: TextStyle(
                fontFamily: AppTheme.wordFont,
                fontSize: 15,
                color: scheme.onSurfaceVariant,
                decoration: TextDecoration.lineThrough,
              ),
            ),
            const SizedBox(width: 10),
            Icon(Icons.arrow_forward_rounded,
                size: 16, color: scheme.onSurfaceVariant),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                u.better.front,
                style: TextStyle(
                  fontFamily: AppTheme.wordFont,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  color: scheme.primary,
                ),
              ),
            ),
          ],
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

