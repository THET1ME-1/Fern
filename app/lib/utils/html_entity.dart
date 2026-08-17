/// Числовые HTML-сущности (`&#1055;`, `&#x43;`) из ЧУЖИХ источников: страницы
/// в интернете, EPUB, FB2, наборы Anki.
///
/// Номер там ничем не гарантирован, а обе стандартные функции на кривом номере
/// падают: `int.parse` — на числе длиннее 64 бит, `String.fromCharCode` — на
/// номере за границей Юникода. Отдельно отсекается одинокий суррогат
/// (U+D800…U+DFFF): строку с ним не примут ни SQLite, ни `jsonEncode`, и
/// разобранный текст не сохранился бы целиком.
library;

/// Символ по номеру сущности или `null`, если номер негодный.
String? decodeNumericEntity(String digits, {int radix = 10}) {
  final code = int.tryParse(digits, radix: radix);
  if (code == null ||
      code < 0 ||
      code > 0x10FFFF ||
      (code >= 0xD800 && code <= 0xDFFF)) {
    return null;
  }
  return String.fromCharCode(code);
}

/// Разворачивает `&#N;` и `&#xN;` в тексте. Негодные записи заменяются на
/// [fallback] (по умолчанию — знак замены Юникода).
String decodeNumericEntities(String s, {String fallback = '�'}) => s
    .replaceAllMapped(RegExp(r'&#(\d+);'),
        (m) => decodeNumericEntity(m.group(1)!) ?? fallback)
    .replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'),
        (m) => decodeNumericEntity(m.group(1)!, radix: 16) ?? fallback);
