import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/strings.dart';
import '../services/translation/translation_manager.dart';
import '../services/tts_service.dart';
import '../theme/app_theme.dart';
import '../widgets/pressable.dart';

/// Результат добавления слова в колоду.
enum LookupAddResult { added, duplicate, cancelled }

/// «Пузырь слова» для текстовых источников (книги): перевод с вариантами,
/// озвучка роботом (TTS), кнопка добавления в колоду. В отличие от видео-версии
/// не требует плеера — работает где угодно.
Future<void> showWordLookup(
  BuildContext context, {
  required String word,
  required String sentence,
  required String sourceLang,
  required String targetLang,
  required bool alreadyKnown,
  required Future<LookupAddResult> Function(String back, String example) onAdd,
}) {
  final scheme = Theme.of(context).colorScheme;
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: scheme.surfaceContainer,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => _WordLookup(
      word: word,
      sentence: sentence,
      sourceLang: sourceLang,
      targetLang: targetLang,
      alreadyKnown: alreadyKnown,
      onAdd: onAdd,
    ),
  );
}

class _WordLookup extends StatefulWidget {
  final String word;
  final String sentence;
  final String sourceLang;
  final String targetLang;
  final bool alreadyKnown;
  final Future<LookupAddResult> Function(String back, String example) onAdd;

  const _WordLookup({
    required this.word,
    required this.sentence,
    required this.sourceLang,
    required this.targetLang,
    required this.alreadyKnown,
    required this.onAdd,
  });

  @override
  State<_WordLookup> createState() => _WordLookupState();
}

class _WordLookupState extends State<_WordLookup> {
  bool _loading = true;
  String _back = '';
  List<String> _options = [];
  String? _pos;
  String? _phonetic;
  LookupAddResult? _addResult;

  @override
  void initState() {
    super.initState();
    _translate();
  }

  Future<void> _translate() async {
    final res = await TranslationManager.instance.translate(
      widget.word,
      widget.sourceLang,
      widget.targetLang,
      context: widget.sentence.isEmpty ? null : widget.sentence,
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res != null) {
        _back = res.primary;
        _options = res.options;
        _pos = res.partOfSpeech;
        _phonetic = res.phonetic;
      }
    });
  }

  Future<void> _speak() async {
    HapticFeedback.selectionClick();
    await TtsService.instance.speak(widget.word, widget.sourceLang);
  }

  Future<void> _speakSentence() async {
    HapticFeedback.selectionClick();
    await TtsService.instance.speak(widget.sentence, widget.sourceLang);
  }

  Future<void> _add() async {
    if (_back.trim().isEmpty) return;
    HapticFeedback.mediumImpact();
    final r = await widget.onAdd(_back.trim(), widget.sentence);
    if (!mounted) return;
    setState(() => _addResult = r);
    if (r != LookupAddResult.cancelled) {
      await Future.delayed(const Duration(milliseconds: 650));
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
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
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Flexible(
                    child: Text(
                      widget.word,
                      style: TextStyle(
                        fontFamily: AppTheme.displayFont,
                        fontWeight: FontWeight.w800,
                        fontSize: 26,
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                  if (_phonetic != null && _phonetic!.isNotEmpty) ...[
                    const SizedBox(width: 10),
                    Text(
                      _phonetic!,
                      style: TextStyle(
                        fontFamily: AppTheme.bodyFont,
                        fontSize: 15,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
              if (_pos != null && _pos!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    _pos!,
                    style: TextStyle(
                      fontFamily: AppTheme.bodyFont,
                      fontStyle: FontStyle.italic,
                      fontSize: 13,
                      color: scheme.primary,
                    ),
                  ),
                ),
              if (widget.alreadyKnown) ...[
                const SizedBox(height: 10),
                _knownChip(scheme),
              ],
              const SizedBox(height: 14),
              if (_loading)
                Row(
                  children: [
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      tr('translating'),
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ],
                )
              else if (_back.isEmpty)
                Text(
                  tr('translate_failed'),
                  style: TextStyle(color: scheme.error),
                )
              else ...[
                Text(
                  _back,
                  style: TextStyle(
                    fontFamily: AppTheme.displayFont,
                    fontWeight: FontWeight.w700,
                    fontSize: 20,
                    color: scheme.primary,
                  ),
                ),
                if (_options.length > 1) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (final o in _options)
                        ChoiceChip(
                          label: Text(o),
                          selected: _back == o,
                          visualDensity: VisualDensity.compact,
                          onSelected: (_) {
                            HapticFeedback.selectionClick();
                            setState(() => _back = o);
                          },
                        ),
                    ],
                  ),
                ],
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  FilledButton.tonalIcon(
                    onPressed: _speak,
                    icon: const Icon(Icons.volume_up_rounded, size: 20),
                    label: Text(tr('play_word')),
                  ),
                ],
              ),
              if (widget.sentence.isNotEmpty &&
                  widget.sentence != widget.word) ...[
                const SizedBox(height: 14),
                _sentenceView(scheme),
              ],
              const SizedBox(height: 18),
              _addButton(scheme),
            ],
          ),
        ),
      ),
    );
  }

  Widget _knownChip(ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle_rounded,
              size: 16, color: scheme.onTertiaryContainer),
          const SizedBox(width: 6),
          Text(
            tr('word_already_known'),
            style: TextStyle(
              fontFamily: AppTheme.bodyFont,
              fontWeight: FontWeight.w600,
              fontSize: 12.5,
              color: scheme.onTertiaryContainer,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sentenceView(ColorScheme scheme) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: _speakSentence,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.volume_up_rounded, size: 20, color: scheme.primary),
            const SizedBox(width: 10),
            Expanded(child: _highlightedSentence(scheme)),
          ],
        ),
      ),
    );
  }

  Widget _highlightedSentence(ColorScheme scheme) {
    final sentence = widget.sentence;
    final lower = sentence.toLowerCase();
    final w = widget.word.toLowerCase();
    final idx = lower.indexOf(w);
    final base = TextStyle(
      fontFamily: AppTheme.bodyFont,
      fontSize: 13.5,
      height: 1.4,
      color: scheme.onSurfaceVariant,
    );
    if (idx < 0) return Text(sentence, style: base);
    return RichText(
      text: TextSpan(
        style: base,
        children: [
          TextSpan(text: sentence.substring(0, idx)),
          TextSpan(
            text: sentence.substring(idx, idx + w.length),
            style: base.copyWith(
              fontWeight: FontWeight.w800,
              color: scheme.primary,
            ),
          ),
          TextSpan(text: sentence.substring(idx + w.length)),
        ],
      ),
    );
  }

  Widget _addButton(ColorScheme scheme) {
    final added = _addResult == LookupAddResult.added;
    final dup = _addResult == LookupAddResult.duplicate || widget.alreadyKnown;
    return SizedBox(
      width: double.infinity,
      child: PressableScale(
        child: FilledButton.icon(
          onPressed: (_loading || _back.isEmpty || _addResult != null)
              ? null
              : _add,
          style: FilledButton.styleFrom(
            backgroundColor: added
                ? scheme.tertiary
                : dup
                    ? scheme.surfaceContainerHighest
                    : scheme.primary,
            foregroundColor: dup && !added ? scheme.onSurface : null,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          icon: Icon(added
              ? Icons.check_circle_rounded
              : dup
                  ? Icons.check_rounded
                  : Icons.add_rounded),
          label: Text(
            added
                ? tr('added')
                : dup
                    ? tr('already_in_deck')
                    : tr('add_to_deck'),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ),
    );
  }
}
