import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

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

  /// Тап по слову (уже очищенному от пунктуации, как отображается).
  final ValueChanged<String> onWord;

  /// Тап мимо слова: локальная точка + ширина блока (для лево/право листания).
  final void Function(Offset localPosition, double width)? onMiss;

  /// Приведение слова к ключу сверки (лемматизация). null — сверка как есть.
  /// Множества [known]/[sessionAdded] должны содержать уже нормализованные ключи.
  final String Function(String lower)? normalize;

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
    this.onMiss,
    this.normalize,
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
        old.addedColor != widget.addedColor) {
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

    final spans = <InlineSpan>[];
    var cursor = 0;
    for (final r in _ranges) {
      if (r.start > cursor) {
        // Пробелы/пунктуация между словами — обычным стилем.
        spans.add(TextSpan(text: widget.text.substring(cursor, r.start)));
      }
      final display = widget.text.substring(r.start, r.end);
      final key = widget.normalize?.call(r.lower) ?? r.lower;
      TextStyle? s;
      if (widget.sessionAdded.contains(key)) {
        s = addedStyle;
      } else if (widget.known.contains(key)) {
        s = knownStyle;
      }
      spans.add(TextSpan(text: display, style: s));
      cursor = r.end;
    }
    if (cursor < widget.text.length) {
      spans.add(TextSpan(text: widget.text.substring(cursor)));
    }
    _spans = spans;
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
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: _handleTap,
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
