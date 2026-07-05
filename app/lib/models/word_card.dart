/// Оценка припоминания карточки. Свайп мапится на [again]/[good], четыре
/// кнопки дают полный контроль. Порядок = грейд FSRS 1..4.
enum Rating { again, hard, good, easy }

extension RatingGrade on Rating {
  /// Грейд FSRS: again=1 … easy=4.
  int get grade => index + 1;
}

/// Стадия карты по FSRS.
enum FsrsState { newCard, learning, review, relearning }

/// Фаза владения словом для адаптивного режима «Учить»
/// (unseen → recognize → produce → recall → mastered).
enum LearnPhase { unseen, recognize, produce, recall, mastered }

/// Состояние интервального повторения карточки по FSRS
/// (см. `models/fsrs.dart` и `docs/learning-system.md`).
class ReviewState {
  /// Стабильность памяти в днях (сколько держится до падения до целевого retention).
  double stability;

  /// Сложность карты 1..10.
  double difficulty;

  /// Стадия FSRS.
  FsrsState state;

  /// Число повторов всего.
  int reps;

  /// Сколько раз карту забыли (провал в стадии review).
  int lapses;

  /// Индекс learning/relearning-шага (для внутридневных шагов).
  int step;

  /// Когда карта снова «всплывёт». null — новая, ещё не показанная.
  DateTime? due;

  /// Момент последнего повтора.
  DateTime? lastReview;

  /// Фаза владения для режима «Учить».
  LearnPhase phase;

  ReviewState({
    this.stability = 0,
    this.difficulty = 0,
    this.state = FsrsState.newCard,
    this.reps = 0,
    this.lapses = 0,
    this.step = 0,
    this.due,
    this.lastReview,
    this.phase = LearnPhase.unseen,
  });

  /// Новая карта — ещё ни разу не оценённая.
  bool get isNew => state == FsrsState.newCard;

  ReviewState copy() => ReviewState(
        stability: stability,
        difficulty: difficulty,
        state: state,
        reps: reps,
        lapses: lapses,
        step: step,
        due: due,
        lastReview: lastReview,
        phase: phase,
      );

  Map<String, dynamic> toJson() => {
        's': stability,
        'd': difficulty,
        'state': state.index,
        'reps': reps,
        'lapses': lapses,
        'step': step,
        'due': due?.millisecondsSinceEpoch,
        'last': lastReview?.millisecondsSinceEpoch,
        'phase': phase.index,
      };

  factory ReviewState.fromJson(Map<String, dynamic> j) => ReviewState(
        stability: (j['s'] as num?)?.toDouble() ?? 0,
        difficulty: (j['d'] as num?)?.toDouble() ?? 0,
        state: FsrsState.values[(j['state'] as num?)?.toInt() ?? 0],
        reps: (j['reps'] as num?)?.toInt() ?? 0,
        lapses: (j['lapses'] as num?)?.toInt() ?? 0,
        step: (j['step'] as num?)?.toInt() ?? 0,
        due: _dt(j['due']),
        lastReview: _dt(j['last']),
        phase: LearnPhase.values[(j['phase'] as num?)?.toInt() ?? 0],
      );

  static DateTime? _dt(Object? v) =>
      v == null ? null : DateTime.fromMillisecondsSinceEpoch((v as num).toInt());
}

/// Карточка слова: перёд (изучаемое слово) → зад (перевод) + пример.
class WordCard {
  final String id;

  /// Колода, которой принадлежит карта. Изменяема — карту можно перенести
  /// (напр. при разбивке колоды по частям речи).
  String deckId;
  String front;
  String back;
  String example;
  ReviewState review;

  /// Часть речи (канонический код: noun/verb/adj/adv/pronoun/article/prep/
  /// conj/num/particle/interj), либо '' — неизвестно. Для разбивки по типам.
  String pos;

  /// Предложение-контекст из видео (для озвучки живым голосом целой реплики).
  String sentence;

  /// Ссылка на видео-источник (YouTube) — задел для живого голоса в повторах.
  String sourceUrl;

  /// Границы фрагмента аудио слова/предложения в источнике (мс), если известны.
  int? clipStartMs;
  int? clipEndMs;

  WordCard({
    required this.id,
    required this.deckId,
    required this.front,
    required this.back,
    this.example = '',
    ReviewState? review,
    this.sentence = '',
    this.sourceUrl = '',
    this.clipStartMs,
    this.clipEndMs,
    this.pos = '',
  }) : review = review ?? ReviewState();

  /// Карта «к повтору сейчас»: новая или наступил срок.
  bool isDue(DateTime now) => review.due == null || !review.due!.isAfter(now);

  Map<String, dynamic> toJson() => {
        'id': id,
        'deckId': deckId,
        'front': front,
        'back': back,
        'example': example,
        'review': review.toJson(),
        // Пишем видео-поля только когда заданы — чтобы не раздувать JSON карт,
        // созданных вручную (обратная совместимость гарантирована дефолтами).
        if (sentence.isNotEmpty) 'sentence': sentence,
        if (sourceUrl.isNotEmpty) 'src': sourceUrl,
        if (clipStartMs != null) 'cs': clipStartMs,
        if (clipEndMs != null) 'ce': clipEndMs,
        if (pos.isNotEmpty) 'pos': pos,
      };

  factory WordCard.fromJson(Map<String, dynamic> j) => WordCard(
        id: j['id'] as String,
        deckId: j['deckId'] as String,
        front: j['front'] as String? ?? '',
        back: j['back'] as String? ?? '',
        example: j['example'] as String? ?? '',
        review: j['review'] == null
            ? ReviewState()
            : ReviewState.fromJson(
                (j['review'] as Map).cast<String, dynamic>()),
        sentence: j['sentence'] as String? ?? '',
        sourceUrl: j['src'] as String? ?? '',
        clipStartMs: (j['cs'] as num?)?.toInt(),
        clipEndMs: (j['ce'] as num?)?.toInt(),
        pos: j['pos'] as String? ?? '',
      );
}

/// Стадия владения карточкой для списка слов (визуальный статус).
enum CardStatus { fresh, learning, young, mature }

extension WordCardStatus on WordCard {
  /// Классификация карты по её FSRS-состоянию для списка колоды.
  CardStatus get status {
    switch (review.state) {
      case FsrsState.newCard:
        return CardStatus.fresh;
      case FsrsState.learning:
      case FsrsState.relearning:
        return CardStatus.learning;
      case FsrsState.review:
        return review.stability >= 21 ? CardStatus.mature : CardStatus.young;
    }
  }
}

/// Человекочитаемая подпись длительности до следующего повтора.
String durationLabel(Duration d) {
  if (d.inMinutes < 1) return '<1 мин';
  if (d.inMinutes < 60) return '${d.inMinutes} мин';
  if (d.inHours < 24) return '${d.inHours} ч';
  final days = d.inHours ~/ 24;
  if (days < 30) return '$days дн';
  if (days < 365) return '${(days / 30).round()} мес';
  return '${(days / 365).round()} г';
}
