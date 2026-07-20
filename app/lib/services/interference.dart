import '../models/word_card.dart';
import '../utils/text_distance.dart';

/// Слова, которые человек путает между собой.
///
/// `affect` и `effect`, два разных слова с одним переводом «яркий», `собака` и
/// `собрание` — введённые вместе, они портят друг друга: память цепляется не за
/// смысл, а за похожую форму, и обе карточки становятся «пиявками». Anki разводит
/// только карточки одной заметки; слова из разных колод, которые путаются, не
/// разводит никто.
///
/// Здесь два приёма: не вводить конфликтующие слова в один заход и держать их
/// подальше друг от друга внутри очереди.
class Interference {
  const Interference._();

  /// Насколько близкими по написанию словам считаться путаемыми.
  static const int maxEditDistance = 2;

  /// Слова короче этого сравнивать по написанию бессмысленно: у трёхбуквенных
  /// расстояние 2 — это уже совсем другое слово.
  static const int minLength = 4;

  /// Минимальный разрыв между путаемыми словами внутри одной очереди.
  static const int minGap = 4;

  /// Путаются ли слова.
  static bool conflict(WordCard a, WordCard b) {
    if (a.id == b.id) return false;

    final fa = _norm(a.front);
    final fb = _norm(b.front);
    final ba = _norm(a.back);
    final bb = _norm(b.back);

    // Одинаковый перевод: при вопросе «как будет „яркий“?» человек мечется
    // между двумя верными ответами и запоминает, что «тут я всегда ошибаюсь».
    if (ba.isNotEmpty && ba == bb) return true;

    // Похожая форма слова.
    if (fa.length >= minLength && fb.length >= minLength) {
      if ((fa.length - fb.length).abs() <= maxEditDistance &&
          levenshtein(fa, fb) <= maxEditDistance) {
        return true;
      }
    }
    return false;
  }

  /// Отбирает новые слова так, чтобы в один заход не попали путаемые.
  ///
  /// [busy] — карты, которые уже в работе (введены недавно, ещё не улеглись):
  /// с ними новое слово тоже не должно спорить.
  static List<WordCard> pickNew(
    List<WordCard> candidates,
    List<WordCard> busy,
  ) {
    final chosen = <WordCard>[];
    final deferred = <WordCard>[];
    for (final card in candidates) {
      final clashes = busy.any((b) => conflict(card, b)) ||
          chosen.any((c) => conflict(card, c));
      (clashes ? deferred : chosen).add(card);
    }
    // Отложенные не выбрасываем: если новых больше не набралось, пусть лучше
    // будет спорная карта, чем пустая сессия.
    return [...chosen, ...deferred];
  }

  /// Раздвигает путаемые слова внутри очереди, сохраняя общий порядок.
  static List<WordCard> spread(List<WordCard> queue, {int gap = minGap}) {
    if (queue.length < 3) return queue;
    final out = <WordCard>[];
    final rest = List<WordCard>.from(queue);

    while (rest.isNotEmpty) {
      // Берём первую карту, которая не спорит с недавно выложенными.
      final recent = out.length <= gap ? out : out.sublist(out.length - gap);
      var idx = rest.indexWhere(
        (card) => !recent.any((r) => conflict(card, r)),
      );
      // Все оставшиеся спорят с хвостом — значит, разводить уже некуда.
      if (idx < 0) idx = 0;
      out.add(rest.removeAt(idx));
    }
    return out;
  }

  /// Сколько путаемых ПАР есть в наборе. Нужно, чтобы сессия могла честно
  /// сказать, сколько ловушек развела: слов в парах может быть меньше, чем пар
  /// (одно слово спорит сразу с двумя), поэтому считаем именно пары.
  static int countConflicts(List<WordCard> cards) {
    var n = 0;
    for (var i = 0; i < cards.length; i++) {
      for (var j = i + 1; j < cards.length; j++) {
        if (conflict(cards[i], cards[j])) n++;
      }
    }
    return n;
  }

  static String _norm(String s) => s.trim().toLowerCase();
}
