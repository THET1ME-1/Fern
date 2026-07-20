import 'package:flutter_test/flutter_test.dart';
import 'package:fern/models/deck.dart';
import 'package:fern/models/word_card.dart';
import 'package:fern/services/deck_repository.dart';
import 'package:fern/services/exposure_service.dart';
import 'package:fern/services/link_propagation.dart';

import 'test_helpers.dart';

/// Подкрепление чтением трогает несколько карточек из многих. Всё остальное
/// обязано остаться на месте: словарь — единственное, что человек собирал
/// руками месяцами, и потеря здесь необратима.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final repo = DeckRepository.instance;

  setUp(resetStorage);

  Future<void> seed() async {
    await repo.upsertDeck(Deck(
      id: 'd1',
      languageCode: 'en',
      name: 'Слова',
      colorValue: 0xFF2E7D5B,
      shapeIndex: 0,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    ));
    for (final word in ['fox', 'table', 'river', 'stone', 'cloud']) {
      await repo.upsertCard(WordCard(
        id: word,
        deckId: 'd1',
        front: word,
        back: 'перевод',
        // Слово подзабыто: только такому встреча в тексте что-то добавляет
        // (подкрепление работает при вероятности вспомнить ниже 0.9).
        review: ReviewState(
          stability: 2,
          difficulty: 5,
          state: FsrsState.review,
          lastReview: DateTime.now().subtract(const Duration(days: 10)),
          due: DateTime.now().subtract(const Duration(days: 8)),
        ),
      ));
    }
  }

  test('Встреченное в книге слово не стирает остальной словарь', () async {
    await seed();
    expect((await repo.loadCards()).length, 5);

    // В прочитанном куске встретилось одно слово из пяти.
    await ExposureService.record({'fox'}, 'en');

    final after = await repo.loadCards();
    expect(after.length, 5, reason: 'остальные четыре карточки на месте');
    expect(after.map((c) => c.front), containsAll(['table', 'river', 'stone']));
  });

  test('Словарь переживает перезапуск после подкрепления чтением', () async {
    await seed();
    await ExposureService.record({'river', 'stone'}, 'en');

    // «Перезапуск»: кэш сброшен, данные читаются с диска.
    repo.resetForTest();
    expect((await repo.loadCards()).length, 5);
  });

  test('Ослабление соседей после срыва не стирает словарь', () async {
    await seed();
    final cards = await repo.loadCards();
    final weakened = LinkPropagation.afterLapse(cards.first, cards, 'en');
    // Даже если соседей не нашлось, путь сохранения не должен резать таблицу.
    await repo.updateCards(weakened.isEmpty ? [cards.first] : weakened);
    repo.resetForTest();
    expect((await repo.loadCards()).length, 5);
  });
}
