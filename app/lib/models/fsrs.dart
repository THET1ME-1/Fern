import 'dart:math' as math;

import '../utils/day.dart';
import 'word_card.dart';

/// FSRS — Free Spaced Repetition Scheduler (актуальный стандарт, точнее SM-2).
///
/// Реализация с дефолтными весами FSRS-5 (`w[0..18]`). Считаем стабильность
/// памяти `S`, сложность `D`, извлекаемость `R` и из них — следующий интервал.
/// Персональная оптимизация весов по истории — отдельный (поздний) шаг; логи
/// уже можно копить в `ReviewLog`. См. `docs/learning-system.md` §3.
class Fsrs {
  Fsrs._();
  static final Fsrs instance = Fsrs._();

  /// Отдельный экземпляр для прогона истории «а что было бы, если»
  /// (см. `services/schedule_lab.dart`). Синглтон для этого не годится:
  /// симуляция не должна трогать веса, по которым живёт настоящее расписание.
  factory Fsrs.forSimulation({
    List<double>? weights,
    double retention = 0.9,
  }) {
    final f = Fsrs._();
    f.setWeights(weights);
    f.requestRetention = retention;
    return f;
  }

  /// Дефолтные веса FSRS-5.
  static const List<double> defaultWeights = [
    0.40255, 1.18385, 3.173, 15.69105, 7.1949, 0.5345, 1.4604, 0.0046,
    1.54575, 0.1192, 1.01925, 1.9395, 0.11, 0.29605, 2.2698, 0.2315,
    2.9898, 0.51655, 0.6621,
  ];

  /// Текущие веса (по умолчанию — [defaultWeights]; могут быть заменены
  /// персональными через [setWeights]).
  List<double> w = List<double>.of(defaultWeights);

  /// Ставит персональные веса (или сбрасывает на дефолтные при null). Принимает
  /// только корректный набор из 19 значений; каждое — в разумных границах, чтобы
  /// кривой оптимизатор не сломал планирование.
  void setWeights(List<double>? weights) {
    if (weights == null || weights.length != defaultWeights.length) {
      w = List<double>.of(defaultWeights);
      return;
    }
    w = [
      for (final v in weights)
        v.isFinite ? v.clamp(-1.0, 100.0).toDouble() : 0.0,
    ];
  }

  /// Целевой уровень удержания (вероятность вспомнить на момент повтора).
  double requestRetention = 0.9;

  /// Максимальный интервал в днях.
  int maximumInterval = 36500;

  static const double _decay = -0.5;
  static const double _factor = 19.0 / 81.0; // 0.9^(1/decay) − 1

  /// Внутридневные шаги для новых/переучиваемых карт.
  static const List<Duration> learningSteps = [
    Duration(minutes: 1),
    Duration(minutes: 10),
  ];
  static const List<Duration> relearningSteps = [Duration(minutes: 10)];

  // ------------------------------- Формулы -------------------------------

  /// Извлекаемость через [t] дней при стабильности [s].
  ///
  /// Отрицательный срок приходит, когда прошлый повтор оказался «в будущем»:
  /// человек перевёл часы или сменил пояс. Формула при этом даёт больше
  /// единицы, а вероятность вспомнить больше ста процентов ломает всё, что на
  /// ней стоит — очередь считает такую карту наименее срочной и перестаёт её
  /// показывать. Поэтому границы держит сама формула, а не каждый, кто её
  /// зовёт: пятый вызов однажды забудет.
  double retrievability(double t, double s) {
    if (s <= 0) return 0;
    final days = t < 0 ? 0.0 : t;
    final r = math.pow(1 + _factor * days / s, _decay).toDouble();
    return r.isFinite ? r.clamp(0.0, 1.0) : 0.0;
  }

  /// Оптимальный интервал (дни) для стабильности [s] и целевого retention.
  int _intervalDays(double s) {
    final ivl = (s / _factor) * (math.pow(requestRetention, 1 / _decay) - 1);
    return ivl.round().clamp(1, maximumInterval);
  }

  /// Интервал review-карты. При [fuzz] — детерминированный разброс вокруг
  /// оптимального (Anki-подобно): карты, добавленные/пришедшие в один день, не
  /// слипаются на одну дату повтора навсегда, нагрузка разводится по дням.
  Duration _reviewInterval(double s, {bool fuzz = false, Object? key}) {
    final base = _intervalDays(s);
    return Duration(days: fuzz ? _fuzzInterval(base, key ?? s) : base);
  }

