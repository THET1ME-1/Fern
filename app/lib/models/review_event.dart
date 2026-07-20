/// Сырое событие повтора — одна оценка одной карты. В отличие от агрегата по
/// дням ([ReviewLog]), хранит достаточно, чтобы ПОЗЖЕ обучить персональные веса
/// FSRS по истории (реконструировать кривую забывания конкретного пользователя).
///
/// Пишется в таблицу `review_events` при каждой оценке (см. [DeckRepository]).
class ReviewEvent {
  final String cardId;

  /// Момент оценки (мс от эпохи).
  final int ts;

  /// Грейд FSRS: again=1 … easy=4.
  final int grade;

  /// Сколько дней прошло с прошлого повтора этой карты (0 для первого показа).
  final double elapsedDays;

  /// Стадия FSRS ДО этой оценки (индекс [FsrsState]) — чтобы отличить первый
  /// показ (newCard) от последующих.
  final int stateBefore;

  /// Сколько миллисекунд заняло ответить (от показа вопроса до оценки).
  /// `null` — время неизвестно (таймаут игры, оценка не из сессии). Пустое
  /// значение честнее нуля: ноль читался бы как «ответил мгновенно».
  final int? answerMs;

  const ReviewEvent({
    required this.cardId,
    required this.ts,
    required this.grade,
    required this.elapsedDays,
    required this.stateBefore,
    this.answerMs,
  });

  /// Ответ засчитан как «вспомнил» (всё, кроме «Не помню»).
  bool get recalled => grade > 1;
}
