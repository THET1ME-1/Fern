import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../l10n/locale_controller.dart';
import '../l10n/strings.dart';
import '../language_picker_sheet.dart';
import '../models/deck.dart';
import '../services/deck_repository.dart';
import '../services/ocr_service.dart';
import '../services/pos.dart';
import '../services/translation/translation_manager.dart';
import '../study/word_lookup_sheet.dart';
import '../theme/app_theme.dart';
import '../video/add_target.dart';
import '../widgets/language_check_card.dart';
import '../widgets/pressable.dart';
import '../widgets/reveal.dart';

/// «Текст с фото»: снимаем/выбираем фото → офлайн-OCR → частые незнакомые слова
/// уходят в колоду одним тапом (или пакетно). Язык распознавания = изучаемый,
/// его можно поправить.
class OcrScreen extends StatefulWidget {
  const OcrScreen({super.key});

  @override
  State<OcrScreen> createState() => _OcrScreenState();
}

class _OcrScreenState extends State<OcrScreen> {
  static const Color _accent = Color(0xFF5B8DEF);

  final DeckRepository _repo = DeckRepository.instance;
  String _lang = 'en';
  File? _image;
  String _text = '';
  List<String> _words = const [];
  bool _busy = false;
  Deck? _targetDeck;

  @override
  void initState() {
    super.initState();
    _repo.selectedLanguageCode().then((v) {
      if (mounted) setState(() => _lang = v ?? 'en');
    });
  }

