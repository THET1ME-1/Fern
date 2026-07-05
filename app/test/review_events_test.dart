import 'package:flutter_test/flutter_test.dart';

import 'package:fern/models/fsrs.dart';
import 'package:fern/models/word_card.dart';
import 'package:fern/services/deck_repository.dart';

import 'test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final repo = DeckRepository.instance;

  setUp(resetStorage);

  test('rateCard пишет событие в журнал повторов', () async {
    await repo.init();
    final card = WordCard(id: 'c1', deckId: 'd1', front: 'a', back: 'б');
    await repo.upsertCard(card);
    expect(await repo.reviewEventCount(), 0);

    await repo.rateCard(card, Rating.good, DateTime(2026, 1, 1, 12));
    await repo.rateCard(card, Rating.again, DateTime(2026, 1, 1, 12, 20));

    expect(await repo.reviewEventCount(), 2);
    final events = await repo.reviewEvents();
    expect(events.first.cardId, 'c1');
    expect(events.first.grade, Rating.good.grade);
    expect(events.first.stateBefore, FsrsState.newCard.index);
    expect(events.last.grade, Rating.again.grade);
  });

  test('целевое удержание сохраняется и применяется к планировщику', () async {
    await repo.init();
    await repo.setRequestRetention(0.85);
    expect(await repo.requestRetention(), 0.85);
    expect(Fsrs.instance.requestRetention, 0.85);

    // applyFsrsSettings поднимает сохранённое значение в планировщик.
    Fsrs.instance.requestRetention = 0.9; // сбили
    await repo.applyFsrsSettings();
    expect(Fsrs.instance.requestRetention, 0.85);
  });

  test('персональные веса сохраняются и сбрасываются', () async {
    await repo.init();
    final custom = List<double>.of(Fsrs.defaultWeights)..[2] = 5.5;
    await repo.setFsrsWeights(custom);
    expect(Fsrs.instance.w[2], 5.5);
    expect((await repo.fsrsWeights())?[2], 5.5);

    await repo.setFsrsWeights(null);
    expect(Fsrs.instance.w[2], Fsrs.defaultWeights[2]);
    expect(await repo.fsrsWeights(), isNull);
  });
}