  /// Разброс интервала. Короткие интервалы (<3 дней) не трогаем — там разброс
  /// вреден. Ширина растёт с интервалом (±~8%, минимум ±1 день). Сдвиг
  /// ДЕТЕРМИНИРОВАН (из бит стабильности), а не случаен — воспроизводимо в
  /// тестах и стабильно при повторном планировании той же карты, но у разных
  /// карт сдвиги разные → нагрузка расходится.
  int _fuzzInterval(int ivl, Object seed) {
    if (ivl < 3) return ivl;
    final spread = math.max(1, (ivl * 0.08).round());
    // Ключом должна быть КАРТА, а не прочность: у слов, пройденных одинаково,
    // прочность побитово равна, и разброс из неё давал всем один и тот же
    // день — ровно то, ради чего разброс и задуман.
    final bits = seed.hashCode & 0x7fffffff;
    final offset = (bits % (2 * spread + 1)) - spread; // [-spread, +spread]
    return (ivl + offset).clamp(1, maximumInterval);
  }

  double _initStability(Rating g) =>
      w[g.grade - 1].clamp(0.1, maximumInterval.toDouble());

  double _initDifficulty(int grade) {
    final d = w[4] - math.exp(w[5] * (grade - 1)) + 1;
    return d.clamp(1.0, 10.0);
  }

  double _nextDifficulty(double d, Rating g) {
    final delta = -w[6] * (g.grade - 3);
    // Линейное демпфирование (FSRS-5): чем выше D, тем меньше сдвиг.
    final damped = d + delta * (10 - d) / 9;
    // Возврат к среднему (к сложности «лёгкой» первой оценки).
    final reverted = w[7] * _initDifficulty(4) + (1 - w[7]) * damped;
    return reverted.clamp(1.0, 10.0);
  }

  double _successStability(double d, double s, double r, Rating g) {
    final hard = g == Rating.hard ? w[15] : 1.0;
    final easy = g == Rating.easy ? w[16] : 1.0;
    final inc = math.exp(w[8]) *
        (11 - d) *
        math.pow(s, -w[9]) *
        (math.exp(w[10] * (1 - r)) - 1) *
        hard *
        easy;
    return s * (1 + inc);
  }

  /// Прочность после «не помню».
  ///
  /// В FSRS-5 у неё есть потолок `S / exp(w17·w18)`, и без него формула на
  /// большой просрочке возвращает БОЛЬШЕ прежней прочности: слово, забытое
  /// начисто после года молчания, получало интервал вдвое длиннее прежнего.
  /// Бьёт сильнее всего по пиявкам — там, где это дороже всего.
  double _failStability(double d, double s, double r) {
    final longTerm = w[11] *
        math.pow(d, -w[12]) *
        (math.pow(s + 1, w[13]) - 1) *
        math.exp(w[14] * (1 - r));
    final ceiling = s / math.exp(w[17] * w[18]);
    return math.min(longTerm.toDouble(), ceiling);
  }

  /// Краткосрочная стабильность (внутри дня / на шагах learning).
  double _shortTermStability(double s, Rating g) {
    return s * math.exp(w[17] * (g.grade - 3 + w[18]));
  }

  // ------------------------------- Планирование -------------------------------