  Future<void> _pick(ImageSource source) async {
    try {
      final x = await ImagePicker()
          .pickImage(source: source, imageQuality: 90, maxWidth: 2200);
      if (x == null) return;
      setState(() {
        _image = File(x.path);
        _busy = true;
        _text = '';
        _words = const [];
      });
      final text = await OcrService.instance.recognize(x.path, _lang);
      if (!mounted) return;
      setState(() {
        _text = text;
        _words = _extractWords(text, _lang);
        _busy = false;
      });
    } catch (_) {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Уникальные буквенные слова, которых ещё нет в словаре языка, по убыванию
  /// частоты в тексте.
  List<String> _extractWords(String text, String lang) {
    final known = _repo.knownFrontsForLanguage(lang);
    final freq = <String, int>{};
    for (final m in RegExp(r"[\p{L}]+(?:['’-][\p{L}]+)*", unicode: true)
        .allMatches(text)) {
      final w = m.group(0)!.toLowerCase();
      if (w.length < 2 || known.contains(w)) continue;
      freq[w] = (freq[w] ?? 0) + 1;
    }
    final list = freq.keys.toList()
      ..sort((a, b) => freq[b]!.compareTo(freq[a]!));
    return list.take(60).toList();
  }

  Future<void> _changeLanguage() async {
    // Меняем язык распознавания и перераспознаём тем же фото.
    final picked = await showLanguagePicker(context, _lang, unknownCode: _lang);
    if (picked == null || picked == _lang) return;
    setState(() => _lang = picked);
    _targetDeck = null;
    if (_image != null) {
      setState(() => _busy = true);
      final text = await OcrService.instance.recognize(_image!.path, _lang);
      if (!mounted) return;
      setState(() {
        _text = text;
        _words = _extractWords(text, _lang);
        _busy = false;
      });
    }
  }

  Future<void> _learn(String word) async {
    await showWordLookup(
      context,
      word: word,
      sentence: _sentenceFor(word),
      sourceLang: _lang,
      targetLang: LocaleController.instance.code,
      alreadyKnown: false,
      onAdd: (back, example, pos) => _add(word, back, example, pos),
    );
    if (mounted) setState(() => _words = _extractWords(_text, _lang));
  }

  Future<LookupAddResult> _add(
      String front, String back, String example, String? dictPos) async {
    _targetDeck ??= await VideoDeckTarget.resolveInSourcePack(
        context, _lang, tr('ocr_source'));
    final deck = _targetDeck;
    if (deck == null) return LookupAddResult.cancelled;
    final ok = await VideoDeckTarget.addWord(
      deck,
      front: front,
      back: back,
      example: example,
      sentence: example,
      pos: PosDetect.detect(front, dictPos: dictPos, languageCode: _lang),
    );
    return ok ? LookupAddResult.added : LookupAddResult.duplicate;
  }

  String _sentenceFor(String word) {
    for (final line in _text.split('\n')) {
      if (line.toLowerCase().contains(word.toLowerCase())) return line.trim();
    }
    return '';
  }

  Future<void> _addAll() async {
    final words = List<String>.from(_words);
    if (words.isEmpty) return;
    HapticFeedback.selectionClick();
    _targetDeck ??= await VideoDeckTarget.resolveInSourcePack(
        context, _lang, tr('ocr_source'));
    final deck = _targetDeck;
    if (deck == null || !mounted) return;

    final progress = ValueNotifier<int>(0);
    final cancelled = ValueNotifier<bool>(false);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _BatchDialog(
          total: words.length, progress: progress, onCancel: () => cancelled.value = true),
    );
    final tgt = LocaleController.instance.code;
    var added = 0;
    for (var i = 0; i < words.length; i++) {
      if (cancelled.value) break;
      final w = words[i];
      final res = await TranslationManager.instance
          .translate(w, _lang, tgt, context: _sentenceFor(w));
      if (res != null && res.primary.trim().isNotEmpty) {
        final ok = await VideoDeckTarget.addWord(deck,
            front: w,
            back: res.primary,
            example: _sentenceFor(w),
            sentence: _sentenceFor(w),
            pos: PosDetect.detect(w, dictPos: res.partOfSpeech, languageCode: _lang));
        if (ok) added++;
      }
      progress.value = i + 1;
    }
    progress.dispose();
    cancelled.dispose();
    if (mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      setState(() => _words = _extractWords(_text, _lang));
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(trf('added_n_cards', {'n': added}))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(tr('ocr_title'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          _sourceButtons(scheme),
          if (_image != null) ...[
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Image.file(_image!,
                  height: 200, width: double.infinity, fit: BoxFit.cover),
            ),
          ],
          if (_busy) ...[
            const SizedBox(height: 24),
            Center(
              child: Column(
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 12),
                  Text(tr('ocr_recognizing'),
                      style: TextStyle(color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
          ] else if (_image != null && _text.trim().isEmpty) ...[
            const SizedBox(height: 24),
            Center(
              child: Text(tr('ocr_no_text'),
                  style: TextStyle(color: scheme.onSurfaceVariant)),
            ),
          ] else if (_text.trim().isNotEmpty) ...[
            const SizedBox(height: 16),
            Reveal(
              child: LanguageCheckCard(
                  languageCode: _lang, onChange: _changeLanguage),
            ),
            const SizedBox(height: 16),
            Reveal(delay: const Duration(milliseconds: 60), child: _wordsCard(scheme)),
            const SizedBox(height: 16),
            Reveal(
              delay: const Duration(milliseconds: 100),
              child: _recognizedText(scheme),
            ),
          ],
        ],
      ),
    );
  }

  Widget _sourceButtons(ColorScheme scheme) {
    return Row(
      children: [
        Expanded(
          child: PressableScale(
            child: FilledButton.icon(
              onPressed: _busy ? null : () => _pick(ImageSource.camera),
              style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16)),
              icon: const Icon(Icons.photo_camera_rounded),
              label: Text(tr('ocr_take_photo')),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: PressableScale(
            child: FilledButton.tonalIcon(
              onPressed: _busy ? null : () => _pick(ImageSource.gallery),
              style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16)),
              icon: const Icon(Icons.photo_library_rounded),
              label: Text(tr('ocr_from_gallery')),
            ),
          ),
        ),
      ],
    );
  }

  Widget _wordsCard(ColorScheme scheme) {
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
          Text(tr('ocr_words_title'),
              style: TextStyle(
                fontFamily: AppTheme.displayFont,
                fontWeight: FontWeight.w700,
                fontSize: 16,
                color: scheme.onSurface,
              )),
          const SizedBox(height: 2),
          Text(tr('ocr_words_sub'),
              style: TextStyle(
                fontFamily: AppTheme.bodyFont,
                fontSize: 12,
                color: scheme.onSurfaceVariant,
              )),
          const SizedBox(height: 14),
          if (_words.isEmpty)
            Text(tr('no_matches'),
                style: TextStyle(color: scheme.onSurfaceVariant))
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final w in _words)
                  ActionChip(
                    label: Text(w),
                    labelStyle: TextStyle(
                        fontFamily: AppTheme.bodyFont,
                        fontSize: 13,
                        color: scheme.onSurface),
                    avatar: Icon(Icons.add_rounded, size: 18, color: scheme.primary),
                    backgroundColor: _accent.withValues(alpha: 0.10),
                    side: BorderSide(color: _accent.withValues(alpha: 0.3)),
                    onPressed: () => _learn(w),
                  ),
              ],
            ),
          if (_words.isNotEmpty) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                onPressed: _addAll,
                icon: const Icon(Icons.done_all_rounded, size: 20),
                label: Text(trf('add_all_n', {'n': _words.length})),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _recognizedText(ColorScheme scheme) {
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
          Text(tr('recognized_text'),
              style: TextStyle(
                fontFamily: AppTheme.displayFont,
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: scheme.onSurface,
              )),
          const SizedBox(height: 10),
          SelectableText(
            _text.trim(),
            style: TextStyle(
              fontFamily: AppTheme.bodyFont,
              fontSize: 14,
              height: 1.4,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// Диалог прогресса пакетного добавления.
class _BatchDialog extends StatelessWidget {
  final int total;
  final ValueNotifier<int> progress;
  final VoidCallback onCancel;
  const _BatchDialog(
      {required this.total, required this.progress, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      content: ValueListenableBuilder<int>(
        valueListenable: progress,
        builder: (_, done, _) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                  value: total == 0 ? 0 : done / total, minHeight: 8),
            ),
            const SizedBox(height: 16),
            Text(trf('batch_adding', {'i': done, 'n': total})),
          ],
        ),
      ),
      actions: [TextButton(onPressed: onCancel, child: Text(tr('cancel')))],
    );
  }
}
