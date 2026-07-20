import '../models/fsrs.dart';
import '../models/word_card.dart';
import 'lemmatizer.dart';

/// Разминка перед чтением: короткая сессия по словам ближайших страниц.
///
/// Fern знает и текст книги, и место, где чтение остановилось, поэтому может
/// повторить именно те слова, что попадутся через пять минут. Слово,
/// встреченное в живом тексте сразу после карточки, закрепляется контекстом —
/// обычному SRS такое недоступно, у него нет книги.
class ReadingWarmup {
  const ReadingWarmup._();

  /// Сколько слов в разминке. Она стоит между человеком и книгой, поэтому
  /// короткая: длинная превратится в повод не читать.
  static const int size = 12;

  /// Карточки для разминки: слова с ближайших страниц, самые забытые первыми.
  ///
  /// [horizon] — основы слов, которые встретятся дальше (см. `ReadingHorizon`).
  static List<WordCard> pick(
    List<WordCard> cards,
    Set<String> horizon,
    String languageCode, {
    int limit = size,
    DateTime? now,
  }) {
    if (horizon.isEmpty) return const [];
    final moment = now ?? DateTime.now();
    final fsrs = Fsrs.instance;

    final ahead = [
      for (final card in cards)
        if (horizon.contains(Lemmatizer.stem(card.front, languageCode))) card,
    ];

    // Впереди то, что вот-вот забудется: разминка должна спасать слабое, а не
    // перебирать твёрдое.
    ahead.sort((a, b) =>
        _recall(fsrs, a, moment).compareTo(_recall(fsrs, b, moment)));
    return ahead.take(limit).toList();
  }

  /// Вероятность вспомнить прямо сейчас. У новых слов её нет — их место в
  /// начале, они и вовсе не выучены.
  static double _recall(Fsrs fsrs, WordCard card, DateTime now) {
    final review = card.review;
    if (review.state == FsrsState.newCard || review.stability <= 0) return -1;
    final last = review.lastReview;
    if (last == null) return -1;
    final elapsed = now.difference(last).inMinutes / (60 * 24);
    return fsrs.retrievability(elapsed < 0 ? 0 : elapsed, review.stability);
  }
}
