import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'reader_settings.dart' show HighlightMode;

/// Текст с тапом по отдельному слову — БЕЗ распознавателя на каждое слово.
///
/// Раньше читалка вешала свой [TapGestureRecognizer] на каждое слово абзаца/
/// страницы (сотни распознавателей → тяжёлый билд, тяжёлый hit-test, лаги при
/// прокрутке и листании). Здесь один [GestureDetector] на весь блок: по тапу мы
/// спрашиваем у отрисованного [RenderParagraph], в какой символ попали, и по
/// смещению находим слово. Спаны с подсветкой строятся без распознавателей.
///
/// Тап мимо слова (пустое место, край строки) отдаётся в [onMiss] — постраничный
/// режим использует это, чтобы листать (лево/право), а режим прокрутки его не
/// задаёт (тап по пустому месту ничего не делает).
class TappableText extends StatefulWidget {
  final String text;
  final TextStyle style;

  /// Слова из базы (известные) и добавленные в этой сессии — раскрашены
  /// [knownColor] и [addedColor]. Множества — в нижнем регистре.
  final Set<String> known;
  final Set<String> sessionAdded;

  /// Меняется, когда пользователь добавил слово — чтобы пересобрать подсветку.
  final int highlightVersion;

  final Color knownColor;
  final Color addedColor;

  /// Что подсвечивать: слова из словаря / незнакомые / ничего.
  final HighlightMode highlightMode;

  /// Тап по слову (уже очищенному от пунктуации, как отображается).
  final ValueChanged<String> onWord;

  /// Тап мимо слова: локальная точка + ширина блока (для лево/право листания).
  final void Function(Offset localPosition, double width)? onMiss;

  /// Приведение слова к ключу сверки (лемматизация). null — сверка как есть.
  /// Множества [known]/[sessionAdded] должны содержать уже нормализованные ключи.
  final String Function(String lower)? normalize;

  /// Выделение фразы (long-press + протяжка) → перевод фразы. null — выключено.
  final ValueChanged<String>? onPhrase;

  const TappableText({
    super.key,
    required this.text,
    required this.style,
    required this.known,
    required this.sessionAdded,
    required this.highlightVersion,
    required this.knownColor,
    required this.addedColor,
    required this.onWord,
    this.highlightMode = HighlightMode.known,
    this.onMiss,
    this.normalize,
    this.onPhrase,
  });

  @override
  State<TappableText> createState() => _TappableTextState();
}

class _TappableTextState extends State<TappableText> {
  static final RegExp _edge = RegExp(
    r'^[^\p{L}\p{N}]+|[^\p{L}\p{N}]+$',
    unicode: true,
  );
  static final RegExp _token = RegExp(r'\S+|\s+');

  final GlobalKey _textKey = GlobalKey();

  /// Диапазоны слов [начало, конец) по индексам в [widget.text] + очищенное
  /// (для показа/добавления) и его нижний регистр (для сверки).
  late List<_WordRange> _ranges;
  late List<InlineSpan> _spans;

  // Активное выделение фразы (символьные смещения anchor/extent), null — нет.
  int? _selAnchor;
  int? _selExtent;
  int get _selMin =>
      _selAnchor == null ? -1 : (_selAnchor! < _selExtent! ? _selAnchor! : _selExtent!);
  int get _selMax =>
      _selAnchor == null ? -1 : (_selAnchor! > _selExtent! ? _selAnchor! : _selExtent!);

  @override
  void initState() {
    super.initState();
    _tokenize();
    _buildSpans();
  }

