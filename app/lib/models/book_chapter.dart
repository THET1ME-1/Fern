/// Глава книги: название и индекс абзаца, с которого она начинается (в том же
/// разбиении на абзацы, что и читалка — `text.split('\n')` без пустых строк).
class BookChapter {
  final String title;
  final int startParagraph;

  const BookChapter(this.title, this.startParagraph);

  Map<String, dynamic> toJson() => {'t': title, 'p': startParagraph};

  factory BookChapter.fromJson(Map<String, dynamic> j) => BookChapter(
        (j['t'] as String?) ?? '',
        (j['p'] as num?)?.toInt() ?? 0,
      );
}
