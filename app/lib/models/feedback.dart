/// Обращение из приложения: виды, правила формы и итог отправки.
///
/// Google Play требует, чтобы о проблеме можно было сообщить, не выходя из
/// приложения (Togetherly отклонили за это 11.11.2026). Форма —
/// `lib/feedback_screen.dart`, сервер — `server/pb_hooks/fern_feedback.pb.js`.
library;

/// Вид обращения. [wire] — как он называется в запросе; те же ключи ждёт
/// `fern_feedback_mail.js`, совпадение стережёт его тест.
enum FeedbackKind {
  bug('bug'),
  idea('idea'),
  payment('payment'),
  other('other');

  const FeedbackKind(this.wire);
  final String wire;
}

/// Короче сервер не примет: это случайное нажатие, а не обращение.
const int kFeedbackMin = 10;

/// Потолок текста — тот же, что на сервере.
const int kFeedbackMax = 4000;

/// Можно ли отправлять такой текст.
bool feedbackReady(String text) {
  final length = text.trim().length;
  return length >= kFeedbackMin && length <= kFeedbackMax;
}

/// Что уходит на сервер.
class FeedbackDraft {
  const FeedbackDraft({
    required this.kind,
    required this.text,
    required this.email,
    required this.app,
    required this.platform,
    required this.lang,
  });

  final FeedbackKind kind;
  final String text;

  /// Почта для ответа; пустая — человек её не оставил.
  final String email;
  final String app;
  final String platform;
  final String lang;

  Map<String, String> toJson() => {
        'kind': kind.wire,
        'text': text,
        'email': email,
        'app': app,
        'platform': platform,
        'lang': lang,
      };
}

/// Чем кончилась отправка.
enum FeedbackSent {
  ok,

  /// Дневной предел обращений с одного адреса.
  tooMany,

  /// Сервер не принял адрес почты.
  badEmail,

  /// Нет связи или сервер не принял: текст остаётся в форме.
  failed,
}

/// Итог по коду ответа и коду ошибки сервера; null — ответа не было.
FeedbackSent feedbackSentOf(int? statusCode, [String? error]) =>
    switch (statusCode) {
      200 => FeedbackSent.ok,
      429 => FeedbackSent.tooMany,
      400 when error == 'bad_email' => FeedbackSent.badEmail,
      _ => FeedbackSent.failed,
    };
