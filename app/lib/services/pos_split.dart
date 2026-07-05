import '../l10n/strings.dart';
import '../models/deck.dart';
import '../models/pack.dart';
import '../models/word_card.dart';
import 'deck_repository.dart';
import 'pos.dart';

/// Разбивка колоды на отдельные колоды по частям речи (глаголы, существительные,
/// артикли …) — по полю [WordCard.pos] (или определяя на лету). Новые колоды
/// складываются в общий пак; слова без определённой части речи остаются в
/// исходной колоде.
class PosSplit {
  const PosSplit._();

  // Отдельный цвет каждой части речи (для наглядных обложек).
  static const Map<String, int> _colors = {
    'noun': 0xFF2E7D5B,
    'verb': 0xFFB5622E,
    'adj': 0xFF3F6FB0,
    'adv': 0xFF7A5AA8,
    'pronoun': 0xFF2E9E6B,
    'article': 0xFF8A8A85,
    'prep': 0xFFC28A2B,
    'conj': 0xFF6B8E23,
    'num': 0xFF4F7A34,
    'particle': 0xFFA0522D,
    'interj': 0xFFCB4E6B,
  };

  /// Часть речи карты: сохранённая → метка, вклеенная в слово → эвристика.
  static String _codeFor(WordCard c, String lang) {
    if (c.pos.isNotEmpty) return c.pos;
    final stripped = PosDetect.strip(c.front);
    if (stripped.$2 != null) return stripped.$2!;
    return PosDetect.detect(c.front, languageCode: lang);
  }

  /// Сколько РАЗНЫХ частей речи можно выделить в колоде (для предложения).
  static Future<int> countGroups(Deck deck) async {
    final cards = await DeckRepository.instance.cardsForDeck(deck.id);
    final codes = <String>{};
    for (final c in cards) {
      final code = _codeFor(c, deck.languageCode);
      if (code.isNotEmpty) codes.add(code);
    }
    return codes.length;
  }

  /// Раскладывает колоду по частям речи. Возвращает число созданных колод
  /// (0 — если частей речи меньше двух, разбивать нечего). Заодно вычищает
  /// вклеенную в слово метку («the артикль» → «the») у старых карт.
  static Future<int> split(Deck deck, {DateTime? now}) async {
    final repo = DeckRepository.instance;
    final cards = await repo.cardsForDeck(deck.id);

    final byPos = <String, List<WordCard>>{};
    for (final c in cards) {
      var code = c.pos;
      if (code.isEmpty) {
        final stripped = PosDetect.strip(c.front);
        if (stripped.$2 != null) {
          c.front = stripped.$1; // чистим слово от метки
          code = stripped.$2!;
        } else {
          code = PosDetect.detect(c.front, languageCode: deck.languageCode);
        }
      }
      if (code.isEmpty) continue;
      byPos.putIfAbsent(code, () => []).add(c);
    }
    final codes =
        PosDetect.order.where((c) => byPos[c]?.isNotEmpty ?? false).toList();
    if (codes.length < 2) return 0;

    final stamp = (now ?? DateTime.now()).millisecondsSinceEpoch;
    final pack = Pack(
      id: 'pack_pos_$stamp',
      languageCode: deck.languageCode,
      name: trf('split_pack', {'name': deck.name}),
      colorValue: deck.colorValue,
      createdAt: stamp,
    );
    await repo.upsertPack(pack);
    // Исходную колоду тоже кладём в пак — в ней остаются слова без части речи.
    await repo.setDeckPack(deck.id, pack.id);

    var created = 0;
    for (final code in codes) {
      final list = byPos[code]!;
      final newDeck = Deck(
        id: 'deck_pos_${code}_${stamp}_$created',
        languageCode: deck.languageCode,
        name: tr('pos_deck_$code'),
        colorValue: _colors[code] ?? 0xFF2E7D5B,
        shapeIndex: created % 6,
        createdAt: stamp + created,
        packId: pack.id,
      );
      await repo.upsertDeck(newDeck);
      await repo.moveCards(list.map((c) => c.id), newDeck.id);
      created++;
    }
    return created;
  }
}
