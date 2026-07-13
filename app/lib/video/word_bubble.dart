import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../l10n/strings.dart';
import '../services/pos.dart';
import '../services/translation/translation_manager.dart';
import '../services/tts_service.dart';
import '../theme/app_theme.dart';
import '../widgets/pressable.dart';

/// Результат добавления слова в колоду (для сообщения пользователю).
enum AddResult { added, duplicate, cancelled }

/// Показывает «пузырь слова»: перевод с вариантами, озвучка (живой голос из
/// видео / робот), кнопка добавления в колоду.
Future<void> showWordBubble(
  BuildContext context, {
  required String word,
  required String sentence,
  required String sourceLang,
  required String targetLang,
  required YoutubePlayerController controller,
  required Duration sentStart,
  required Duration sentEnd,
  Duration? wordStart,
  Duration? wordEnd,
  required Future<AddResult> Function(
    String back,
    String example,
    int? clipStartMs,
    int? clipEndMs,
  ) onAdd,
}) {
  final scheme = Theme.of(context).colorScheme;
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: scheme.surfaceContainer,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => _WordBubble(
      word: word,
      sentence: sentence,
      sourceLang: sourceLang,
      targetLang: targetLang,
      controller: controller,
      sentStart: sentStart,
      sentEnd: sentEnd,
      wordStart: wordStart,
      wordEnd: wordEnd,
      onAdd: onAdd,
    ),
  );
}

class _WordBubble extends StatefulWidget {
  final String word;
  final String sentence;
  final String sourceLang;
  final String targetLang;
  final YoutubePlayerController controller;
  final Duration sentStart;
  final Duration sentEnd;
  final Duration? wordStart;
  final Duration? wordEnd;
  final Future<AddResult> Function(
    String back,
    String example,
    int? clipStartMs,
    int? clipEndMs,
  ) onAdd;

  const _WordBubble({
    required this.word,
    required this.sentence,
    required this.sourceLang,
    required this.targetLang,
    required this.controller,
    required this.sentStart,
    required this.sentEnd,
    required this.onAdd,
    this.wordStart,
    this.wordEnd,
  });

  @override
  State<_WordBubble> createState() => _WordBubbleState();
}

class _WordBubbleState extends State<_WordBubble> {
  bool _loading = true;
  String _back = '';
  List<String> _options = [];
  String? _pos;
  String? _phonetic;

  bool _live = true; // 🎬 живой голос по умолчанию (если доступен)
  Timer? _segTimer;
  AddResult? _addResult;

  bool get _wordLive => widget.wordStart != null && widget.wordEnd != null;

  /// Локализованное название части речи: сырую строку словаря («noun», «verb»)
  /// приводим к каноническому коду и берём перевод. Не распознали — показываем
  /// как пришло (лучше сырое, чем ничего).
  String? get _posLabel {
    final raw = _pos?.trim();
    if (raw == null || raw.isEmpty) return null;
    final code = PosDetect.fromDictionary(raw);
    return code == null ? raw : tr('pos_deck_$code');
  }

  @override
  void initState() {
    super.initState();
    _live = true;
    _translate();
  }

  @override
  void dispose() {
    _segTimer?.cancel();
    super.dispose();
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

  Future<void> _playSegment(Duration start, Duration end) async {
    final c = widget.controller;
    _segTimer?.cancel();
    await c.seekTo(seconds: start.inMilliseconds / 1000, allowSeekAhead: true);
    await c.playVideo();
    final dur = end - start;
    _segTimer = Timer(
      dur + const Duration(milliseconds: 150),
      () => c.pauseVideo(),
    );
  }

  Future<void> _speakWord() async {
    HapticFeedback.selectionClick();
    if (_live && _wordLive) {
      await _playSegment(widget.wordStart!, widget.wordEnd!);
    } else {
      await TtsService.instance.speak(widget.word, widget.sourceLang);
    }
  }

  Future<void> _speakSentence() async {
    HapticFeedback.selectionClick();
    if (_live) {
      await _playSegment(widget.sentStart, widget.sentEnd);
    } else {
      await TtsService.instance.speak(widget.sentence, widget.sourceLang);
    }
  }

  Future<void> _add() async {
    if (_back.trim().isEmpty) return;
    HapticFeedback.mediumImpact();
    final cs =
        (_wordLive ? widget.wordStart! : widget.sentStart).inMilliseconds;
    final ce = (_wordLive ? widget.wordEnd! : widget.sentEnd).inMilliseconds;
    final r = await widget.onAdd(_back.trim(), widget.sentence, cs, ce);
    if (!mounted) return;
    setState(() => _addResult = r);
    if (r != AddResult.cancelled) {
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
              // Слово + транскрипция.
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
              if (_posLabel != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    _posLabel!,
                    style: TextStyle(
                      fontFamily: AppTheme.bodyFont,
                      fontStyle: FontStyle.italic,
                      fontSize: 13,
                      color: scheme.primary,
                    ),
                  ),
                ),
              const SizedBox(height: 14),
              // Перевод / варианты.
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
              _audioControls(scheme),
              if (widget.sentence.isNotEmpty) ...[
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

  Widget _audioControls(ColorScheme scheme) {
    return Row(
      children: [
        // Тумблер живой/робот.
        SegmentedButton<bool>(
          style: const ButtonStyle(
            visualDensity: VisualDensity.compact,
          ),
          segments: [
            ButtonSegment(
              value: true,
              icon: const Icon(Icons.movie_rounded, size: 18),
              label: Text(tr('audio_live')),
            ),
            ButtonSegment(
              value: false,
              icon: const Icon(Icons.smart_toy_rounded, size: 18),
              label: Text(tr('audio_robot')),
            ),
          ],
          selected: {_live},
          onSelectionChanged: (s) => setState(() => _live = s.first),
        ),
        const Spacer(),
        IconButton.filledTonal(
          tooltip: tr('play_word'),
          onPressed: _speakWord,
          icon: const Icon(Icons.volume_up_rounded),
        ),
      ],
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
            Icon(Icons.play_circle_outline_rounded,
                size: 20, color: scheme.primary),
            const SizedBox(width: 10),
            Expanded(child: _highlightedSentence(scheme)),
          ],
        ),
      ),
    );
  }

  /// Предложение-контекст с выделенным изучаемым словом.
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
    if (idx < 0) {
      return Text(sentence, style: base);
    }
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
    final added = _addResult == AddResult.added;
    final dup = _addResult == AddResult.duplicate;
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
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          icon: Icon(added
              ? Icons.check_circle_rounded
              : dup
                  ? Icons.info_outline_rounded
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
