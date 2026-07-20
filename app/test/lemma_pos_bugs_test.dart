import 'package:flutter_test/flutter_test.dart';
import 'package:fern/services/lemmatizer.dart';
import 'package:fern/services/pos.dart';

/// Сверка слова из книги с карточкой держится на одном: основа слова в тексте
/// и основа «переда» карточки должны совпадать. Где они расходятся, там
/// карточка не опознаётся в книге — не подсвечивается, не попадает в разминку,
/// не получает метку «встретится дальше».
void main() {
  group('Лемматизатор: форма и словарная запись дают одну основу', () {
    test('falling и fall', () {
      expect(Lemmatizer.stem('falling', 'en'), Lemmatizer.stem('fall', 'en'));
    });

    test('spelling и spell', () {
      expect(Lemmatizer.stem('spelling', 'en'), Lemmatizer.stem('spell', 'en'));
    });

    test('adding и add', () {
      expect(Lemmatizer.stem('adding', 'en'), Lemmatizer.stem('add', 'en'));
    });

    test('running и run — удвоение тут настоящее', () {
      expect(Lemmatizer.stem('running', 'en'), Lemmatizer.stem('run', 'en'));
    });

    test('goes и go', () {
      expect(Lemmatizer.stem('goes', 'en'), Lemmatizer.stem('go', 'en'));
    });

    test('столом и стол', () {
      expect(Lemmatizer.stem('столом', 'ru'), Lemmatizer.stem('стол', 'ru'));
    });

    test('форум и форума — «ум» не окончание', () {
      expect(Lemmatizer.stem('форума', 'ru'), Lemmatizer.stem('форум', 'ru'));
    });
  });

  group('Часть речи из словаря', () {
    test('местоимение не превращается в существительное', () {
      expect(PosDetect.fromDictionary('pronoun'), 'pronoun');
    });

    test('частица не превращается в артикль', () {
      expect(PosDetect.fromDictionary('particle'), 'particle');
    });

    test('существительное остаётся собой', () {
      expect(PosDetect.fromDictionary('noun'), 'noun');
    });

    test('артикль остаётся собой', () {
      expect(PosDetect.fromDictionary('article'), 'article');
    });
  });
}