  @override
  void didUpdateWidget(TappableText old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) {
      _tokenize();
      _buildSpans();
    } else if (old.highlightVersion != widget.highlightVersion ||
        old.style != widget.style ||
        old.knownColor != widget.knownColor ||
        old.addedColor != widget.addedColor ||
        old.highlightMode != widget.highlightMode) {
      _buildSpans();
    }
  }

  /// Разбивает текст на слова один раз (диапазоны символов не зависят от
  /// подсветки — их пересчитывать не нужно, пока текст тот же).
  void _tokenize() {
    _ranges = [];
    var offset = 0;
    for (final m in _token.allMatches(widget.text)) {
      final raw = m.group(0)!;
      final len = raw.length;
      if (raw.trim().isNotEmpty) {
        final clean = raw.replaceAll(_edge, '');
        if (clean.isNotEmpty) {
          _ranges.add(_WordRange(offset, offset + len, clean, clean.toLowerCase()));
        }
      }
      offset += len;
    }
  }

  void _buildSpans() {
    final knownStyle = widget.style.copyWith(
      color: widget.knownColor,
      decoration: TextDecoration.underline,
      decorationColor: widget.knownColor.withValues(alpha: 0.5),
      decorationThickness: 2,
    );
    final addedStyle = widget.style.copyWith(
      color: widget.addedColor,
      fontWeight: FontWeight.w700,
      decoration: TextDecoration.underline,
      decorationColor: widget.addedColor.withValues(alpha: 0.6),
      decorationThickness: 2,
    );
    // Незнакомые слова — пунктирное подчёркивание (отличается от known).
    final unknownStyle = widget.style.copyWith(
      decoration: TextDecoration.underline,
      decorationColor: widget.knownColor.withValues(alpha: 0.55),
      decorationStyle: TextDecorationStyle.dotted,
      decorationThickness: 2,
    );

    TextStyle? styleForWord(String key) {
      if (widget.sessionAdded.contains(key)) return addedStyle;
      switch (widget.highlightMode) {
        case HighlightMode.known:
          return widget.known.contains(key) ? knownStyle : null;
        case HighlightMode.unknown:
          return widget.known.contains(key) ? null : unknownStyle;
        case HighlightMode.off:
          return null;
      }
    }

    // Фон выделения фразы для символьного отрезка [a,b), если он в выделении.
    final selColor = widget.knownColor.withValues(alpha: 0.28);
    TextStyle? withSel(int a, int b, TextStyle? base) {
      if (_selAnchor == null || _selMax <= _selMin) return base;
      if (a < _selMax && b > _selMin) {
        return (base ?? widget.style).copyWith(backgroundColor: selColor);
      }
      return base;
    }

    final spans = <InlineSpan>[];
    var cursor = 0;
    for (final r in _ranges) {
      if (r.start > cursor) {
        // Пробелы/пунктуация между словами — обычным стилем.
        spans.add(TextSpan(
          text: widget.text.substring(cursor, r.start),
          style: withSel(cursor, r.start, null),
        ));
      }
      final display = widget.text.substring(r.start, r.end);
      final key = widget.normalize?.call(r.lower) ?? r.lower;
      spans.add(TextSpan(
        text: display,
        style: withSel(r.start, r.end, styleForWord(key)),
      ));
      cursor = r.end;
    }
    if (cursor < widget.text.length) {
      spans.add(TextSpan(
        text: widget.text.substring(cursor),
        style: withSel(cursor, widget.text.length, null),
      ));
    }
    _spans = spans;
  }

  int? _offsetAt(Offset local) {
    final render = _textKey.currentContext?.findRenderObject();
    if (render is! RenderParagraph) return null;
    return render.getPositionForOffset(local).offset;
  }

  void _onLongPressStart(LongPressStartDetails d) {
    final o = _offsetAt(d.localPosition);
    if (o == null) return;
    HapticFeedback.selectionClick();
    setState(() {
      _selAnchor = o;
      _selExtent = o;
      _buildSpans();
    });
  }

  void _onLongPressMove(LongPressMoveUpdateDetails d) {
    if (_selAnchor == null) return;
    final o = _offsetAt(d.localPosition);
    if (o == null || o == _selExtent) return;
    setState(() {
      _selExtent = o;
      _buildSpans();
    });
  }

  void _onLongPressEnd(LongPressEndDetails d) {
    final anchor = _selAnchor;
    if (anchor == null) return;
    final ext = _selExtent ?? anchor;
    final lo0 = anchor < ext ? anchor : ext;
    final hi0 = anchor > ext ? anchor : ext;
    final expanded = _expandToWords(lo0, hi0);
    final phrase = widget.text.substring(expanded.$1, expanded.$2).trim();
    setState(() {
      _selAnchor = null;
      _selExtent = null;
      _buildSpans();
    });
    if (phrase.isNotEmpty && _letter.hasMatch(phrase)) {
      widget.onPhrase?.call(phrase);
    }
  }

  static final RegExp _letter = RegExp(r'\p{L}', unicode: true);

  /// Расширяет отрезок [a,b) до границ слов (чтобы не резать по половине слова).
  (int, int) _expandToWords(int a, int b) {
    var lo = a, hi = b;
    for (final r in _ranges) {
      if (a >= r.start && a < r.end) lo = r.start;
      if (b > r.start && b <= r.end) hi = r.end;
    }
    return (lo.clamp(0, widget.text.length), hi.clamp(0, widget.text.length));
  }

  void _handleTap(TapUpDetails d) {
    final render = _textKey.currentContext?.findRenderObject();
    if (render is! RenderParagraph) return;
    final offset = render.getPositionForOffset(d.localPosition).offset;
    final word = _wordAt(offset);
    if (word != null) {
      widget.onWord(word);
    } else {
      widget.onMiss?.call(d.localPosition, render.size.width);
    }
  }

  /// Слово, покрывающее символ [o] (или соседний слева — чтобы правый край
  /// слова тоже попадал). null — тап по пустому месту.
  String? _wordAt(int o) {
    for (final r in _ranges) {
      if (o >= r.start && o < r.end) return r.clean;
    }
    final p = o - 1;
    for (final r in _ranges) {
      if (p >= r.start && p < r.end) return r.clean;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    // Именно RichText (а не Text.rich): его render-объект — RenderParagraph, к
    // которому обращаемся по ключу для поиска слова под пальцем. Text.rich мог
    // бы обернуться в Semantics/MouseRegion, и ключ указал бы не туда.
    final phraseEnabled = widget.onPhrase != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: _handleTap,
      onLongPressStart: phraseEnabled ? _onLongPressStart : null,
      onLongPressMoveUpdate: phraseEnabled ? _onLongPressMove : null,
      onLongPressEnd: phraseEnabled ? _onLongPressEnd : null,
      child: RichText(
        key: _textKey,
        text: TextSpan(style: widget.style, children: _spans),
      ),
    );
  }
}

class _WordRange {
  final int start;
  final int end;
  final String clean;
  final String lower;
  const _WordRange(this.start, this.end, this.clean, this.lower);
}
