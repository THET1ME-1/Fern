import 'package:flutter/foundation.dart';

import '../study/study_models.dart';
import 'lemmatizer.dart';
import 'translation/translation_manager.dart';

/// Переводит [text] с [from] на [to] и отдаёт все значения, какие знает.
/// Отдельным типом, чтобы сверку можно было проверить без движка перевода.
typedef Translate = Future<List<String>> Function(
  String text,
  String from,
  String to,
);

/// Ответ не совпал с переводом на карточке — но значит ли он то же самое?
///
/// У слова редко одно значение: `back` это и «спина», и «назад», `hundred` —
/// «сто» и «сотня». Держать все значения в наборе нельзя: слова приходят ещё и
/// из книг, а языков пятьдесят пять. Поэтому спрашиваем тот переводчик, который
/// человек выбрал в настройках: переводим ОТВЕТ обратно на язык карточки и
/// смотрим, не получилось ли слово с карточки.
class AnswerCheck {
  const AnswerCheck._();

  /// Сколько ждём переводчик. Занятие — быстрый ритм: лучше честное «неверно» с
  /// кнопкой «засчитать», чем застывший экран.
  static const Duration defaultTimeout = Duration(seconds: 4);

  /// Значит ли [typed] то же, что слово [source] на карточке.
  ///
  /// [typed] — что набрал человек, на языке [typedLang]; [source] — слово, о
  /// котором спрашивали, на языке [sourceLang]. В обратном упражнении («напиши
  /// слово») стороны меняются местами, и проверка работает так же.
  static Future<bool> meansTheSame({
    required String typed,
    required String typedLang,
    required String source,
    required String sourceLang,
    Translate? translate,
    Duration timeout = defaultTimeout,
  }) async {
    final answer = typed.trim();
    final word = source.trim();
    if (answer.isEmpty || word.isEmpty) return false;
    // Языки совпали — переводить нечего, и обратный перевод вернул бы то же
    // самое слово, засчитав любой ответ.
    if (typedLang == sourceLang) return false;

    try {
      final options = await (translate ?? _viaChosenProvider)(
        answer,
        typedLang,
        sourceLang,
      ).timeout(timeout);
      return options.any((o) => _sameWord(o, word, sourceLang));
    } catch (e) {
      debugPrint('AnswerCheck failed: $e');
      return false;
    }
  }

  /// Перевод тем движком, который выбран в настройках, — и ТОЛЬКО им.
  ///
  /// Не `manager.translate`: тот при сбое уходит по fallback-цепочке в
  /// онлайн-Google, а человек, выбравший офлайн-движок, не ждёт, что его
  /// ответы поедут в сеть. Готовность проверяем заранее: у ML Kit «неготов»
  /// значит «модель не скачана», а тянуть тридцать мегабайт посреди занятия
  /// нельзя.
  static Future<List<String>> _viaChosenProvider(
    String text,
    String from,
    String to,
  ) async {
    final active = TranslationManager.instance.active;
    if (!active.supportsPair(from, to)) return const [];
    if (!await active.isReady(from, to)) return const [];
    final res = await active.translate(text, from, to);
    return res?.options ?? const [];
  }

  /// Одно ли это слово с точностью до формы.
  ///
  /// Машинный перевод отдаёт словарную форму не всегда: «сотня» уходит в
  /// `hundreds`. Сверяем основы — тем же лемматизатором, которым карточка
  /// узнаётся в тексте книги.
  static bool _sameWord(String a, String b, String lang) {
    final na = normalizeAnswer(a);
    final nb = normalizeAnswer(b);
    if (na.isEmpty || nb.isEmpty) return false;
    if (na == nb) return true;
    if (na.contains(' ') || nb.contains(' ')) return false;
    final sa = Lemmatizer.stem(na, lang);
    final sb = Lemmatizer.stem(nb, lang);
    return sa.isNotEmpty && sa == sb;
  }
}
