import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../l10n/strings.dart';
import '../services/deck_repository.dart';
import '../theme/app_theme.dart';

/// Карточка «Твоя неделя»: сводка за 7 дней (повторы, активные дни, точность,
/// серия, щиты) + кнопка поделиться (рендерит карточку в PNG). Мотивация +
/// вирусность.
class WeeklyRecapCard extends StatefulWidget {
  final int reviews;
  final int activeDays;
  final int accuracy;
  final int streak;

  const WeeklyRecapCard({
    super.key,
    required this.reviews,
    required this.activeDays,
    required this.accuracy,
    required this.streak,
  });

  @override
  State<WeeklyRecapCard> createState() => _WeeklyRecapCardState();
}

class _WeeklyRecapCardState extends State<WeeklyRecapCard> {
  final GlobalKey _boundaryKey = GlobalKey();
  int _freezes = 0;
  bool _sharing = false;

  @override
  void initState() {
    super.initState();
    DeckRepository.instance.streakFreezes().then((v) {
      if (mounted) setState(() => _freezes = v);
    });
  }

  Future<void> _share() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    HapticFeedback.selectionClick();
    try {
      final boundary = _boundaryKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 3);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) return;
      final bytes = data.buffer.asUint8List();
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/fern_week.png');
      await file.writeAsBytes(bytes);
      await Share.shareXFiles([XFile(file.path)], text: 'Fern');
    } catch (_) {
      // тихо — поделиться не критично
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RepaintBoundary(
          key: _boundaryKey,
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  scheme.primaryContainer,
                  scheme.tertiaryContainer,
                ],
              ),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.eco_rounded,
                        size: 20, color: scheme.onPrimaryContainer),
                    const SizedBox(width: 8),
                    Text(
                      tr('your_week'),
                      style: TextStyle(
                        fontFamily: AppTheme.displayFont,
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                        color: scheme.onPrimaryContainer,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      'Fern',
                      style: TextStyle(
                        fontFamily: AppTheme.displayFont,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: scheme.onPrimaryContainer.withValues(alpha: 0.75),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    _tile('${widget.reviews}', tr('reviews_word'), scheme),
                    const SizedBox(width: 10),
                    _tile('${widget.activeDays}/7', tr('week_days'), scheme),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _tile('${widget.accuracy}%', tr('res_accuracy'), scheme),
                    const SizedBox(width: 10),
                    _tile('🔥 ${widget.streak}', tr('stat_streak'), scheme),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('❄️', style: TextStyle(fontSize: 15)),
                  const SizedBox(width: 6),
                  Text(
                    trf('freezes_n', {'n': _freezes}),
                    style: TextStyle(
                      fontFamily: AppTheme.bodyFont,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: scheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            FilledButton.tonalIcon(
              onPressed: _sharing ? null : _share,
              icon: const Icon(Icons.ios_share_rounded, size: 18),
              label: Text(tr('share')),
            ),
          ],
        ),
      ],
    );
  }

  Widget _tile(String value, String label, ColorScheme scheme) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        decoration: BoxDecoration(
          color: scheme.surface.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: TextStyle(
                fontFamily: AppTheme.displayFont,
                fontWeight: FontWeight.w800,
                fontSize: 24,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontFamily: AppTheme.bodyFont,
                fontSize: 12,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
