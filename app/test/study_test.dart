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
      final q = builder.build(StudyMode.flashcards, cards, now, goal: 5);
      expect(q.length, 5);
      expect(q.every((e) => e.kind == ExerciseKind.flip), true);
    });

    test('write — упражнения на ввод', () {
      final q = builder.build(StudyMode.write, cards, now, goal: 6);
      expect(q.length, 6);
      expect(q.every((e) => e.kind == ExerciseKind.type), true);
    });

    test('test — фиксированное число, разные типы', () {
      final q = builder.build(StudyMode.test, cards, now, testCount: 6);
      expect(q.length, 6);
    });

    test('speed — выбор варианта при достаточном пуле', () {
      final q = builder.build(StudyMode.speed, cards, now, goal: 10);
      expect(q.isNotEmpty, true);
      expect(q.every((e) => e.kind == ExerciseKind.choose), true);
    });

    test('match — пустая очередь (отдельный экран-игра)', () {
      expect(builder.build(StudyMode.match, cards, now), isEmpty);
    });

    test('audio — упражнения на слух (listen)', () {
      final q = builder.build(StudyMode.audio, cards, now, goal: 6);
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
      final q = builder.build(StudyMode.learn, [recall, ..._c8()], now, goal: 20);
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

  test('дистракторы не содержат правильный ответ и берутся из пула', () {
    final cards = [for (var i = 0; i < 6; i++) _c('$i')];
    final ex = Exercise(cards.first, ExerciseKind.choose);
    final d = builder.distractors(ex, cards, n: 3);
    expect(d.length, 3);
    expect(d.contains(ex.answer), false);
  });
}

List<WordCard> _c8() => [for (var i = 10; i < 18; i++) _c('$i')];
