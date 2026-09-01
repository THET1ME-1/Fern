import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../study/tappable_text.dart';
import 'subtitle.dart';

/// Часы воспроизведения: позиция ролика на КАЖДЫЙ кадр, а не на тик плеера.
///
/// YouTube присылает позицию раз в 100 мс (`videoStateUpdateInterval`) и с
/// дрожью: `getCurrentTime()` за окном вебвью идёт неровно. Подсветка слова на
/// таких данных дёргается, поэтому между тиками время считается локально, а
/// пришедшая позиция подтягивает якорь.
///
/// Класс чистый: никакого плеера и никакого `DateTime.now()` внутри — «сейчас»
/// приходит снаружи ([wall], у экрана это `Stopwatch`). Так его можно проверить
/// обычным тестом, а экран видео в тестах не поднять (там вебвью).
class PlaybackClock {
  /// Расхождение, с которого считаем, что человек перемотал, а не что часы
  /// разошлись. Тик приходит раз в 100 мс, полсекунды хватает с запасом.
  static const Duration resyncThreshold = Duration(milliseconds: 400);

  /// Насколько подтягиваемся к позиции плеера за один тик. Вперёд охотнее, чем
  /// назад: откат плашки на слово назад заметнее, чем задержка.
  static const double _pullForward = 0.25;
  static const double _pullBack = 0.06;

  Duration _anchorPos = Duration.zero;
  Duration _anchorWall = Duration.zero;
  double _rate = 1;
  bool _playing = false;

  bool get playing => _playing;
  double get rate => _rate;

  /// Позиция ролика в момент [wall].
  Duration positionAt(Duration wall) {
    if (!_playing) return _anchorPos;
    final since = wall - _anchorWall;
    return _anchorPos + since * _rate;
  }

  /// Пауза и продолжение. На паузе часы стоят: тиков от плеера в это время нет
  /// вовсе (таймер в player.html живёт только в состоянии «играет»).
  void setPlaying(bool value, Duration wall) {
    _anchorPos = positionAt(wall);
    _anchorWall = wall;
    _playing = value;
  }

  /// Скорость воспроизведения (человек мог поставить 0,5× для разбора).
  void setRate(double value, Duration wall) {
    if (value <= 0 || value == _rate) return;
    _anchorPos = positionAt(wall);
    _anchorWall = wall;
    _rate = value;
  }

  /// Позиция от плеера. Возвращает true, если это была перемотка.
  bool sync(Duration reported, Duration wall) {
    final predicted = positionAt(wall);
    final drift = reported - predicted;
    final jumped = drift.abs() >= resyncThreshold;
    if (jumped) {
      _anchorPos = reported;
    } else {
      final pull = drift.isNegative ? _pullBack : _pullForward;
      _anchorPos = predicted + drift * pull;
    }
    _anchorWall = wall;
    return jumped;
  }

  /// Жёсткая установка (перемотка из пузыря слова, старт с середины).
  void seek(Duration pos, Duration wall) {
    _anchorPos = pos;
    _anchorWall = wall;
  }
}

/// Реплика субтитра с «бегунком»: плашка переезжает от слова к слову под
/// текстом, звучащее слово перекрашивается.
///
/// Плашка рисуется [CustomPaint]'ом ПОД текстом, а границы слова берутся у того
/// же `RenderParagraph`, по которому экран ищет слово под пальцем. Мерить текст
/// вторым `TextPainter`ом нельзя: добавленные в этой сессии слова идут жирным,
/// и плашка уезжала бы от них на пару пикселей.
class KaraokeLine extends StatefulWidget {
  final SubLine line;
  final TextStyle style;
  final bool active;

  /// Границы звучащего слова и предыдущего (по символам в `line.text`) —
  /// откуда и куда едет плашка. null — плашки нет.
  final (int, int)? spoken;
  final (int, int)? previous;

  /// Переезд плашки: 0 — она у [previous], 1 — у [spoken].
  final Animation<double> travel;

  final Color pillColor;
  final Color spokenColor;

