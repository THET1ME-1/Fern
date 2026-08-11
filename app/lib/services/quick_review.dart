import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/word_card.dart';
import 'deck_repository.dart';

/// Ответ, данный прямо из шторки уведомлений.
class QuickAnswer {
  final String cardId;

  /// true — «помню», false — «не помню».
  final bool recalled;

  /// Когда ответили (миллисекунды эпохи).
  final int at;

  const QuickAnswer(this.cardId, this.recalled, this.at);

  Map<String, dynamic> toJson() =>
      {'id': cardId, 'ok': recalled, 'at': at};

  factory QuickAnswer.fromJson(Map<String, dynamic> j) => QuickAnswer(
        j['id'] as String,
        j['ok'] == true,
        (j['at'] as num?)?.toInt() ?? 0,
      );
}

/// Микроповтор из шторки: карточка приходит уведомлением с двумя кнопками, и
/// ответ засчитывается без открытия приложения.
///
/// Почему очередь, а не запись сразу: кнопку обрабатывает ФОНОВЫЙ изолят, у
/// которого нет ни живого репозитория, ни открытого соединения с базой. Вторая
/// запись в тот же файл SQLite из другого изолята — верный способ получить
/// «database is locked» и потерять словарь. Ответ кладётся в очередь
/// (`SharedPreferences`), а применяет его приложение при первом запуске.
class QuickReview {
  const QuickReview._();

  static const String _queueKey = 'quickReviewQueue';

  /// Идентификаторы действий уведомления (сверяются в фоновом обработчике).
  static const String actionKnow = 'quick_know';
  static const String actionForgot = 'quick_forgot';

  /// Кладёт ответ в очередь. Зовётся из ФОНОВОГО изолята, поэтому берёт
  /// обычный `SharedPreferences`: у него есть синхронное чтение кэша, и он
  /// доступен без инициализации остальных сервисов приложения.
  static Future<void> enqueue(String cardId, bool recalled) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList(_queueKey) ?? <String>[];
      raw.add(jsonEncode(
        QuickAnswer(cardId, recalled, DateTime.now().millisecondsSinceEpoch)
            .toJson(),
      ));
      await prefs.setStringList(_queueKey, raw);
    } catch (e) {
      debugPrint('QuickReview.enqueue: $e');
    }
  }

  /// Забирает накопленные ответы и очищает очередь.
  static Future<List<QuickAnswer>> drain() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final raw = prefs.getStringList(_queueKey) ?? const <String>[];
      if (raw.isEmpty) return const [];
      await prefs.remove(_queueKey);
      return [
        for (final line in raw)
          QuickAnswer.fromJson(
            (jsonDecode(line) as Map).cast<String, dynamic>(),
          ),
      ];
    } catch (e) {
      debugPrint('QuickReview.drain: $e');
      return const [];
    }
  }

  /// Применяет накопленные ответы к карточкам. Возвращает, сколько применилось.
  ///
  /// Оценка нарочно грубая: из шторки человек отвечает «помню/не помню», и
  /// выдавать за это «легко» нельзя — время ответа там не измеряется, а сам
  /// ответ дан между делом.
  static Future<int> applyPending() async {
    final pending = await drain();
    if (pending.isEmpty) return 0;
    final repo = DeckRepository.instance;
    final cards = await repo.loadCards();
    final byId = {for (final c in cards) c.id: c};
    var applied = 0;
    for (final answer in pending) {
      final card = byId[answer.cardId];
      if (card == null) continue;
      await repo.rateCard(
        card,
        answer.recalled ? Rating.good : Rating.again,
        DateTime.fromMillisecondsSinceEpoch(answer.at),
      );
      applied++;
    }
    return applied;
  }
}

