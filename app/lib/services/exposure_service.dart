import '../models/fsrs.dart';
import '../models/word_card.dart';
import 'deck_repository.dart';
import 'lemmatizer.dart';

/// Встречи слов в тексте как слабое подкрепление памяти.
///
/// Обычный SRS считает, что между сессиями человек лежал в темноте. В Fern это
/// не так: он читает книги, смотрит видео с субтитрами, снимает текст камерой.
/// Слово, встреченное вчера на странице, вспоминалось по-настоящему — и это
/// стоит учесть, прежде чем спрашивать его снова.
///
/// Подкрепление намеренно скромное и с оговорками (см. [Fsrs.passiveExposure]):
/// узнать слово в предложении легче, чем достать его из памяти по карточке.
class ExposureService {
  const ExposureService._();

  /// Отмечает встречи слов [words] (сырые слова из текста) на языке
  /// [languageCode]. Возвращает, скольким карточкам это пошло в зачёт.
  static Future<int> record(
    Iterable<String> words,
    String languageCode, {
    DateTime? now,
  }) async {
    if (words.isEmpty) return 0;
    final repo = DeckRepository.instance;
    final at = now ?? DateTime.now();

    // Слова текста и «перёд» карточек приводим к основам одинаково — иначе
    // «cats» на странице не найдёт карточку «cat».
    final stems = <String>{
      for (final w in words)
        if (w.trim().isNotEmpty) Lemmatizer.stem(w.trim(), languageCode),
    }..remove('');
    if (stems.isEmpty) return 0;

    final cards = await repo.cardsForLanguage(languageCode);
    final touched = <WordCard>[];
    for (final card in cards) {
      if (!stems.contains(Lemmatizer.stem(card.front, languageCode))) continue;
      final next = Fsrs.instance.passiveExposure(card.review, at);
      if (next == null) continue;
      card.review = next;
      touched.add(card);
    }

    if (touched.isNotEmpty) {
      await repo.updateCards(touched);
      await repo.addReinforcedByReading(touched.length);
    }
    return touched.length;
  }
}
