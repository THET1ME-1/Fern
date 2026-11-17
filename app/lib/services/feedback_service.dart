import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:pocketbase/pocketbase.dart';

import '../models/feedback.dart';
import 'fern_account.dart';

/// Отправка обращения на свой сервер. Из приложения человек при этом не
/// выходит: ни почтовой программы, ни браузера (требование Google Play).
///
/// Идёт тем же клиентом, что и аккаунт: если человек вошёл, обращение
/// подписано его сессией, и сервер сам возьмёт почту для ответа.
class FeedbackService {
  const FeedbackService();

  Future<FeedbackSent> send(FeedbackDraft draft) async {
    try {
      await FernAccount.instance.init();
      await FernAccount.instance.pb
          .send('/api/fern/feedback', method: 'POST', body: draft.toJson())
          .timeout(const Duration(seconds: 20));
      return FeedbackSent.ok;
    } on ClientException catch (e) {
      debugPrint('Feedback.send отказ: ${e.statusCode}');
      final error = e.response['error'];
      return feedbackSentOf(e.statusCode, error is String ? error : null);
    } catch (e) {
      debugPrint('Feedback.send не ушло: $e');
      return FeedbackSent.failed;
    }
  }
}
