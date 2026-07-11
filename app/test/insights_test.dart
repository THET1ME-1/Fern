import 'package:flutter_test/flutter_test.dart';

import 'package:fern/models/review_event.dart';
import 'package:fern/models/word_card.dart';
import 'package:fern/services/article_import.dart';
import 'package:fern/services/study_insights.dart';

WordCard _card(String id,
        {required double stability,
        required int daysAgo,
        FsrsState state = FsrsState.review}) =>
    WordCard(
      id: id,
      deckId: 'd',
      front: id,
      back: id,
      review: ReviewState(
        stability: stability,
        state: state,
        lastReview: DateTime(2026, 7, 11, 12).subtract(Duration(days: daysAgo)),
      ),
    );

void main() {
  group('Слова под угрозой', () {
    final now = DateTime(2026, 7, 11, 12);

    test('давно не повторявшиеся с упавшей памятью — в списке', () {
      final cards = [
        _card('fresh', stability: 20, daysAgo: 1), // R высокий → нет
        _card('faded', stability: 5, daysAgo: 40), // R низкий → да
        _card('new', stability: 0, daysAgo: 0, state: FsrsState.newCard), // нет
      ];
      final ids = StudyInsights.atRisk(cards, now).map((r) => r.card.id);
      expect(ids, contains('faded'));
      expect(ids, isNot(contains('fresh')));
      expect(ids, isNot(contains('new')));
    });

    test('сортировка по возрастанию памяти (слабейшие первыми)', () {
      final risk = StudyInsights.atRisk([
        _card('a', stability: 5, daysAgo: 15),
        _card('b', stability: 5, daysAgo: 60),
      ], now);
      expect(risk.first.card.id, 'b'); // дольше не повторяли → память ниже
      expect(risk.first.retrievability, lessThan(risk.last.retrievability));
    });
  });

  group('Лучшее время учить', () {
    ReviewEvent ev(int hour) => ReviewEvent(
          cardId: 'c',
          ts: DateTime(2026, 7, 1, hour).millisecondsSinceEpoch,
          grade: 3,
          elapsedDays: 1,
          stateBefore: 2,
        );

    test('находит пиковый час', () {
      final events = [for (var i = 0; i < 40; i++) ev(20), ev(8), ev(8)];
      expect(StudyInsights.bestStudyHour(events), 20);
    });

    test('мало данных → null', () {
      expect(StudyInsights.bestStudyHour([ev(20), ev(20)]), isNull);
    });
  });

  group('Импорт статьи: парсинг HTML', () {
    test('заголовок og:title, чистый текст, предпочтение <article>', () {
      const html = '''
<html><head>
<meta property="og:title" content="Заголовок статьи">
<title>site — page</title>
<style>.x{color:red}</style>
</head><body>
<nav>меню мусор</nav>
<article><p>Первый абзац. Немного текста для длины строки.</p><p>Второй&nbsp;абзац. И ещё слов, чтобы пройти порог.</p></article>
<footer>подвал мусор</footer>
</body></html>''';
      final a = ArticleImport.parseForTest(html, 'https://example.com/x');
      final norm = a.text.replaceAll(RegExp(r'\s+'), ' ');
      expect(a.title, 'Заголовок статьи');
      expect(norm.contains('Первый абзац.'), true);
      expect(norm.contains('Второй абзац.'), true); // &nbsp; → обычный пробел
      expect(a.text.contains('мусор'), false); // nav/footer вырезаны
      expect(a.hasText, true);
    });

    test('firstUrl вытаскивает ссылку', () {
      expect(ArticleImport.firstUrl('читай тут https://a.b/c ok'),
          'https://a.b/c');
      expect(ArticleImport.firstUrl('без ссылки'), isNull);
    });
  });
}
