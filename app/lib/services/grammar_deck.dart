import '../l10n/strings.dart';
import '../models/deck.dart';
import '../models/word_card.dart';
import 'deck_repository.dart';

/// Колода грамматики: правила языка, взятые из собственных текстов.
///
/// Правило хранится обычной карточкой ([WordCard.rule] — код конструкции), и
/// это главное решение: планировщик, сессии, статистика, экспорт и резервная
/// копия начинают работать с грамматикой без единой правки. Отдельная сущность
/// «правило» потребовала бы своей таблицы, своего FSRS и своего экрана
/// статистики.
class GrammarDeck {
  const GrammarDeck._();

  /// Обложка колоды — синяя: зелёный занят словарными колодами по умолчанию.
  static const int deckColor = 0xFF3F6FB0;

  /// Идентификатор колоды детерминированный: имя локализовано и меняется вслед
  /// за языком интерфейса, искать по нему нельзя.
  static String deckIdFor(String languageCode) => 'deck_grammar_$languageCode';

  /// Колода правил языка (создаётся при первом обращении).
  static Future<Deck> ensure(String languageCode) async {
    final repo = DeckRepository.instance;
    final id = deckIdFor(languageCode);
    for (final d in repo.decks) {
      if (d.id == id) return d;
    }
    final deck = Deck(
      id: id,
      languageCode: languageCode,
      name: tr('grammar_deck_name'),
      colorValue: deckColor,
      shapeIndex: 3,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    await repo.upsertDeck(deck);
    return deck;
  }

  /// Карточка правила [code] на языке [languageCode] или null.
  static WordCard? find(String code, String languageCode) {
    for (final c in DeckRepository.instance.cardsForLanguageSync(languageCode)) {
      if (c.rule == code) return c;
    }
    return null;
  }

  /// Все карточки правил языка.
  static List<WordCard> rules(String languageCode) => [
        for (final c in DeckRepository.instance.cardsForLanguageSync(languageCode))
          if (c.isRule) c,
      ];

  /// Заводит карточку правила. Возвращает уже существующую, если правило взято
  /// раньше: одно правило — одна карточка, иначе повторный разбор того же
  /// текста плодил бы дубли с разными примерами.
  static Future<WordCard> add({
    required String languageCode,
    required String code,
    required String name,
    required String hint,
    required String example,
  }) async {
    final existing = find(code, languageCode);
    if (existing != null) return existing;
    final deck = await ensure(languageCode);
    final card = WordCard(
      id: 'rule_${code}_${DateTime.now().microsecondsSinceEpoch}',
      deckId: deck.id,
      front: name,
      back: hint,
      example: example,
      sentence: example,
      rule: code,
    );
    await DeckRepository.instance.upsertCard(card);
    return card;
  }
}

