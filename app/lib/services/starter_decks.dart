import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../models/deck.dart';
import '../models/word_card.dart';
import 'deck_repository.dart';

/// Готовая колода-стартер из ассетов (`assets/starter/<lang>.json`).
class StarterPack {
  final String languageCode;
  final String name;
  final int shapeIndex;
  final List<({String front, String back, String example})> cards;

  const StarterPack({
    required this.languageCode,
    required this.name,
    required this.shapeIndex,
    required this.cards,
  });

  int get wordCount => cards.length;
}

/// Загрузка и добавление готовых колод. Наборы лежат в ассетах и переводят на
/// русский (основная аудитория приложения).
class StarterDecks {
  StarterDecks._();

  /// Цвета обложек по индексу колоды в наборе.
  static const List<int> _palette = [
    0xFF2E7D5B,
    0xFF3F6FB0,
    0xFFB5622E,
    0xFF8A4FBF,
    0xFFB03F6F,
    0xFF4FA0A8,
  ];

  /// Языки, для которых есть готовые наборы (файлы `assets/starter/<code>.json`).
  /// Английский НЕ здесь — он сеется как набор по умолчанию.
  static const Set<String> availableLanguages = {'es', 'de', 'fr', 'it'};

  /// Возвращает готовые колоды для языка (пусто, если для него нет набора).
  static Future<List<StarterPack>> forLanguage(String code) async {
    String raw;
    try {
      raw = await rootBundle.loadString('assets/starter/$code.json');
    } catch (_) {
      return const [];
    }
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final lang = data['lang'] as String? ?? code;
      final decks = (data['decks'] as List? ?? []);
      return [
        for (final d in decks)
          StarterPack(
            languageCode: lang,
            name: (d as Map)['name'] as String? ?? '—',
            shapeIndex: (d['shape'] as num?)?.toInt() ?? 0,
            cards: [
              for (final c in (d['cards'] as List? ?? []))
                (
                  front: (c as Map)['front'] as String? ?? '',
                  back: c['back'] as String? ?? '',
                  example: c['example'] as String? ?? '',
                ),
            ],
          ),
      ];
    } catch (_) {
      return const [];
    }
  }

  /// Есть ли для языка готовый набор. Синхронная проверка по [availableLanguages]
  /// — без чтения ассета, чтобы не грузить хвост экрана (и не виснуть в тестах,
  /// где rootBundle не любит FakeAsync).
  static Future<bool> hasPacksFor(String code) async =>
      availableLanguages.contains(code);

  /// Добавляет готовую колоду в репозиторий свежей копией (новые id).
  static Future<void> add(StarterPack pack, {DateTime? now}) async {
    final repo = DeckRepository.instance;
    final stamp = (now ?? DateTime.now()).millisecondsSinceEpoch;
    final existing = await repo.loadDecks();
    final colorIndex = existing.length % _palette.length;
    final deckId = 'starter_${pack.languageCode}_$stamp';
    final deck = Deck(
      id: deckId,
      languageCode: pack.languageCode,
      name: pack.name,
      colorValue: _palette[colorIndex],
      shapeIndex: pack.shapeIndex,
      createdAt: stamp,
    );
    await repo.upsertDeck(deck);
    final cards = <WordCard>[
      for (var i = 0; i < pack.cards.length; i++)
        WordCard(
          id: 'card_${stamp}_$i',
          deckId: deckId,
          front: pack.cards[i].front,
          back: pack.cards[i].back,
          example: pack.cards[i].example,
        ),
    ];
    await repo.addCards(cards);
  }
}
