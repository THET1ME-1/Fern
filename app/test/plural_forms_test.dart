import 'package:flutter_test/flutter_test.dart';

import 'package:fern/l10n/locale_controller.dart';
import 'package:fern/l10n/strings.dart';
import 'package:fern/services/deck_repository.dart';

import 'test_helpers.dart';

/// Счётчики на плитках: «1 колода», а не «1 колод».
///
/// Число подставлялось в строку с существительным через `trf`, и на главном
/// экране книга с одной колодой подписывалась «1 колод» — первое, обо что
/// спотыкается глаз в магазине приложений.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await resetStorage();
    await DeckRepository.instance.init();
    await LocaleController.instance.setCode('ru');
  });

  group('колоды по-русски', () {
    test('одна', () => expect(trn('n_decks', 1), '1 колода'));
    test('две', () => expect(trn('n_decks', 2), '2 колоды'));
    test('пять', () => expect(trn('n_decks', 5), '5 колод'));
    test('одиннадцать — исключение', () => expect(trn('n_decks', 11), '11 колод'));
    test('двадцать одна', () => expect(trn('n_decks', 21), '21 колода'));
  });

  test('в английском две формы', () async {
    await LocaleController.instance.setCode('en');
    expect(trn('n_decks', 1), '1 deck');
    expect(trn('n_decks', 4), '4 decks');
  });
}
