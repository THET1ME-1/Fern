import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/strings.dart';
import '../models/deck.dart';
import '../models/word_card.dart';
import '../services/deck_repository.dart';
import '../theme/app_theme.dart';

/// Плитка в игре «Подбор»: текст, id карты и сторона (термин/перевод).
class _Tile {
  final String text;
  final String cardId;
  final bool isFront;
  _Tile(this.text, this.cardId, this.isFront);
}

/// Игра «Подбор пар» на скорость: соедини слова и переводы.
class MatchScreen extends StatefulWidget {
  final Deck deck;
  final List<WordCard> cards;

  const MatchScreen({super.key, required this.deck, required this.cards});

  @override
  State<MatchScreen> createState() => _MatchScreenState();
}

class _MatchScreenState extends State<MatchScreen> {
  static const int _maxPairs = 5;

  late List<_Tile> _tiles;
  final Set<String> _matched = {};
  int? _selected; // индекс выбранной плитки
  int? _wrongA;
  int? _wrongB;
  int _pairs = 0;

  Timer? _timer;
  final Stopwatch _watch = Stopwatch();
  bool _finished = false;
  int? _bestMillis;
  bool _isNewRecord = false;

  @override
  void initState() {
    super.initState();
    _bestMillis = DeckRepository.instance.bestMatchMillis(widget.deck.id);
    _setup();
  }

  void _setup() {
    final cards = List<WordCard>.from(widget.cards)..shuffle();
    final chosen = cards.take(_maxPairs).toList();
    _pairs = chosen.length;
    _tiles = [];
    for (final c in chosen) {
      _tiles.add(_Tile(c.front, c.id, true));
      _tiles.add(_Tile(c.back, c.id, false));
    }
    _tiles.shuffle();
    _matched.clear();
    _selected = null;
    _finished = false;
    _watch
      ..reset()
      ..start();
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _watch.stop();
    super.dispose();
  }

  void _tap(int i) {
    if (_finished) return;
    final tile = _tiles[i];
    if (_matched.contains(tile.cardId)) return;
    if (_wrongA != null) return; // ждём сброса неверной пары
    if (_selected == null) {
      setState(() => _selected = i);
      HapticFeedback.selectionClick();
      return;
    }
    if (_selected == i) {
      setState(() => _selected = null);
      return;
    }
    final a = _tiles[_selected!];
    final b = tile;
    if (a.cardId == b.cardId && a.isFront != b.isFront) {
      // Верная пара.
      setState(() {
        _matched.add(a.cardId);
        _selected = null;
      });
      HapticFeedback.mediumImpact();
      if (_matched.length >= _pairs) _finish();
    } else {
      // Неверно — краткая подсветка и сброс.
      setState(() {
        _wrongA = _selected;
        _wrongB = i;
        _selected = null;
      });
      HapticFeedback.heavyImpact();
      Future.delayed(const Duration(milliseconds: 550), () {
        if (mounted) setState(() => _wrongA = _wrongB = null);
      });
    }
  }

  void _finish() {
    _watch.stop();
    _timer?.cancel();
    final ms = _watch.elapsedMilliseconds;
    final repo = DeckRepository.instance;
    // Игра «Подбор» — тоже занятие: засчитываем в журнал (все пары верные).
    repo.logSession(reviews: _pairs, correct: _pairs);
    // Рекорд времени по колоде.
    repo.recordMatchMillis(widget.deck.id, ms).then((isRecord) {
      if (!mounted) return;
      setState(() {
        _isNewRecord = isRecord;
        _bestMillis = repo.bestMatchMillis(widget.deck.id);
      });
    });
    setState(() => _finished = true);
  }

  String get _timeStr => trf('dur_sec',
      {'s': (_watch.elapsedMilliseconds / 1000).toStringAsFixed(1)});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (_pairs < 2) {
      return Scaffold(
        appBar: AppBar(title: Text(tr('mode_match'))),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
              tr('empty_deck_sub'),
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(tr('mode_match')),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text(
                _timeStr,
                style: TextStyle(
                  fontFamily: AppTheme.displayFont,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  color: scheme.primary,
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.5,
                ),
                itemCount: _tiles.length,
                itemBuilder: (_, i) => _tileWidget(i, scheme),
              ),
            ),
            if (_finished) _finishOverlay(scheme),
          ],
        ),
      ),
    );
  }

  Widget _tileWidget(int i, ColorScheme scheme) {
    final tile = _tiles[i];
    final matched = _matched.contains(tile.cardId);
    final selected = _selected == i;
    final wrong = _wrongA == i || _wrongB == i;

    Color bg = scheme.surfaceContainerHigh;
    Color fg = scheme.onSurface;
    if (wrong) {
      bg = scheme.errorContainer;
      fg = scheme.onErrorContainer;
    } else if (selected) {
      bg = scheme.primaryContainer;
      fg = scheme.onPrimaryContainer;
    }

    return AnimatedOpacity(
      opacity: matched ? 0 : 1,
      duration: const Duration(milliseconds: 300),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: matched ? null : () => _tap(i),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Center(
              child: Text(
                tile.text,
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: AppTheme.bodyFont,
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                  color: fg,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _finishOverlay(ColorScheme scheme) {
    return Positioned.fill(
      child: Container(
        color: scheme.scrim.withValues(alpha: 0.55),
        alignment: Alignment.center,
        child: Container(
          margin: const EdgeInsets.all(32),
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(28),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.bolt_rounded, size: 56, color: scheme.primary),
              const SizedBox(height: 12),
              Text(
                tr('session_done'),
                style: TextStyle(
                  fontFamily: AppTheme.displayFont,
                  fontWeight: FontWeight.w800,
                  fontSize: 22,
                  color: scheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _timeStr,
                style: TextStyle(
                  fontFamily: AppTheme.displayFont,
                  fontWeight: FontWeight.w700,
                  fontSize: 34,
                  color: scheme.primary,
                ),
              ),
              const SizedBox(height: 8),
              if (_isNewRecord)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.emoji_events_rounded,
                        size: 18,
                        color: scheme.onPrimaryContainer,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        tr('match_new_record'),
                        style: TextStyle(
                          fontFamily: AppTheme.bodyFont,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: scheme.onPrimaryContainer,
                        ),
                      ),
                    ],
                  ),
                )
              else if (_bestMillis != null)
                Text(
                  trf('match_record', {
                    't': (_bestMillis! / 1000).toStringAsFixed(1),
                  }),
                  style: TextStyle(
                    fontFamily: AppTheme.bodyFont,
                    fontSize: 13,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.tonal(
                      onPressed: () => setState(_setup),
                      child: Text(tr('study_more')),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(tr('back_to_deck')),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
