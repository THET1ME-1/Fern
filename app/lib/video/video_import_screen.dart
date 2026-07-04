import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/strings.dart';
import '../services/deck_repository.dart';
import '../services/source_library.dart';
import '../theme/app_theme.dart';
import '../widgets/pressable.dart';
import '../widgets/reveal.dart';
import 'subtitle.dart';
import 'video_study_screen.dart';

/// Экран импорта видео: вставь ссылку на YouTube → тянем субтитры с таймкодами →
/// открываем разбор. Пословный тайминг (авто-субтитры) даёт живой голос слова.
class VideoImportScreen extends StatefulWidget {
  const VideoImportScreen({super.key});

  @override
  State<VideoImportScreen> createState() => _VideoImportScreenState();
}

class _VideoImportScreenState extends State<VideoImportScreen> {
  final TextEditingController _url = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text != null && text.isNotEmpty) {
      setState(() => _url.text = text);
    }
  }

  Future<void> _parse() async {
    final url = _url.text.trim();
    if (url.isEmpty || _loading) return;
    FocusScope.of(context).unfocus();
    HapticFeedback.selectionClick();
    setState(() {
      _loading = true;
      _error = null;
    });
    final preferLang =
        await DeckRepository.instance.selectedLanguageCode() ?? 'en';
    final result = await VideoService.fetch(url, preferLang: preferLang);
    if (!mounted) return;
    setState(() => _loading = false);
    if (result.isOk) {
      // Сохраняем разбор в библиотеку — к видео можно вернуться позже.
      final sourceId = await SourceLibrary.instance.saveVideo(result.transcript!);
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => VideoStudyScreen(
            transcript: result.transcript!,
            sourceId: sourceId,
          ),
        ),
      );
    } else {
      setState(() => _error = switch (result.error) {
            VideoError.badUrl => tr('video_bad_url'),
            VideoError.noCaptions => tr('video_no_captions'),
            _ => tr('video_network_error'),
          });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(tr('video_import_title'))),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Reveal(
              child: Column(
                children: [
                  Container(
                    width: 84,
                    height: 84,
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.subtitles_rounded,
                        size: 42, color: scheme.onPrimaryContainer),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    tr('video_import_headline'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: AppTheme.displayFont,
                      fontWeight: FontWeight.w800,
                      fontSize: 22,
                      color: scheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    tr('video_import_sub'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: AppTheme.bodyFont,
                      fontSize: 14,
                      height: 1.4,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            Reveal(
              delay: const Duration(milliseconds: 80),
              child: TextField(
                controller: _url,
                keyboardType: TextInputType.url,
                autocorrect: false,
                onSubmitted: (_) => _parse(),
                decoration: InputDecoration(
                  labelText: tr('video_url_label'),
                  hintText: 'https://youtu.be/…',
                  prefixIcon: const Icon(Icons.link_rounded),
                  suffixIcon: IconButton(
                    tooltip: tr('paste'),
                    icon: const Icon(Icons.content_paste_rounded),
                    onPressed: _paste,
                  ),
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.errorContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline_rounded,
                        size: 18, color: scheme.onErrorContainer),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _error!,
                        style: TextStyle(
                          fontSize: 13,
                          color: scheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 20),
            Reveal(
              delay: const Duration(milliseconds: 140),
              child: PressableScale(
                child: FilledButton.icon(
                  onPressed: _loading ? null : _parse,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  icon: _loading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.auto_awesome_rounded),
                  label: Text(
                    _loading ? tr('video_parsing') : tr('video_parse'),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Reveal(
              delay: const Duration(milliseconds: 200),
              child: _hintCard(scheme),
            ),
          ],
        ),
      ),
    );
  }

  Widget _hintCard(ColorScheme scheme) {
    final tips = [
      (Icons.record_voice_over_rounded, tr('video_tip_voice')),
      (Icons.touch_app_rounded, tr('video_tip_tap')),
      (Icons.style_rounded, tr('video_tip_deck')),
    ];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          for (var i = 0; i < tips.length; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(tips[i].$1, size: 20, color: scheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    tips[i].$2,
                    style: TextStyle(
                      fontFamily: AppTheme.bodyFont,
                      fontSize: 13,
                      height: 1.35,
                      color: scheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
