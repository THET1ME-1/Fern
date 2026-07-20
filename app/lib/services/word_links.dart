import '../models/word_card.dart';
import 'lemmatizer.dart';

/// Тип связи между словами.
enum LinkKind {
  /// Близкие по смыслу: у карточек совпал перевод.
  synonym,

  /// Противоположные — только вручную: по переводу их не вычислить.
  antonym,

  /// От одного корня: `bright` / `brightness` / `brighten`.
  root,
}

extension LinkKindCode on LinkKind {
  /// Короткий код для хранения в JSON карточки.
  String get code => switch (this) {
        LinkKind.synonym => 'syn',
        LinkKind.antonym => 'ant',
        LinkKind.root => 'root',
      };

  String get titleKey => switch (this) {
        LinkKind.synonym => 'link_synonyms',
        LinkKind.antonym => 'link_antonyms',
        LinkKind.root => 'link_root',
      };
}

LinkKind? linkKindFromCode(String code) => switch (code) {
      'syn' => LinkKind.synonym,
      'ant' => LinkKind.antonym,
      'root' => LinkKind.root,
      _ => null,
    };

/// Одна связь: на какую карточку и какого рода.
/// [auto] — связь вычислена, а не проставлена руками (её нельзя снять,
/// но можно переопределить вручную).
class WordLink {
  final WordCard card;
  final LinkKind kind;
  final bool auto;

  const WordLink({required this.card, required this.kind, this.auto = false});
}

/// Семантические связи между карточками.
///
/// Часть связей Fern выводит сам из того, что уже лежит в базе: совпал перевод —
/// синонимы, совпала основа слова — однокоренные. Остальное человек ставит
/// руками, и это хранится в самой карточке ([WordCard.links]).
class WordLinks {
  const WordLinks._();

  /// Вычисленные связи карточки внутри [pool] (карты того же языка).
  static List<WordLink> auto(WordCard card, List<WordCard> pool, String lang) {
    final out = <WordLink>[];
    final back = _norm(card.back);
    final stem = Lemmatizer.stem(card.front, lang);
    final front = _norm(card.front);

    for (final other in pool) {
      if (other.id == card.id) continue;
      // Ручная связь главнее вычисленной: не дублируем.
      if (card.links.containsKey(other.id)) continue;

      if (back.isNotEmpty && _norm(other.back) == back) {
        out.add(WordLink(card: other, kind: LinkKind.synonym, auto: true));
        continue;
      }
      if (_sameRoot(front, stem, other.front, lang)) {
        out.add(WordLink(card: other, kind: LinkKind.root, auto: true));
      }
    }
    return out;
  }

  /// Ручные связи карточки, разрешённые в карты из [pool].
  static List<WordLink> manual(WordCard card, List<WordCard> pool) {
    final byId = {for (final c in pool) c.id: c};
    final out = <WordLink>[];
    card.links.forEach((id, code) {
      final target = byId[id];
      final kind = linkKindFromCode(code);
      if (target != null && kind != null) {
        out.add(WordLink(card: target, kind: kind));
      }
    });
    return out;
  }

  /// Все связи карточки: сперва проставленные руками, следом вычисленные.
  static List<WordLink> all(WordCard card, List<WordCard> pool, String lang) =>
      [...manual(card, pool), ...auto(card, pool, lang)];

  /// Связи, сгруппированные по типу (пустые группы не возвращаются).
  static Map<LinkKind, List<WordLink>> grouped(
    WordCard card,
    List<WordCard> pool,
    String lang,
  ) {
    final out = <LinkKind, List<WordLink>>{};
    for (final link in all(card, pool, lang)) {
      out.putIfAbsent(link.kind, () => []).add(link);
    }
    return out;
  }

  /// Ставит связь в обе стороны: связь односторонней не бывает.
  static void connect(WordCard a, WordCard b, LinkKind kind) {
    if (a.id == b.id) return;
    a.links[b.id] = kind.code;
    b.links[a.id] = kind.code;
  }

  /// Снимает связь с обеих карточек.
  static void disconnect(WordCard a, WordCard b) {
    a.links.remove(b.id);
    b.links.remove(a.id);
  }

  /// Однокоренные ли слова.
  ///
  /// Сперва общая основа (`cat` / `cats` — это ловит [Lemmatizer]), затем
  /// словообразование, до которого лемматизатору дела нет: `bright` →
  /// `brightness`, `brighten`. Там работает префикс, но с порогами, иначе
  /// вылезут `boot` / `booth` и `car` / `carpet`: корень от четырёх букв,
  /// хвост от двух и не длиннее шести.
  static bool _sameRoot(String front, String stem, String otherRaw, String lang) {
    final other = _norm(otherRaw);
    if (other == front || other.isEmpty) return false;

    if (stem.length >= 3 && Lemmatizer.stem(otherRaw, lang) == stem) return true;

    final (shorter, longer) =
        front.length <= other.length ? (front, other) : (other, front);
    if (shorter.length < 4) return false;
    if (!longer.startsWith(shorter)) return false;
    final tail = longer.length - shorter.length;
    if (tail < 2 || tail > 6) return false;
    // Общий префикс — слабая улика: rest/restaurant, cost/costume,
    // fort/fortune начинаются одинаково и родства не имеют. Связь `root`
    // входит в spreadingKinds, поэтому цена ошибки не косметическая: срыв на
    // «restaurant» тянул к досрочному повтору ни в чём не повинный «rest».
    // Просим подтверждения от словообразования: хвост должен быть похож на
    // суффикс, а не на начало другого слова.
    return _looksLikeSuffix(longer.substring(shorter.length));
  }

  /// Продолжение слова похоже на суффикс, а не на случайное совпадение начала.
  ///
  /// Список закрытый: словообразовательных суффиксов в языке конечное число, а
  /// «любые две-шесть букв» — это половина словаря.
  static const List<String> _suffixes = [
    'er', 'ers', 'or', 'ors', 'ist', 'ists', 'ing', 'ings', 'ed', 'es', 's',
    'ness', 'ment', 'ments', 'tion', 'sion', 'ity', 'ties', 'ance', 'ence',
    'able', 'ible', 'al', 'ial', 'ful', 'less', 'ly', 'y', 'ish', 'ive',
    'ous', 'en', 'ify', 'ize', 'ise', 'hood', 'ship', 'dom', 'age',
  ];

  static bool _looksLikeSuffix(String tail) {
    final t = tail.toLowerCase();
    return _suffixes.contains(t);
  }

  static String _norm(String s) => s.trim().toLowerCase();
}
