import 'package:flutter_test/flutter_test.dart';

import 'package:fern/models/word_card.dart';
import 'package:fern/services/answer_check.dart';
import 'package:fern/services/auto_grade.dart';
import 'package:fern/study/study_models.dart';

/// Второе значение слова.
///
/// Жалоба тестера: `back` в наборе переведён как «спина», и ответ «назад»
/// считался ошибкой. Так же `hundred` → «сто» против «сотня». Держать все
/// значения в наборе нельзя: слова приходят ещё и из книг, на 55 языках.
/// Поэтому судят трое по очереди: точное совпадение, ранее засчитанные
/// варианты карточки и переводчик.
void main() {
  group('засчитанные варианты карточки', () {
    test('вариант, засчитанный однажды, принимается сразу', () {
      final card = WordCard(id: '1', deckId: 'd', front: 'back', back: 'спина');
      expect(typedQuality('назад', card.back, also: card.accepted),
          TypedMatch.wrong);

      card.accept('назад');
      expect(typedQuality('назад', card.back, also: card.accepted),
          TypedMatch.exact);
    });

    test('описка в засчитанном варианте — тоже описка, а не промах', () {
      final card = WordCard(id: '1', deckId: 'd', front: 'back', back: 'спина');
      card.accept('назад');
      expect(typedQuality('нозад', card.back, also: card.accepted),
          TypedMatch.typo);
    });

    test('вариант не задваивается и не пишется пустым', () {
      final card = WordCard(id: '1', deckId: 'd', front: 'back', back: 'спина');
      card.accept('назад');
      card.accept('  Назад ');
      card.accept('');
      card.accept('спина');
      expect(card.accepted, ['назад'],
          reason: 'регистр и пробелы не создают нового варианта, '
              'а сам перевод карточки в списке не нужен');
    });

    test('варианты переживают запись на диск', () {
      final card = WordCard(id: '1', deckId: 'd', front: 'back', back: 'спина')
        ..accept('назад');
      final back = WordCard.fromJson(card.toJson());
      expect(back.accepted, ['назад']);

      final plain = WordCard(id: '2', deckId: 'd', front: 'cat', back: 'кот');
      expect(plain.toJson().containsKey('acc'), isFalse,
          reason: 'пустое поле не раздувает JSON словаря');
    });
  });

  group('направление упражнения', () {
    test('засчитанные варианты работают только в прямом направлении', () {
      final card = WordCard(id: '1', deckId: 'd', front: 'back', back: 'спина')
        ..accept('назад');

      final forward = Exercise(card, ExerciseKind.type);
      expect(forward.acceptedVariants, ['назад']);

      // Обратное упражнение ждёт термин `back`. «Назад» — перевод, и без
      // этого гейта typedQuality засчитал бы русское слово за английское.
      final reversed = Exercise(card, ExerciseKind.type, reversed: true);
      expect(reversed.acceptedVariants, isEmpty);
      expect(
        typedQuality('назад', reversed.answer, also: reversed.acceptedVariants),
        TypedMatch.wrong,
      );
    });
  });

  group('сверка переводчиком', () {
    test('обратный перевод совпал с ожидаемым — ответ верный', () async {
      final ok = await AnswerCheck.meansTheSame(
        typed: 'назад',
        typedLang: 'ru',
        source: 'back',
        sourceLang: 'en',
        translate: (text, from, to) async {
          expect(text, 'назад');
          expect(from, 'ru');
          expect(to, 'en');
          return const ['back'];
        },
      );
      expect(ok, isTrue);
    });

    test('сверка идёт по основе слова: формы совпадают', () async {
      final ok = await AnswerCheck.meansTheSame(
        typed: 'сотня',
        typedLang: 'ru',
        source: 'hundred',
        sourceLang: 'en',
        translate: (_, _, _) async => const ['hundreds'],
      );
      expect(ok, isTrue);
    });

    test('чужое слово остаётся ошибкой', () async {
      final ok = await AnswerCheck.meansTheSame(
        typed: 'кот',
        typedLang: 'ru',
        source: 'back',
        sourceLang: 'en',
        translate: (_, _, _) async => const ['cat'],
      );
      expect(ok, isFalse);
    });

    test('переводчик молчит — решение не выдумываем', () async {
      final ok = await AnswerCheck.meansTheSame(
        typed: 'назад',
        typedLang: 'ru',
        source: 'back',
        sourceLang: 'en',
        translate: (_, _, _) async => const [],
      );
      expect(ok, isFalse);
    });

    test('долгий ответ не держит занятие', () async {
      final ok = await AnswerCheck.meansTheSame(
        typed: 'назад',
        typedLang: 'ru',
        source: 'back',
        sourceLang: 'en',
        timeout: const Duration(milliseconds: 50),
        translate: (_, _, _) async {
          await Future<void>.delayed(const Duration(seconds: 5));
          return const ['back'];
        },
      );
      expect(ok, isFalse);
    });

    test('одинаковые языки сверять нечем', () async {
      var called = false;
      final ok = await AnswerCheck.meansTheSame(
        typed: 'назад',
        typedLang: 'ru',
        source: 'спина',
        sourceLang: 'ru',
        translate: (_, _, _) async {
          called = true;
          return const ['спина'];
        },
      );
      expect(ok, isFalse);
      expect(called, isFalse);
    });
  });
}