  /// Возвращает НОВОЕ состояние карты после оценки [g] в момент [now].
  ///
  /// [fuzz] — разбрасывать ли review-интервал (в реальном планировании да; в
  /// [preview] нет, чтобы подписи на кнопках были стабильными).
  /// [fuzzKey] — то, чем карта отличается от соседки (обычно её id): из него
  /// считается разброс дат. Без ключа разброс берётся из прочности, а она у
  /// одинаково пройденных слов совпадает побитово.
  ReviewState review(ReviewState prev, Rating g, DateTime now,
      {bool fuzz = true, Object? fuzzKey}) {
    final elapsedDays = prev.lastReview == null
        ? 0.0
        : math.max(0, now.difference(prev.lastReview!).inSeconds / 86400.0)
            .toDouble();

    // Второй успех по той же карте за день расписание не двигает.
    //
    // Короткая ветка ниже умножает прочность на константу, не глядя на время,
    // и потолка у этого нет. А «Трудные», «Под угрозой» и разминка показывают
    // карточки без учёта срока, так что прогнать одну и ту же карту можно
    // сколько угодно раз: шесть тапов «Хорошо» уносили её с 84 дней на 463, а
    // «Легко» — на десять лет вперёд. Памяти эти минуты ничего не добавляют,
    // отвечает человек уже по следу от предыдущего показа.
    //
    // Срыв — другое дело: забыл значит забыл, и такой ответ проходит дальше.
    // Ошибиться в сторону «спросим раньше» дёшево, в обратную — потеря слова.
    if (prev.state == FsrsState.review &&
        g != Rating.again &&
        prev.lastReview != null &&
        startOfDay(prev.lastReview!) == startOfDay(now)) {
      return prev.copy()
        ..reps = prev.reps + 1
        ..nudgedByNeighbour = false;
    }

    double s;
    double d;
    // Прочность нуля у не-новой карты приходит из чужого бэкапа и импорта
    // колод. Формулы делят и возводят в отрицательную степень, дают NaN, а
    // `clamp` от NaN возвращает верхнюю границу — карта уезжала на сто лет
    // вперёд и больше не спрашивалась. Считаем такую карту новой: это ровно
    // то, чем она и является.
    if (prev.state == FsrsState.newCard ||
        !prev.stability.isFinite ||
        prev.stability <= 0) {
      d = _initDifficulty(g.grade);
      s = _initStability(g);
    } else {
      final r = retrievability(elapsedDays, prev.stability);
      d = _nextDifficulty(prev.difficulty, g);
      if (g == Rating.again) {
        s = _failStability(prev.difficulty, prev.stability, r);
      } else if (elapsedDays < 1.0) {
        // Короткая формула — про внутридневные шаги, и решает тут ПРОШЕДШЕЕ
        // время, а не ярлык стадии. Прежнее условие («learning или relearning
        // или меньше суток») проглатывало третью проверку: карта со сроком
        // «+10 минут», брошенная на три месяца, при возвращении получала пять
        // дней вместо пятидесяти трёх. А бросают их постоянно — сессия
        // кончилась, приложение закрыли.
        s = _shortTermStability(prev.stability, g);
      } else {
        s = _successStability(prev.difficulty, prev.stability, r, g);
      }
    }
    // NaN до сюда дойти уже не должен, но `clamp` от NaN отдаёт верхнюю
    // границу — молчаливый повтор через сто лет. Ловим явно.
    if (!s.isFinite) s = _initStability(g);
    s = s.clamp(0.01, maximumInterval.toDouble());
    d = d.clamp(1.0, 10.0);

    final next = prev.copy()
      ..stability = s
      ..difficulty = d
      ..reps = prev.reps + 1
      ..lastReview = now
      // Карту спросили — повод «подтянута из-за соседа» исчерпан.
      ..nudgedByNeighbour = false;

    _schedule(prev, next, g, s, now, fuzz, fuzzKey);
    return next;
  }

  /// Доля прироста стабильности за одну встречу слова в тексте.
  /// Скромная намеренно: узнать слово в предложении легче, чем вспомнить его
  /// по карточке, и выдавать одно за другое нельзя.
  static const double passiveGain = 0.15;

  /// Слово попалось при чтении — это тоже припоминание, просто слабое.
  ///
  /// Возвращает новое состояние либо null, если встреча ничего не меняет:
  /// у новых и переучиваемых карт (пассивное узнавание не учит с нуля), у
  /// свежих в памяти (прибавлять нечего) и чаще раза в сутки на карту.
  /// Прибавка тем больше, чем ближе слово к забыванию: встреченное вовремя
  /// слово спасается, хорошо помнимое просто подтверждается.
  ReviewState? passiveExposure(ReviewState prev, DateTime now) {
    if (prev.state != FsrsState.review) return null;
    if (prev.stability <= 0 || prev.lastReview == null) return null;
    if (prev.lastSeen != null &&
        now.difference(prev.lastSeen!) < const Duration(hours: 20)) {
      return null;
    }

    final elapsedDays =
        math.max(0, now.difference(prev.lastReview!).inSeconds / 86400.0)
            .toDouble();
    final r = retrievability(elapsedDays, prev.stability);
    // Память ещё свежая — встреча проходит мимо, как повтор в тот же день.
    if (r >= 0.9) return null;

    final s = (prev.stability * (1 + passiveGain * (1 - r)))
        .clamp(0.01, maximumInterval.toDouble());
    final next = prev.copy()
      ..stability = s
      ..lastSeen = now
      // Срок пересчитан заново, значит и повод «подтянута из-за соседа»
      // исчерпан: иначе сессия показывала метку «сосед сорвался» на карточке,
      // которую уже никто не подтягивает.
      ..nudgedByNeighbour = false;
    // Срок сдвигаем от ПРОШЛОГО повтора: встреча укрепляет память, но не
    // заменяет собой повтор, поэтому точка отсчёта не меняется.
    final shifted = prev.lastReview!.add(_reviewInterval(s, fuzz: false));
    // Только вперёд. Пересчёт от нуля терял разброс, полученный при
    // планировании (до +8%), а прибавка от встречи меньше него — и карта,
    // которую собирались спросить через три недели, прыгала в сегодняшнюю
    // очередь. Встреча слова не может сделать повтор СРОЧНЕЕ.
    next.due = (prev.due != null && prev.due!.isAfter(shifted))
        ? prev.due
        : shifted;
    return next;
  }

