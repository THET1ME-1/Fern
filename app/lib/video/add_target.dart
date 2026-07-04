import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../models/deck.dart';
import '../models/pack.dart';
import '../models/word_card.dart';
import '../services/deck_repository.dart';
import '../widgets/deck_editor_sheet.dart';

/// Куда складывать слова, разобранные из источника (видео или книга).
///
/// У КАЖДОГО источника — свой **пак** (папка с его названием): видео → пак с
/// названием ролика, книга → пак с названием книги. Пак не дублируется: если
/// он уже есть (сравнение по названию без учёта регистра), переиспользуем.
/// Внутри пака пользователь выбирает существующую колоду слов или создаёт
/// новую. Так одна книга/видео не плодит десяток одинаковых списков.
class VideoDeckTarget {
  const VideoDeckTarget._();

  static const int _packColor = 0xFF3F6FB0;

  /// Целевая колода для источника [sourceTitle] на языке [languageCode].
  /// Гарантирует пак источника, затем даёт выбрать/создать колоду внутри него.
  /// Возвращает null, если пользователь отменил.
  static Future<Deck?> resolveInSourcePack(
    BuildContext context,
    String languageCode,
    String sourceTitle,
  ) async {
    final repo = DeckRepository.instance;
    final pack = await _ensureSourcePack(repo, languageCode, sourceTitle);
    if (!context.mounted) return null;
    final decks = repo.decks.where((d) => d.packId == pack.id).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    // Пак пуст — молча создаём первую колоду «Слова» в паке (без диалогов).
    if (decks.isEmpty) {
      return _createDeckInPack(
          repo, languageCode, pack.id, tr('deck_words_default'));
    }
    if (!context.mounted) return null;
    return _pickDeckInPack(context, repo, pack, decks, languageCode);
  }

  static Future<Deck> _createDeckInPack(
    DeckRepository repo,
    String languageCode,
    String packId,
    String name,
  ) async {
    final deck = Deck(
      id: 'deck_${DateTime.now().microsecondsSinceEpoch}',
      languageCode: languageCode,
      name: name,
      colorValue: 0xFF2E7D5B,
      shapeIndex: 0,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      packId: packId,
    );
    await repo.upsertDeck(deck);
    return deck;
  }

  /// Пак источника: существующий (по названию, без учёта регистра) или новый.
  static Future<Pack> _ensureSourcePack(
    DeckRepository repo,
    String languageCode,
    String title,
  ) async {
    final name = title.trim().isEmpty ? tr('source_pack_fallback') : title.trim();
    final key = name.toLowerCase();
    final existing = repo.packs
        .where((p) =>
            p.languageCode == languageCode &&
            p.name.trim().toLowerCase() == key)
        .firstOrNull;
    if (existing != null) return existing;
    final pack = Pack(
      id: 'pack_src_${DateTime.now().millisecondsSinceEpoch}',
      languageCode: languageCode,
      name: name,
      colorValue: _packColor,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    await repo.upsertPack(pack);
    return pack;
  }

  /// Простой выбор колоды внутри пака + пункт «создать новую колоду в паке».
  static Future<Deck?> _pickDeckInPack(
    BuildContext context,
    DeckRepository repo,
    Pack pack,
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
              pack.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(ctx).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final d in decks)
                    ListTile(
                      leading:
                          CircleAvatar(backgroundColor: d.color, radius: 14),
                      title: Text(d.name),
                      onTap: () => Navigator.pop(ctx, d),
                    ),
                  ListTile(
                    leading: Icon(Icons.add_rounded, color: scheme.primary),
                    title: Text(tr('new_deck_in_pack')),
                    onTap: () async {
                      final d = await showDeckEditor(
                        ctx,
                        languageCode: languageCode,
                        fixedPackId: pack.id,
                      );
                      if (d != null) await repo.upsertDeck(d);
                      if (ctx.mounted) Navigator.pop(ctx, d);
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

  /// Добавляет слово в колоду с дедупом ПО ВСЕЙ базе языка колоды (если слово
  /// уже есть в любой колоде этого языка — не добавляем). Возвращает true, если
  /// добавлено; false — если уже было (или пусто).
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
    if (repo.hasWordInLanguage(f, deck.languageCode)) return false;
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
