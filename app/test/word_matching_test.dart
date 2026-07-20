import 'package:flutter_test/flutter_test.dart';

import 'package:fern/models/word_card.dart';
import 'package:fern/services/lemmatizer.dart';
import 'package:fern/services/reading_horizon.dart';
import 'package:fern/services/word_links.dart';

WordCard _card(String id, String front, String back) =>
    WordCard(id: id, deckId: 'd1', front: front, back: back);

void main() {
  group('русский творительный падеж третьего склонения', () {
    // Сверка карточки с текстом книги держится на совпадении основ. В списке
    // окончаний было одиночное «ю», но не «ью»: «дверь» стеммилось в «двер», а
    // «дверью» — в «дверь». Это все существительные женского рода на мягкий
    // знак, а не редкое исключение.
    test('основа формы совпадает с основой словарной записи', () {
      for (final pair in [
        ('дверь', 'дверью'),
        ('ночь', 'ночью'),
        ('мышь', 'мышью'),
        ('любовь', 'любовью'),
        ('жизнь', 'жизнью'),
      ]) {
        expect(Lemmatizer.stem(pair.$2, 'ru'), Lemmatizer.stem(pair.$1, 'ru'),
            reason: '${pair.$2} должно опознаваться как ${pair.$1}');
      }
    });

    test('прежние пары не сломались', () {
      expect(Lemmatizer.stem('слова', 'ru'), Lemmatizer.stem('слово', 'ru'));
      expect(Lemmatizer.stem('коты', 'ru'), Lemmatizer.stem('кот', 'ru'));
      expect(Lemmatizer.stem('столом', 'ru'), Lemmatizer.stem('стол', 'ru'));
    });
  });

  group('типографский апостроф', () {
    test('слово не разваливается надвое', () {
      // В вычитанных EPUB сокращения набраны знаком ’ (U+2019), а не '.
      // Регулярка знала только прямой апостроф, поэтому don’t давало два
      // токена: don и t. Обрубок can (из can’t) — частое слово, и карточка
      // «can» ложно считалась «скоро встретится в книге».
      final words = ReadingHorizon.debugWords('I don’t like it, can’t stay');
      expect(words, contains('don’t'));
      expect(words, contains('can’t'));
      expect(words, isNot(contains('t')));
    });

    test('прямой апостроф работает по-прежнему', () {
      expect(ReadingHorizon.debugWords("don't stop"), contains("don't"));
    });
  });

  group('однокоренные слова', () {
    test('случайное совпадение начала не делает слова родственными', () {
      // Общий префикс от четырёх букв и хвост в 2-6 букв — слишком слабое
      // правило. Связь root входит в spreadingKinds: сорвался на «restaurant»
      // — и карточка «rest» без причины просится к повтору раньше срока.
      for (final pair in [
        ('rest', 'restaurant'),
        ('cost', 'costume'),
        ('fort', 'fortune'),
      ]) {
        final a = _card('a', pair.$1, 'перевод-1');
        final b = _card('b', pair.$2, 'перевод-2');
        final links = WordLinks.auto(a, [b], 'en');
        expect(links.where((l) => l.kind == LinkKind.root), isEmpty,
            reason: '${pair.$1} и ${pair.$2} — разные слова');
      }
    });

    test('настоящие однокоренные по-прежнему связываются', () {
      final teach = _card('a', 'teach', 'учить');
      final teacher = _card('b', 'teacher', 'учитель');
      final links = WordLinks.auto(teach, [teacher], 'en');
      expect(links.where((l) => l.kind == LinkKind.root), isNotEmpty);
    });
  });
}