  /// На сколько слабеет память соседнего слова, когда рядом случился срыв.
  static const double lapseSpread = 0.9;

  /// Сосед по смыслу сорвался — значит, и это слово держится хуже, чем
  /// считает планировщик.
  ///
  /// Работает в одну сторону: срыв соседа СБЛИЖАЕТ повтор, но успех соседа
  /// ничего не отодвигает. Ошибиться в сторону «спросим пораньше» дёшево,
  /// в сторону «подождём подольше» — потеря слова.
  ReviewState? weakenByNeighbour(ReviewState prev, DateTime now) {
    if (prev.state != FsrsState.review) return null;
    if (prev.stability <= 0 || prev.lastReview == null) return null;

    final s = (prev.stability * lapseSpread).clamp(0.01, maximumInterval.toDouble());
    final next = prev.copy()
      ..stability = s
      ..nudgedByNeighbour = true;
    final due = prev.lastReview!.add(_reviewInterval(s, fuzz: false));
    // Срок только приближаем: если он и так раньше, оставляем как есть.
    next.due = (prev.due != null && prev.due!.isBefore(due)) ? prev.due : due;
    return next;
  }

  void _schedule(ReviewState prev, ReviewState next, Rating g, double s,
      DateTime now, bool fuzz, Object? fuzzKey) {
    if (g == Rating.again) {
      if (prev.state == FsrsState.review) next.lapses = prev.lapses + 1;
      // Переучивают только то, что было выучено. Карта, ни разу не дошедшая до
      // review, после провала возвращается в learning на нулевой шаг: в
      // relearning шаг всего один, и первое же «Хорошо» выпускало новое слово
      // в review, минуя обе внутридневные ступени.
      next.state = prev.state == FsrsState.review
          ? FsrsState.relearning
          : FsrsState.learning;
      final steps =
          next.state == FsrsState.relearning ? relearningSteps : learningSteps;
      next.step = 0;
      next.due = now.add(steps.first);
      return;
    }

    if (g == Rating.easy) {
      next.state = FsrsState.review;
      next.step = 0;
      next.due = now.add(_reviewInterval(s, fuzz: fuzz, key: fuzzKey));
      return;
    }

    // hard или good.
    final inSteps = prev.state == FsrsState.newCard ||
        prev.state == FsrsState.learning ||
        prev.state == FsrsState.relearning;
    if (inSteps) {
      final relearn = prev.state == FsrsState.relearning;
      final steps = relearn ? relearningSteps : learningSteps;
      final curStep = prev.state == FsrsState.newCard ? 0 : prev.step;
      if (g == Rating.hard) {
        // Повторяем текущий шаг.
        next.state = relearn ? FsrsState.relearning : FsrsState.learning;
        next.step = curStep.clamp(0, steps.length - 1);
        next.due = now.add(steps[next.step]);
      } else {
        // good — продвигаем шаг; закончились — выпускаем в review.
        final nextStep = curStep + 1;
        if (nextStep >= steps.length) {
          next.state = FsrsState.review;
          next.step = 0;
          next.due = now.add(_reviewInterval(s, fuzz: fuzz, key: fuzzKey));
        } else {
          next.state = relearn ? FsrsState.relearning : FsrsState.learning;
          next.step = nextStep;
          next.due = now.add(steps[nextStep]);
        }
      }
    } else {
      // Карта в review, успех (hard/good) → новый интервал.
      next.state = FsrsState.review;
      next.step = 0;
      next.due = now.add(_reviewInterval(s, fuzz: fuzz, key: fuzzKey));
    }
  }

  /// Прогноз «когда вернётся» для каждой оценки (для подписей на кнопках),
  /// без изменения состояния карты.
  Map<Rating, Duration> preview(ReviewState prev, DateTime now) {
    final map = <Rating, Duration>{};
    for (final g in Rating.values) {
      final next = review(prev, g, now, fuzz: false);
      final due = next.due ?? now;
      map[g] = due.difference(now);
    }
    return map;
  }
}
