import '../models/fsrs.dart';
import '../models/review_event.dart';
import '../models/word_card.dart';

/// Слово под угрозой забывания: карта + её текущая извлекаемость (0..1).
class RiskWord {
  final WordCard card;
  final double retrievability;
  const RiskWord(this.card, this.retrievability);

  int get memoryPercent => (retrievability * 100).round();
}

/// Аналитика поверх уже собираемых данных (FSRS-состояние карт + журнал
/// событий): что вот-вот забудется и когда пользователь обычно занимается.
class StudyInsights {
  StudyInsights._();

  /// Слова под угрозой забывания: выученные карты (есть прошлый повтор и
  /// накоплена стабильность), у которых текущая извлекаемость упала ниже
  /// [threshold]. Отсортированы по возрастанию R — самые слабые первыми.
  static List<RiskWord> atRisk(
    List<WordCard> cards,
    DateTime now, {
    double threshold = 0.9,
    double minStability = 1.0,
  }) {
    final out = <RiskWord>[];
    for (final c in cards) {
      final last = c.review.lastReview;
      if (c.review.isNew || last == null) continue;
      if (c.review.stability < minStability) continue;
      final elapsed = now.difference(last).inSeconds / 86400.0;
      if (elapsed <= 0) continue;
      final r = Fsrs.instance.retrievability(elapsed, c.review.stability);
      if (r < threshold) out.add(RiskWord(c, r));
    }
    out.sort((a, b) => a.retrievability.compareTo(b.retrievability));
    return out;
  }

  /// Час дня (0..23), в который пользователь чаще всего занимается, по журналу
  /// событий. `null`, если данных мало (< [minEvents]) или пик неубедителен.
  static int? bestStudyHour(List<ReviewEvent> events, {int minEvents = 30}) {
    if (events.length < minEvents) return null;
    final byHour = List<int>.filled(24, 0);
    for (final e in events) {
      byHour[DateTime.fromMillisecondsSinceEpoch(e.ts).hour]++;
    }
    var best = 0;
    for (var h = 1; h < 24; h++) {
      if (byHour[h] > byHour[best]) best = h;
    }
    return byHour[best] == 0 ? null : best;
  }
}
