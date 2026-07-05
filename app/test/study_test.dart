import 'package:flutter_test/flutter_test.dart';

import 'package:fern/models/word_card.dart';
import 'package:fern/study/study_models.dart';

WordCard _c(String id, {LearnPhase phase = LearnPhase.unseen, bool isNew = true}) {
  final card = WordCard(id: id, deckId: 'd', front: 'f$id', back: 'b$id');
  card.review.phase = phase;
  if (!isNew) {
    card.review.state = FsrsState.review;
    card.review.due = DateTime(2000); // давно просрочена → due
    card.review.stability = 30;
  }
  return card;
}

void main() {
  final builder = SessionBuilder();
  final now = DateTime(2026, 7, 3, 12);

  group('SessionBuilder по режимам', () {
    final cards = [for (var i = 0; i < 8; i++) _c('$i')];

    test('flashcards — флип-упражнения, не больше дневной цели', () {
      final q = builder.build(StudyMode.flashcards, cards, now, newAllowed: 5);
      expect(q.length, 5);
      expect(q.every((e) => e.kind == ExerciseKind.flip), true);
    });

    test('write — упражнения на ввод', () {
      final q = builder.build(StudyMode.write, cards, now, newAllowed: 6);
      expect(q.length, 6);
      expect(q.every((e) => e.kind == ExerciseKind.type), true);
    });

    test('test — фиксированное число, разные типы', () {
      final q = builder.build(StudyMode.test, cards, now, testCount: 6);
      expect(q.length, 6);
    });

    test('speed — выбор варианта при достаточном пуле', () {
      final q = builder.build(StudyMode.speed, cards, now, newAllowed: 10);
      expect(q.isNotEmpty, true);
      expect(q.every((e) => e.kind == ExerciseKind.choose), true);
    });

    test('match — пустая очередь (отдельный экран-игра)', () {
      expect(builder.build(StudyMode.match, cards, now), isEmpty);
    });

    test('audio — упражнения на слух (listen)', () {
      final q = builder.build(StudyMode.audio, cards, now, newAllowed: 6);
      expect(q.length, 6);
      expect(q.every((e) => e.kind == ExerciseKind.listen), true);
    });

    test('hard — только трудные карты (lapses/сложность)', () {
      final hardCard = _c('h', isNew: false)
        ..review.lapses = 3
        ..review.difficulty = 8;
      final easy = _c('e', isNew: false)..review.difficulty = 2;
      final q = builder.build(StudyMode.hard, [hardCard, easy], now);
      expect(q.length, 1);
      expect(q.first.card.id, 'h');
    });

    test('learn — тип упражнения зависит от фазы владения', () {
      final recall = _c('r', phase: LearnPhase.recall);
      final q = builder.build(StudyMode.learn, [recall, ..._c8()], now, newAllowed: 20);
      final ex = q.firstWhere((e) => e.card.id == 'r');
      expect(ex.kind, ExerciseKind.type); // фаза recall → ввод
    });
  });

  group('Проверка ответа (толерантная)', () {
    test('точное совпадение без учёта регистра/пробелов', () {
      expect(answerMatches('  Привет ', 'привет'), true);
    });
    test('одна опечатка (Левенштейн ≤1) для длинных слов', () {
      expect(answerMatches('privet', 'privt'), true);
      expect(answerMatches('cat', 'bat'), false); // короткие — строго
    });
    test('несколько вариантов через запятую', () {
      expect(answerMatches('ехать', 'идти, ехать'), true);
    });
    test('пустой ввод — неверно', () {
      expect(answerMatches('', 'привет'), false);
    });
  });

  group('Направление изучения', () {
    final cards = [for (var i = 0; i < 6; i++) _c('$i')];
    test('forward — все упражнения прямые', () {
      final q = builder.build(StudyMode.flashcards, cards, now,
          newAllowed: 6, direction: StudyDirection.forward);
      expect(q.every((e) => !e.reversed), true);
    });
    test('reverse — все упражнения обратные', () {
      final q = builder.build(StudyMode.flashcards, cards, now,
          newAllowed: 6, direction: StudyDirection.reverse);
      expect(q.every((e) => e.reversed), true);
    });
  });

  test('дистракторы не содержат правильный ответ и берутся из пула', () {
    final cards = [for (var i = 0; i < 6; i++) _c('$i')];
    final ex = Exercise(cards.first, ExerciseKind.choose);
    final d = builder.distractors(ex, cards, n: 3);
    expect(d.length, 3);
    expect(d.contains(ex.answer), false);
  });

  test('дистракторы предпочитают ту же часть речи', () {
    WordCard w(String id, String front, String back, String pos) =>
        WordCard(id: id, deckId: 'd', front: front, back: back, pos: pos);
    final target = w('t', 'run', 'бежать', 'verb');
    final pool = [
      target,
      w('v1', 'jump', 'прыгать', 'verb'),
      w('v2', 'swim', 'плавать', 'verb'),
      w('n1', 'cat', 'котик', 'noun'),
      w('n2', 'dog', 'собака', 'noun'),
      w('n3', 'sun', 'солнце', 'noun'),
    ];
    final d = builder.distractors(Exercise(target, ExerciseKind.choose), pool,
        n: 2);
    expect(d.toSet(), {'прыгать', 'плавать'},
        reason: 'при равной длине глаголы вытесняют существительные');
  });

  test('пиявка — карта с 8+ провалами', () {
    final c = WordCard(id: 'x', deckId: 'd', front: 'a', back: 'b');
    c.review.lapses = 7;
    expect(c.isLeech, false);
    c.review.lapses = 8;
    expect(c.isLeech, true);
  });

  group('Подача: срочность, лимиты, вкрапление', () {
    WordCard due(String id, {required double stability, required int daysAgo}) {
      final c = WordCard(id: id, deckId: 'd', front: 'f$id', back: 'b$id');
      c.review
        ..state = FsrsState.review
        ..stability = stability
        ..lastReview = now.subtract(Duration(days: daysAgo))
        ..due = now.subtract(const Duration(days: 1));
      return c;
    }

    test('повторы идут по срочности: слабее память → раньше', () {
      final a = due('a', stability: 2, daysAgo: 10); // низкая R — срочно
      final b = due('b', stability: 200, daysAgo: 1); // высокая R — не срочно
      final q =
          builder.build(StudyMode.flashcards, [b, a], now, newAllowed: 0);
      expect(q.map((e) => e.card.id).toList(), ['a', 'b']);
    });

    test('потолок повторов (maxReviews) ограничивает поток', () {
      final cards = [
        for (var i = 0; i < 10; i++) due('$i', stability: 5, daysAgo: 3),
      ];
      final q = builder.build(StudyMode.flashcards, cards, now,
          newAllowed: 0, maxReviews: 4);
      expect(q.length, 4);
    });

    test('лимит новых (newAllowed) ограничивает ввод новых', () {
      final cards = [for (var i = 0; i < 10; i++) _c('$i')];
      final q = builder.build(StudyMode.flashcards, cards, now,
          newAllowed: 3, maxReviews: 100);
      expect(q.length, 3);
    });

    test('новые вкраплены между повторами, а не свалены в конец', () {
      final reviews = [
        for (var i = 0; i < 4; i++) due('r$i', stability: 5, daysAgo: 3),
      ];
      final news = [_c('n0'), _c('n1')];
      final q = builder.build(StudyMode.flashcards, [...reviews, ...news], now,
          newAllowed: 2, maxReviews: 100);
      expect(q.length, 6);
      final newPositions = [
        for (var i = 0; i < q.length; i++)
          if (q[i].card.review.isNew) i,
      ];
      expect(newPositions.first < q.length - 2, true);
    });
  });
}

List<WordCard> _c8() => [for (var i = 10; i < 18; i++) _c('$i')];
