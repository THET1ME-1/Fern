import '../models/fsrs.dart';
import '../models/word_card.dart';
import 'word_links.dart';

/// Перенос сомнения по связям слова.
///
/// FSRS считает карточки независимыми: сорвался на `bright` — и `brightness`
/// с `brighten` это никак не касается. В жизни иначе: слова одного гнезда
/// держатся вместе и осыпаются вместе. Fern знает связи, поэтому может спросить
/// соседей пораньше.
///
/// Строго в одну сторону — срыв соседа приближает повтор, успех соседа ничего
/// не отодвигает. Спросить лишний раз дёшево; отложить слово, которое на самом
/// деле забыто, значит потерять его.
class LinkPropagation {
  const LinkPropagation._();

  /// Скольким соседям максимум передаётся сомнение за один срыв.
  static const int maxNeighbours = 5;

  /// Связи, по которым сомнение переносится. Антонимы сюда не входят: знание
  /// `dark` не держится на знании `bright`, они просто про одно поле смысла.
  static const Set<LinkKind> spreadingKinds = {
    LinkKind.synonym,
    LinkKind.root,
  };

  /// Возвращает соседей [card], которых стоит спросить раньше, уже с
  /// обновлённым состоянием. Пустой список — переносить нечего.
  static List<WordCard> afterLapse(
    WordCard card,
    List<WordCard> pool,
    String languageCode, {
    DateTime? now,
  }) {
    final at = now ?? DateTime.now();
    final links = WordLinks.all(card, pool, languageCode)
        .where((l) => spreadingKinds.contains(l.kind))
        .take(maxNeighbours);

    final touched = <WordCard>[];
    for (final link in links) {
      final next = Fsrs.instance.weakenByNeighbour(link.card.review, at);
      if (next == null) continue;
      link.card.review = next;
      touched.add(link.card);
    }
    return touched;
  }
}
