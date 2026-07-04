import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../models/deck.dart';
import '../models/word_card.dart';
import '../services/deck_repository.dart';

/// Куда складывать слова, разобранные из видео. Управляется настройкой
/// `addWordMode`:
///  * `auto` — колода «Из видео» для языка создаётся/берётся молча;
///  * `manual` — спросить колоду (один раз за сессию разбора);
///  * `remember` — взять последнюю выбранную (через сессии), иначе спросить.
class VideoDeckTarget {
  const VideoDeckTarget._();

  static const int _defaultColor = 0xFF2E7D5B;

  /// Определяет целевую колоду для языка [languageCode]. Может показать выбор
  /// (bottom sheet). Возвращает null, если пользователь отменил выбор.
  static Future<Deck?> resolve(
    BuildContext context,
    String languageCode,
  ) async {
    final repo = DeckRepository.instance;
    final mode = await repo.addWordMode();
    final decks =
        repo.decks.where((d) => d.languageCode == languageCode).toList();

    switch (mode) {
      case 'auto':
        return _autoDeck(repo, languageCode, decks);
      case 'remember':
        final lastId = await repo.lastVideoDeckId();
        final last = decks.where((d) => d.id == lastId).firstOrNull;
        if (last != null) return last;
        if (!context.mounted) return null;
        final picked = await _pick(context, decks, languageCode);
        if (picked != null) await repo.setLastVideoDeckId(picked.id);
        return picked;
      case 'manual':
      default:
        if (!context.mounted) return null;
        final picked = await _pick(context, decks, languageCode);
        if (picked != null) await repo.setLastVideoDeckId(picked.id);
        return picked;
    }
  }

  /// Берёт колоду «Из видео» для языка или создаёт её.
  static Future<Deck> _autoDeck(
    DeckRepository repo,
    String languageCode,
    List<Deck> decks,
  ) async {
    final name = tr('video_deck_name');
    final existing = decks.where((d) => d.name == name).firstOrNull;
    if (existing != null) return existing;
    return _create(repo, languageCode, name);
  }

  static Future<Deck> _create(
    DeckRepository repo,
    String languageCode,
    String name,
  ) async {
    final deck = Deck(
      id: 'deck_${DateTime.now().microsecondsSinceEpoch}',
      languageCode: languageCode,
      name: name,
      colorValue: _defaultColor,
      shapeIndex: 0,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    await repo.upsertDeck(deck);
    return deck;
  }

  /// Лист выбора колоды + пункт «создать колоду из видео».
  static Future<Deck?> _pick(
    BuildContext context,
    List<Deck> decks,
    String languageCode,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return showModalBottomSheet<Deck>(
      context: context,
      backgroundColor: scheme.surfaceContainer,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 14),
            Text(
              tr('pick_deck'),
              style: Theme.of(ctx).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final d in decks)
                    ListTile(
                      leading: CircleAvatar(
                        backgroundColor: d.color,
                        radius: 14,
                      ),
                      title: Text(d.name),
                      onTap: () => Navigator.pop(ctx, d),
                    ),
                  ListTile(
                    leading: Icon(Icons.add_rounded, color: scheme.primary),
                    title: Text(tr('add_new_deck_video')),
                    onTap: () async {
                      final deck = await _create(
                        DeckRepository.instance,
                        languageCode,
                        tr('video_deck_name'),
                      );
                      if (ctx.mounted) Navigator.pop(ctx, deck);
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// Добавляет слово в колоду с дедупом по «переду» (без учёта регистра).
  /// Возвращает true, если добавлено; false — если уже было.
  static Future<bool> addWord(
    Deck deck, {
    required String front,
    required String back,
    String example = '',
    String sentence = '',
    String sourceUrl = '',
    int? clipStartMs,
    int? clipEndMs,
  }) async {
    final repo = DeckRepository.instance;
    final f = front.trim();
    if (f.isEmpty || back.trim().isEmpty) return false;
    final existing = await repo.cardsForDeck(deck.id);
    if (existing.any((c) => c.front.trim().toLowerCase() == f.toLowerCase())) {
      return false;
    }
    await repo.upsertCard(
      WordCard(
        id: 'card_${DateTime.now().microsecondsSinceEpoch}',
        deckId: deck.id,
        front: f,
        back: back.trim(),
        example: example.trim(),
        sentence: sentence.trim(),
        sourceUrl: sourceUrl.trim(),
        clipStartMs: clipStartMs,
        clipEndMs: clipEndMs,
      ),
    );
    return true;
  }
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
