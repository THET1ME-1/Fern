import 'package:flutter_test/flutter_test.dart';

import 'package:fern/models/word_card.dart';
import 'package:fern/services/word_links.dart';

WordCard _c(String id, String front, String back, {String pos = ''}) =>
    WordCard(id: id, deckId: 'd1', front: front, back: back, pos: pos);

void main() {
  group('Вычисленные связи', () {
    test('совпал перевод — синонимы', () {
      final bright = _c('c1', 'bright', 'яркий');
      final pool = [bright, _c('c2', 'shiny', 'яркий'), _c('c3', 'dark', 'тёмный')];

      final links = WordLinks.auto(bright, pool, 'en');
      expect(links.length, 1);
      expect(links.single.card.front, 'shiny');
      expect(links.single.kind, LinkKind.synonym);
      expect(links.single.auto, true);
    });

    test('общая основа — однокоренные', () {
      final cat = _c('c1', 'cats', 'коты');
      final pool = [cat, _c('c2', 'cat', 'кот')];

      final links = WordLinks.auto(cat, pool, 'en');
      expect(links.single.card.front, 'cat');
      expect(links.single.kind, LinkKind.root);
    });

    test('словообразование тоже даёт однокоренные', () {
      final bright = _c('c1', 'bright', 'яркий');
      final pool = [bright, _c('c2', 'brightness', 'яркость')];
      expect(WordLinks.auto(bright, pool, 'en').single.kind, LinkKind.root);
    });

    test('похожие по началу, но чужие слова не связываются', () {
      final boot = _c('c1', 'boot', 'ботинок');
      final pool = [
        boot,
        _c('c2', 'booth', 'будка'), // хвост в один символ
        _c('c3', 'bootstrapping', 'раскрутка'), // хвост длиннее шести
      ];
      expect(WordLinks.auto(boot, pool, 'en'), isEmpty);
    });

    test('карточка не связывается сама с собой', () {
      final card = _c('c1', 'bright', 'яркий');
      expect(WordLinks.auto(card, [card], 'en'), isEmpty);
    });

    test('ручная связь вытесняет вычисленную', () {
      final bright = _c('c1', 'bright', 'яркий');
      final shiny = _c('c2', 'shiny', 'яркий');
      WordLinks.connect(bright, shiny, LinkKind.antonym);

      final auto = WordLinks.auto(bright, [bright, shiny], 'en');
      expect(auto, isEmpty, reason: 'ручная связь важнее угаданной');

      final all = WordLinks.all(bright, [bright, shiny], 'en');
      expect(all.single.kind, LinkKind.antonym);
      expect(all.single.auto, false);
    });
  });

  group('Ручные связи', () {
    test('связь ставится и снимается с обеих сторон', () {
      final a = _c('c1', 'bright', 'яркий');
      final b = _c('c2', 'dark', 'тёмный');

      WordLinks.connect(a, b, LinkKind.antonym);
      expect(a.links['c2'], 'ant');
      expect(b.links['c1'], 'ant');

      WordLinks.disconnect(a, b);
      expect(a.links, isEmpty);
      expect(b.links, isEmpty);
    });

    test('переживают сериализацию карточки', () {
      final a = _c('c1', 'bright', 'яркий');
      final b = _c('c2', 'dark', 'тёмный');
      WordLinks.connect(a, b, LinkKind.antonym);

      final restored = WordCard.fromJson(a.toJson());
      expect(restored.links, {'c2': 'ant'});
    });

    test('связи на удалённые карточки не показываются', () {
      final a = _c('c1', 'bright', 'яркий');
      a.links['ghost'] = 'syn';
      expect(WordLinks.manual(a, [a]), isEmpty);
    });
  });

  test('группировка складывает связи по типу', () {
    final bright = _c('c1', 'bright', 'яркий');
    final dark = _c('c2', 'dark', 'тёмный');
    final shiny = _c('c3', 'shiny', 'яркий');
    final brightness = _c('c4', 'brightness', 'яркость');
    WordLinks.connect(bright, dark, LinkKind.antonym);

    final grouped =
        WordLinks.grouped(bright, [bright, dark, shiny, brightness], 'en');

    expect(grouped[LinkKind.antonym]!.single.card.front, 'dark');
    expect(grouped[LinkKind.synonym]!.single.card.front, 'shiny');
    expect(grouped[LinkKind.root]!.single.card.front, 'brightness');
  });
}
