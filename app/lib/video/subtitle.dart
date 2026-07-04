import 'package:flutter/foundation.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

/// Одно слово субтитра с абсолютным таймкодом начала (для живого голоса слова).
/// Есть только у авто-субтитров (ASR); у ручных — список пуст.
class SubWord {
  final String text;
  final Duration start;
  const SubWord(this.text, this.start);

  Map<String, dynamic> toJson() => {'t': text, 's': start.inMilliseconds};

  factory SubWord.fromJson(Map<String, dynamic> j) => SubWord(
        j['t'] as String? ?? '',
        Duration(milliseconds: (j['s'] as num?)?.toInt() ?? 0),
      );
}

/// Реплика субтитра: `start`–`end` (для живого голоса целого предложения) и
/// текст. `words` заполнен только при пословном тайминге.
class SubLine {
  final Duration start;
  final Duration end;
  final String text;
  final List<SubWord> words;

  const SubLine({
    required this.start,
    required this.end,
    required this.text,
    this.words = const [],
  });

  bool get hasWordTiming => words.isNotEmpty;

  /// Границы слова [w] внутри этой реплики (start слова → start следующего /
  /// конец реплики). Используется для проигрывания живого голоса слова.
  (Duration, Duration) wordSpan(SubWord w) {
    final i = words.indexOf(w);
    final end = (i >= 0 && i < words.length - 1) ? words[i + 1].start : this.end;
    return (w.start, end);
  }

  Map<String, dynamic> toJson() => {
        'a': start.inMilliseconds,
        'b': end.inMilliseconds,
        'x': text,
        if (words.isNotEmpty) 'w': [for (final w in words) w.toJson()],
      };

  factory SubLine.fromJson(Map<String, dynamic> j) => SubLine(
        start: Duration(milliseconds: (j['a'] as num?)?.toInt() ?? 0),
        end: Duration(milliseconds: (j['b'] as num?)?.toInt() ?? 0),
        text: j['x'] as String? ?? '',
        words: [
          for (final w in (j['w'] as List? ?? const []))
            SubWord.fromJson((w as Map).cast<String, dynamic>()),
        ],
      );
}

/// Разобранный транскрипт видео.
class VideoTranscript {
  final String videoId;
  final String url;
  final String title;

  /// Код языка субтитров (что изучаем).
  final String langCode;

  /// Есть ли пословный тайминг хотя бы у части реплик (живой голос слова).
  final bool wordTimed;

  final List<SubLine> lines;

  const VideoTranscript({
    required this.videoId,
    required this.url,
    required this.title,
    required this.langCode,
    required this.wordTimed,
    required this.lines,
  });

  bool get hasCaptions => lines.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'id': videoId,
        'url': url,
        'title': title,
        'lang': langCode,
        'wt': wordTimed,
        'lines': [for (final l in lines) l.toJson()],
      };

  factory VideoTranscript.fromJson(Map<String, dynamic> j) => VideoTranscript(
        videoId: j['id'] as String? ?? '',
        url: j['url'] as String? ?? '',
        title: j['title'] as String? ?? '',
        langCode: j['lang'] as String? ?? 'en',
        wordTimed: j['wt'] as bool? ?? false,
        lines: [
          for (final l in (j['lines'] as List? ?? const []))
            SubLine.fromJson((l as Map).cast<String, dynamic>()),
        ],
      );
}

/// Причина неудачи загрузки — для понятного сообщения пользователю.
enum VideoError { badUrl, noCaptions, network }

class VideoResult {
  final VideoTranscript? transcript;
  final VideoError? error;
  const VideoResult.ok(this.transcript) : error = null;
  const VideoResult.fail(this.error) : transcript = null;
  bool get isOk => transcript != null;
}

/// Загрузка субтитров YouTube с таймкодами (без API-ключа). Предпочитает
/// авто-субтитры формата srv3 нужного языка — у них пословный тайминг.
class VideoService {
  const VideoService._();

  static String? parseId(String url) => VideoId.parseVideoId(url);

  static Future<VideoResult> fetch(String url, {String? preferLang}) async {
    final id = VideoId.parseVideoId(url.trim());
    if (id == null) return const VideoResult.fail(VideoError.badUrl);

    final yt = YoutubeExplode();
    try {
      final video = await yt.videos.get(id);
      final manifest = await yt.videos.closedCaptions.getManifest(id);
      if (manifest.tracks.isEmpty) {
        return const VideoResult.fail(VideoError.noCaptions);
      }
      final track = _pickTrack(manifest.tracks, preferLang);
      final cc = await yt.videos.closedCaptions.get(track);

      final lines = <SubLine>[];
      for (final c in cc.captions) {
        final text = c.text.trim();
        if (text.isEmpty) continue;
        final words = <SubWord>[
          for (final p in c.parts)
            if (p.text.trim().isNotEmpty)
              SubWord(p.text.trim(), c.offset + p.offset),
        ];
        lines.add(
          SubLine(start: c.offset, end: c.end, text: text, words: words),
        );
      }
      if (lines.isEmpty) return const VideoResult.fail(VideoError.noCaptions);

      return VideoResult.ok(
        VideoTranscript(
          videoId: id,
          url: 'https://youtu.be/$id',
          title: video.title,
          langCode: track.language.code,
          wordTimed: lines.any((l) => l.hasWordTiming),
          lines: lines,
        ),
      );
    } catch (e) {
      debugPrint('VideoService.fetch failed: $e');
      return const VideoResult.fail(VideoError.network);
    } finally {
      yt.close();
    }
  }

  /// Приоритет: язык+srv3 → язык → srv3 → первый доступный.
  static ClosedCaptionTrackInfo _pickTrack(
    List<ClosedCaptionTrackInfo> tracks,
    String? preferLang,
  ) {
    final lang = preferLang?.toLowerCase();
    ClosedCaptionTrackInfo? langSrv3, byLang, srv3;
    for (final t in tracks) {
      final langMatch =
          lang != null && t.language.code.toLowerCase().startsWith(lang);
      final isSrv3 = t.format.formatCode == 'srv3';
      if (langMatch && isSrv3) langSrv3 ??= t;
      if (langMatch) byLang ??= t;
      if (isSrv3) srv3 ??= t;
    }
    return langSrv3 ?? byLang ?? srv3 ?? tracks.first;
  }
}
