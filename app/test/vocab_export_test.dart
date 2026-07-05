import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:fern/models/word_card.dart';
import 'package:fern/services/vocab_export.dart';

void main() {
  final cards = [
    WordCard(id: '1', deckId: 'd', front: 'cat', back: 'кот', example: 'A cat.'),
    WordCard(id: '2', deckId: 'd', front: 'hi, there', back: 'привет'),
    WordCard(id: '3', deckId: 'd', front: 'cat', back: 'дубль'),
  ];

  test('CSV: заголовок + экранирование запятых', () {
    final csv = VocabExport.build(VocabFormat.csv, cards);
    final lines = csv.trim().split('\n');
    expect(lines.first, 'front,back,example');
    expect(csv.contains('"hi, there"'), isTrue); // запятая → кавычки
  });

  test('Anki TSV: табы, без заголовка', () {
    final tsv = VocabExport.build(VocabFormat.ankiTsv, cards);
    expect(tsv.contains('front\tback'), isFalse); // нет заголовка
    expect(tsv.split('\n').first, 'cat\tкот\tA cat.');
  });

  test('JSON: валидный массив объектов', () {
    final json = VocabExport.build(VocabFormat.json, cards);
    final data = jsonDecode(json) as List;
    expect(data.length, 3);
    expect((data.first as Map)['front'], 'cat');
  });

  test('Список слов: уникальные', () {
    final list = VocabExport.build(VocabFormat.list, cards).trim().split('\n');
    expect(list, ['cat', 'hi, there']); // «cat» не дублируется
  });
}