  final Set<String> known;
  final Set<String> sessionAdded;
  final int highlightVersion;
  final Color knownColor;
  final Color addedColor;
  final ValueChanged<String> onWord;
  final ValueChanged<String> onPhrase;

  const KaraokeLine({
    super.key,
    required this.line,
    required this.style,
    required this.active,
    required this.spoken,
    required this.previous,
    required this.travel,
    required this.pillColor,
    required this.spokenColor,
    required this.known,
    required this.sessionAdded,
    required this.highlightVersion,
    required this.knownColor,
    required this.addedColor,
    required this.onWord,
    required this.onPhrase,
  });

  @override
  State<KaraokeLine> createState() => _KaraokeLineState();
}

class _KaraokeLineState extends State<KaraokeLine> {
  /// Ключ живёт в состоянии строки, а не ездит между строками: общий ключ на
  /// «активную» переносился бы из одной реплики в другую каждым переключением.
  final GlobalKey _paragraph = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final text = TappableText(
      text: widget.line.text,
      style: widget.style,
      paragraphKey: _paragraph,
      known: widget.known,
      sessionAdded: widget.sessionAdded,
      highlightVersion: widget.highlightVersion,
      knownColor: widget.knownColor,
      addedColor: widget.addedColor,
      spoken: widget.active ? widget.spoken : null,
      spokenColor: widget.spokenColor,
      onWord: widget.onWord,
      onPhrase: widget.onPhrase,
    );
    if (!widget.active || widget.spoken == null) return text;
    return CustomPaint(
      painter: _PillPainter(
        paragraph: _paragraph,
        from: widget.previous,
        to: widget.spoken!,
        travel: widget.travel,
        color: widget.pillColor,
      ),
      child: text,
    );
  }
}

/// Границы слова [span] в уже отрисованной реплике. null — слово в реплику не
/// попало (разметка разошлась с текстом).
Rect? wordBox(RenderParagraph render, (int, int) span) {
  final boxes = render.getBoxesForSelection(
    TextSelection(baseOffset: span.$1, extentOffset: span.$2),
  );
  if (boxes.isEmpty) return null;
  var rect = boxes.first.toRect();
  for (final b in boxes.skip(1)) {
    rect = rect.expandToInclude(b.toRect());
  }
  return rect;
}

/// Где сейчас плашка: переезд от [from] к [to] на доле [travel].
///
/// Возвращает и прозрачность: у первого слова реплики плашка не прилетает
/// издалека, а проявляется на месте.
({Rect rect, double opacity})? pillRect(
  RenderParagraph render, {
  (int, int)? from,
  required (int, int) to,
  required double travel,
}) {
  final target = wordBox(render, to);
  if (target == null) return null;
  final start = from == null ? null : wordBox(render, from);
  final k = Curves.easeOutCubic.transform(travel.clamp(0.0, 1.0));

  if (start == null) return (rect: target, opacity: k);
  // Слово с другой строки реплики: по диагонали через весь текст не летим.
  if ((start.top - target.top).abs() > 2) return (rect: target, opacity: 1);
  return (rect: Rect.lerp(start, target, k)!, opacity: 1);
}

class _PillPainter extends CustomPainter {
  final GlobalKey paragraph;
  final (int, int)? from;
  final (int, int) to;
  final Animation<double> travel;
  final Color color;

  _PillPainter({
    required this.paragraph,
    required this.from,
    required this.to,
    required this.travel,
    required this.color,
  }) : super(repaint: travel);

  @override
  void paint(Canvas canvas, Size size) {
    final render = paragraph.currentContext?.findRenderObject();
    if (render is! RenderParagraph) return;
    final at = pillRect(render, from: from, to: to, travel: travel.value);
    if (at == null) return;
    final r = at.rect;
    final pill = RRect.fromRectAndRadius(
      Rect.fromLTRB(r.left - 4, r.top + 1.5, r.right + 4, r.bottom - 1.5),
      const Radius.circular(8),
    );
    canvas.drawRRect(pill, Paint()..color = color.withValues(alpha: at.opacity));
  }

  @override
  bool shouldRepaint(_PillPainter old) =>
      old.from != from || old.to != to || old.color != color;
}
