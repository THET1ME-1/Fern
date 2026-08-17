import '../l10n/strings.dart';

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

  /// Когда слово в последний раз попадалось при чтении (не повтор, а встреча
  /// в тексте). Нужен, чтобы одна книга не подкармливала карту бесконечно.
  DateTime? lastSeen;

  /// Срок этой карты приблизили из-за срыва соседа по смыслу (см.
  /// `services/link_propagation.dart`). Держим след, чтобы сессия могла честно
  /// сказать, почему слово всплыло раньше времени. Снимается при первом же
  /// повторе: карту спросили — повод исчерпан.
  bool nudgedByNeighbour;

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
    this.lastSeen,
    this.nudgedByNeighbour = false,
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
        lastSeen: lastSeen,
        nudgedByNeighbour: nudgedByNeighbour,
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
        if (lastSeen != null) 'seen': lastSeen!.millisecondsSinceEpoch,
        if (nudgedByNeighbour) 'nbr': true,
      };

  /// Разбор состояния из JSON.
  ///
  /// Значения приходят не только из своей базы: их несёт резервная копия и
  /// импорт чужой колоды, то есть файл, который могли испортить или собрать
  /// вручную. Номер состояния вне списка ронял разбор `RangeError`, а
  /// отрицательная прочность и сложность за шкалой расходились по формулам
  /// планировщика и выдавали карточке срок в другом веке.
  factory ReviewState.fromJson(Map<String, dynamic> j) => ReviewState(
        stability: _positive(j['s']),
        difficulty: _difficulty(j['d']),
        state: _enum(FsrsState.values, j['state']),
        reps: _count(j['reps']),
        lapses: _count(j['lapses']),
        step: _count(j['step']),
        due: _dt(j['due']),
        lastReview: _dt(j['last']),
        phase: _enum(LearnPhase.values, j['phase']),
        lastSeen: _dt(j['seen']),
        nudgedByNeighbour: j['nbr'] == true,
      );

  /// Неотрицательное конечное число (NaN и бесконечность — в ноль).
  static double _positive(Object? v) {
    final d = v is num ? v.toDouble() : 0.0;
    if (d.isNaN || !d.isFinite || d < 0) return 0;
    return d;
  }

  /// Сложность по шкале FSRS 1..10. Ноль оставляем: он значит «ещё не задана»
  /// у новой карточки.
  static double _difficulty(Object? v) {
    final d = _positive(v);
    return d > 10 ? 10 : d;
  }

  static int _count(Object? v) {
    final n = v is num ? v.toInt() : 0;
    return n < 0 ? 0 : n;
  }

  static T _enum<T>(List<T> values, Object? v) {
    final i = v is num ? v.toInt() : 0;
    return i >= 0 && i < values.length ? values[i] : values.first;
  }

  static DateTime? _dt(Object? v) =>
      v is num ? DateTime.fromMillisecondsSinceEpoch(v.toInt()) : null;
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

  /// Ответы, засчитанные вдобавок к [back]: второе значение слова («назад» для
  /// `back`), синоним, своя формулировка. Копятся по ходу занятий — сам человек
  /// или переводчик решают, что ответ верный, а карточка это запоминает и
  /// больше не спорит.
  List<String> accepted;

  /// Мнемоника-«крючок»: своя фраза-ассоциация, за которую цепляется память
  /// («под подушкой спрятана пила» для pillow). Пишется руками, показывается
  /// на обороте по кнопке и после срыва — там, где подсказка нужнее всего.
  String mnemonic;

  /// Имя файла картинки в каталоге [CardImages] (не полный путь: контейнер
  /// приложения меняется между установками). Пусто — картинки нет.
  String image;

  /// Связи с другими карточками, проставленные руками: id карты → код типа
  /// (`syn`/`ant`/`root`, см. `services/word_links.dart`). Вычисляемые связи
  /// (совпал перевод, общая основа) здесь НЕ хранятся — они считаются на лету.
  Map<String, String> links;

  /// Код грамматической конструкции, если это карточка ПРАВИЛА, а не слова
  /// (`present_perfect`, `passive_past`; см. `services/constructions.dart`).
  /// Пусто у обычных карточек. Правило живёт обычной карточкой намеренно: так
  /// ему достаются FSRS, сессии, статистика и резервная копия без единой
  /// правки в них.
  String rule;

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
    this.mnemonic = '',
    this.image = '',
    Map<String, String>? links,
    this.sentence = '',
    this.sourceUrl = '',
    this.clipStartMs,
    this.clipEndMs,
    this.pos = '',
    this.rule = '',
    List<String>? accepted,
  })  : review = review ?? ReviewState(),
        links = links ?? <String, String>{},
        accepted = accepted ?? <String>[];

  /// Карта «к повтору сейчас»: новая или наступил срок.
  bool isDue(DateTime now) => review.due == null || !review.due!.isAfter(now);

  /// Запоминает ответ как верный. Регистр и пробелы не создают нового варианта,
  /// сам перевод карточки в списке не нужен.
  void accept(String answer) {
    final t = answer.trim();
    if (t.isEmpty) return;
    final key = t.toLowerCase();
    if (key == back.trim().toLowerCase()) return;
    if (accepted.any((a) => a.toLowerCase() == key)) return;
    accepted.add(t);
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'deckId': deckId,
        'front': front,
        'back': back,
        'example': example,
        'review': review.toJson(),
        // Необязательные поля пишем, только когда заданы — чтобы не раздувать
        // JSON карт, созданных вручную (совместимость держат дефолты).
        if (mnemonic.isNotEmpty) 'mn': mnemonic,
        if (image.isNotEmpty) 'img': image,
        if (links.isNotEmpty) 'lnk': links,
        if (sentence.isNotEmpty) 'sentence': sentence,
        if (sourceUrl.isNotEmpty) 'src': sourceUrl,
        if (clipStartMs != null) 'cs': clipStartMs,
        if (clipEndMs != null) 'ce': clipEndMs,
        if (pos.isNotEmpty) 'pos': pos,
        if (rule.isNotEmpty) 'rule': rule,
        if (accepted.isNotEmpty) 'acc': accepted,
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
        mnemonic: j['mn'] as String? ?? '',
        image: j['img'] as String? ?? '',
        links: (j['lnk'] as Map?)?.map(
              (k, v) => MapEntry(k as String, v as String),
            ) ??
            <String, String>{},
        sentence: j['sentence'] as String? ?? '',
        sourceUrl: j['src'] as String? ?? '',
        clipStartMs: (j['cs'] as num?)?.toInt(),
        clipEndMs: (j['ce'] as num?)?.toInt(),
        pos: j['pos'] as String? ?? '',
        rule: j['rule'] as String? ?? '',
        accepted: (j['acc'] as List?)?.map((e) => e as String).toList(),
      );

  /// Карточка правила, а не слова.
  bool get isRule => rule.isNotEmpty;
}

/// Стадия владения карточкой для списка слов (визуальный статус).
enum CardStatus { fresh, learning, young, mature }

extension WordCardStatus on WordCard {
  /// «Пиявка» — карту забывали слишком много раз (порог как в Anki: 8 провалов).
  /// Такую стоит переформулировать / добавить пример или мнемонику.
  bool get isLeech => review.lapses >= 8;

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
///
/// Единицы идут через словарь: подписи стоят на кнопках оценки, и в английском
/// интерфейсе они показывались по-русски («10 мин», «16 дн»).
String durationLabel(Duration d) {
  if (d.inMinutes < 1) return tr('ivl_lt_min');
  if (d.inMinutes < 60) return trf('ivl_min', {'n': '${d.inMinutes}'});
  if (d.inHours < 24) return trf('ivl_hour', {'n': '${d.inHours}'});
  final days = d.inHours ~/ 24;
  if (days < 30) return trf('ivl_day', {'n': '$days'});
  if (days < 365) return trf('ivl_month', {'n': '${(days / 30).round()}'});
  return trf('ivl_year', {'n': '${(days / 365).round()}'});
}
