import '../models/word_card.dart';
import 'deck_repository.dart';
import 'lemmatizer.dart';
import 'text_analysis.dart';

/// Знакомая замена слову из ответа: «сказал `big`, а ты знаешь `huge`».
class WordUpgrade {
  /// Слово, которое человек употребил.
  final String used;

  /// Карточка из его же словаря с тем же значением.
  final WordCard better;

  const WordUpgrade(this.used, this.better);
}

/// Подсказки к собственному ответу.
class ReplyHints {
  /// Слова ответа, которые уже есть в словаре, — их человек применил сам.
  final List<String> used;

  /// Слова ответа, которых в словаре нет: кандидаты в карточки.
  final List<String> fresh;

  /// Знакомые синонимы к употреблённым словам.
  final List<WordUpgrade> upgrades;

  const ReplyHints({
    required this.used,
    required this.fresh,
    required this.upgrades,
  });

  static const ReplyHints empty =
      ReplyHints(used: [], fresh: [], upgrades: []);
}

/// Разбор собственного ответа: что из своего словаря пошло в дело, чего не
/// хватило и где вместо простого слова просилось выученное.
///
/// Смысл: словарь копится, а в живой речи человек по привычке обходится
/// десятком первых слов. Подсказка «ты уже учил слово посильнее» переводит
/// запас из пассивного в рабочий.
class ReplyAnalysis {
  const ReplyAnalysis._();

  /// Сколько замен предлагать: список длиннее человек не читает.
  static const int maxUpgrades = 6;

  static ReplyHints of(TextAnalysis analysis, String languageCode) {
    if (analysis.tokens.isEmpty) return ReplyHints.empty;
    final cards = DeckRepository.instance.cardsForLanguageSync(languageCode);

    final used = <String>[];
    final fresh = <String>[];
    final seenUsed = <String>{};
    final upgrades = <WordUpgrade>[];
    final offered = <String>{};

    for (final token in analysis.tokens) {
      if (!token.isWord) continue;
      final lower = token.surface.toLowerCase();
      if (token.status == WordStatus.unknown) {
        if (!fresh.contains(lower)) fresh.add(lower);
        continue;
      }
      if (!seenUsed.add(lower)) continue;
      used.add(lower);

      final card = _cardById(cards, token.cardId);
      if (card == null) continue;
      for (final other in _synonyms(cards, card, languageCode)) {
        if (!offered.add(other.id)) continue;
        upgrades.add(WordUpgrade(lower, other));
        break; // на слово хватает одной замены
      }
    }

    return ReplyHints(
      used: used,
      fresh: fresh,
      upgrades: upgrades.take(maxUpgrades).toList(),
    );
  }

  static WordCard? _cardById(List<WordCard> cards, String? id) {
    if (id == null) return null;
    for (final c in cards) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// Карточки с тем же значением, что у [card]: сравниваем переводы по
  /// отдельным значениям («яркий, светлый» → два ключа), иначе синонимом
  /// считалась бы только полная строка перевода.
  static List<WordCard> _synonyms(
    List<WordCard> cards,
    WordCard card,
    String languageCode,
  ) {
    final keys = _meanings(card);
    if (keys.isEmpty) return const [];
    final stem = Lemmatizer.stem(card.front, languageCode);
    final out = <WordCard>[];
    for (final other in cards) {
      if (other.id == card.id || other.isRule) continue;
      if (Lemmatizer.stem(other.front, languageCode) == stem) continue;
      if (_meanings(other).any(keys.contains)) out.add(other);
    }
    // Вперёд идут те, что человек помнит крепче: советовать слово, которое он
    // сам едва помнит, значит подставлять его в собственном ответе.
    out.sort((a, b) => b.review.stability.compareTo(a.review.stability));
    return out;
  }

  static Set<String> _meanings(WordCard card) => {
        for (final part in card.back.split(RegExp(r'[,;/]')))
          if (part.trim().isNotEmpty) part.trim().toLowerCase(),
      };
}
