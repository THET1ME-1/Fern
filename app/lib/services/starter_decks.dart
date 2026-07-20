import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../l10n/strings.dart';
import '../models/deck.dart';
import '../models/word_card.dart';
import 'deck_repository.dart';

/// Готовая колода-стартер из ассетов (`assets/starter/<lang>.json`).
class StarterPack {
  final String languageCode;
  final String name;
  final int shapeIndex;
  final List<({String front, String back, String example})> cards;

  /// Ключ локализации имени — колода с ним переводится при смене языка.
  final String? nameKey;

  const StarterPack({
    required this.languageCode,
    required this.name,
    required this.shapeIndex,
    required this.cards,
    this.nameKey,
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

  /// Кладёт готовый набор для выбранного языка изучения — целиком, все колоды.
  ///
  /// Английский лежит отдельным ассетом (он же набор по умолчанию), остальные
  /// — в `assets/starter`. Для языка без набора не происходит ничего: пустой
  /// экран колод честнее чужих слов.
  static Future<void> seedFor(String code) async {
    if (code == 'en') {
      await DeckRepository.instance.seedDemoIfNeeded();
      return;
    }
    if (!availableLanguages.contains(code)) return;
    for (final pack in await forLanguage(code)) {
      await add(pack);
    }
  }

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
            nameKey: (d as Map)['nameKey'] as String?,
            name: localizedDeckName(
              nameKey: d['nameKey'] as String?,
              name: d['name'] as String?,
            ),
            shapeIndex: (d['shape'] as num?)?.toInt() ?? 0,
            cards: [
              for (final c in (d['cards'] as List? ?? []))
                (
                  front: (c as Map)['front'] as String? ?? '',
                  back: localizedBack(c['back']),
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
    // В идентификатор входит сам набор, а не только метка времени: четыре
    // колоды набора добавляются подряд и укладываются в одну миллисекунду —
    // с одинаковым id они затирали друг друга, и от набора оставалась
    // последняя колода.
    final slug = (pack.nameKey ?? pack.name).replaceAll(RegExp(r'\W+'), '_');
    final deckId = 'starter_${pack.languageCode}_${slug}_$stamp';
    final deck = Deck(
      id: deckId,
      languageCode: pack.languageCode,
      name: pack.name,
      colorValue: _palette[colorIndex],
      shapeIndex: pack.shapeIndex,
      createdAt: stamp,
      nameKey: pack.nameKey, // по ключу колода переведётся при смене языка
    );
    await repo.upsertDeck(deck);
    final cards = <WordCard>[
      for (var i = 0; i < pack.cards.length; i++)
        WordCard(
          id: '${deckId}_$i',
          deckId: deckId,
          front: pack.cards[i].front,
          back: pack.cards[i].back,
          example: pack.cards[i].example,
        ),
    ];
    await repo.addCards(cards);
  }
}
