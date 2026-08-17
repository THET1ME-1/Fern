import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/locale_controller.dart';
import '../l10n/strings.dart';
import '../models/deck.dart';
import '../models/fsrs.dart';
import '../models/word_card.dart';
import '../services/answer_check.dart';
import '../services/auto_grade.dart';
import '../services/card_images.dart';
import '../services/construction_catalog.dart';
import '../services/constructions.dart';
import '../services/deck_repository.dart';
import '../services/pro.dart';
import '../services/reading_horizon.dart';
import '../services/text_analysis.dart';
import '../services/word_links.dart';
import '../services/tts_service.dart';
import '../settings_screen.dart';
import '../theme/app_theme.dart';
import '../widgets/shadow_button.dart';
import '../widgets/speaker_button.dart';
import 'results_screen.dart';
import 'study_models.dart';
import '../widgets/morph_shapes.dart';
import '../widgets/session_progress.dart';
import '../widgets/pos_badge.dart';
import '../widgets/pressable.dart';

/// Экран сессии: прогоняет очередь упражнений (флип / выбор / ввод / верно-
/// неверно), обновляет FSRS и показывает результаты.
class SessionScreen extends StatefulWidget {
  final Deck deck;
  final StudyMode mode;
  final List<WordCard> cards;

  /// Как перезагрузить карты для «Ещё сессия» (для пака — все карты пака).
  /// null — берём карты колоды [deck].
  final Future<List<WordCard>> Function()? reload;

  const SessionScreen({
    super.key,
    required this.deck,
    required this.mode,
    required this.cards,
    this.reload,
  });

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen>
    with SingleTickerProviderStateMixin {
  final DeckRepository _repo = DeckRepository.instance;
  final SessionBuilder _builder = SessionBuilder();

  /// Названия правил каталога — варианты для «назови конструкцию».
  List<String> _ruleNames = const [];

  List<Exercise> _queue = [];
  late List<WordCard> _pool;
  int _index = 0;
  int _answered = 0;
  int _correct = 0;
  bool _logged = false;
  bool _ready = false; // очередь собрана (лимиты добираются асинхронно)
  late DateTime _start;

  // Динамическая переочередь: карту, которую ещё не закрепили (осталась в
  // learning/relearning), переспрашиваем в этой же сессии через несколько карт —
  // настоящие learning-шаги, а не «ошибся и забыл до завтра».
  static const int _reinsertGap = 3;
  static const int _maxReinserts = 6; // страховка от бесконечной сессии
  final Map<String, int> _reinserts = {};

  // Данные текущего упражнения (варианты/пары), пересчитываются при смене шага.
  int _dataFor = -1;
  late _ExData _data;

  // Режим «Быстрый повтор»: обратный отсчёт на вопрос + комбо/очки.
  static const int _speedSeconds = 8;
  AnimationController? _speedCtrl;
  int _combo = 0;
  int _bestCombo = 0;
  int _score = 0;
  int _resolvedIndex = -1; // защита от двойного разрешения (тап + таймаут)

  // Автооценка: личный темп ответа и режим двух кнопок. Догружаются вместе с
  // очередью; до этого действуют безопасные значения по умолчанию.
  AutoGrade _autoGrade = const AutoGrade.fallback();
  bool _twoButtons = false;

  // Дневная подача новых слов: нужна пустому экрану, чтобы назвать причину
  // («лимит на сегодня»), а не отговариваться «нечего повторять».
  int _newPerDay = 0;
  int _introducedToday = 0;
  int _newAllowed = 0;

  /// Висит ли диалог выхода. Пока висит, вопросы не видны — значит и отсчёт
  /// «Быстрого повтора» заводить не с чего.
  bool _exitAsked = false;

  /// Когда показан текущий вопрос — отсюда считается время ответа.
  DateTime _shownAt = DateTime.now();

  /// Сколько карт пришло по каждой причине — для сводки «что сделал алгоритм».
  final Map<SelectionReason, int> _byReason = {};

  bool get _isSpeed => widget.mode == StudyMode.speed;

  /// Сколько миллисекунд человек думал над текущим вопросом.
  int get _elapsedMs =>
      DateTime.now().difference(_shownAt).inMilliseconds.clamp(0, 600000);

  @override
  void initState() {
    super.initState();
    _start = DateTime.now();
    _pool = widget.cards;
    if (_isSpeed) {
      _speedCtrl =
          AnimationController(
            vsync: this,
            duration: const Duration(seconds: _speedSeconds),
          )..addStatusListener((s) {
            if (s == AnimationStatus.completed) _onTimeout();
          });
    }
    _prepare();
  }

  /// Добирает лимиты подачи (новые/день, потолок повторов) и строит очередь.
  Future<void> _prepare() async {
    // Что человеку вот-вот встретится в книге — это влияет на порядок подачи.
    // Слова из книги идут первыми только в Pro: это надстройка поверх
    // платного сценария, а не часть обычного расписания.
    if (Pro.bookBoost) {
      _builder.setReadingHorizon(
        await ReadingHorizon.upcoming(widget.deck.languageCode),
        widget.deck.languageCode,
      );
    }
    final newPerDay = await _repo.newPerDay();
    final introduced = await _repo.newIntroducedToday(_start);
    final maxReviews = await _repo.maxReviews();
    // newPerDay == 0 → без лимита новых.
    final newAllowed = await _repo.newAllowedNow(_start);
    // Названия соседних правил — варианты для «назови конструкцию». Берём из
    // каталога языка, а не из своей колоды: с двумя выученными правилами выбор
    // из двух вариантов угадывается монеткой.
    if (widget.mode == StudyMode.grammar) {
      await ConstructionCatalog.instance.ensureLoaded(widget.deck.languageCode);
      _ruleNames = [
        for (final r in ConstructionCatalog.instance.all(widget.deck.languageCode))
          r.name,
      ];
    }
    final queue = _builder.build(
      widget.mode,
      widget.cards,
      _start,
      newAllowed: newAllowed,
      maxReviews: maxReviews,
      direction: studyDirectionFromIndex(widget.deck.directionIndex),
      language: widget.deck.languageCode,
      ruleNames: _ruleNames,
    );
    final autoGrade = await _repo.autoGrade();
    final twoButtons = await _repo.twoButtonRating();
    if (!mounted) return;
    // Причины считаем по УНИКАЛЬНЫМ картам: переспрос той же карточки внутри
    // сессии — не второе «слово из книги».
    final seen = <String>{};
    for (final ex in queue) {
      if (seen.add(ex.card.id)) {
        _byReason[ex.reason] = (_byReason[ex.reason] ?? 0) + 1;
      }
    }
    setState(() {
      _queue = queue;
      _autoGrade = autoGrade;
      _twoButtons = twoButtons;
      _newPerDay = newPerDay;
      _introducedToday = introduced;
      _newAllowed = newAllowed;
      _shownAt = DateTime.now();
      _ready = true;
    });
  }

  /// Новых слов, которые этот режим вообще может показать. Клоуз и «Собери
  /// фразу» живут на карточках с предложением-контекстом: без фильтра пустая
  /// сессия по ним объяснялась бы дневным лимитом, хотя дело не в нём.
  int get _newInDeck =>
      widget.cards.where((c) => c.review.isNew && _fitsMode(c)).length;

  /// Просроченных повторов в колоде — тех, что лимит новых не касается.
  /// Тоже только подходящие режиму: карточка без примера не даст «Контекст»
  /// ни новой, ни просроченной.
  int get _dueInDeck => widget.cards
      .where((c) => !c.review.isNew && c.isDue(DateTime.now()) && _fitsMode(c))
      .length;

  /// Годится ли карточка этому режиму. Клоуз и «Собери фразу» живут на
  /// предложении-контексте, «Связи» — на словах одной темы, «Двойники» — на
  /// похожих парах; остальным режимам подходит любая карточка.
  bool _fitsMode(WordCard c) => switch (widget.mode) {
        StudyMode.cloze => buildCloze(c) != null,
        StudyMode.assemble => buildAssemble(c) != null,
        StudyMode.associations =>
          buildOddOne(c, widget.cards, widget.deck.languageCode) != null,
        StudyMode.twins => buildTwins(c, widget.cards) != null,
        _ => true,
      };

  /// Слова в колоде есть, но НИ ОДНО не годится этому упражнению. Раньше такой
  /// случай выглядел как «Пока нечего повторять, возвращайтесь позже» —
  /// человек ждал завтрашнего дня, хотя ждать было нечего: режиму нужны слова
  /// с примером (или связями), а не время.
  bool get _noFitForMode =>
      widget.cards.isNotEmpty && !widget.cards.any(_fitsMode);

  /// Пустая очередь упёрлась в дневной лимит новых слов, а не в исчерпанную
  /// колоду. Ровно этот случай выглядел как «слова кончились»: экран колоды
  /// считает новые вместе с просроченными и обещает сотню карточек.
  bool get _blockedByNewLimit =>
      _newPerDay > 0 && _newAllowed <= 0 && _newInDeck > 0 && _dueInDeck == 0;

  /// Сколько новых слов даст кнопка «Учить ещё»: дневную порцию, но не больше,
  /// чем осталось в колоде.
  int get _extraOffer => min(_newPerDay > 0 ? _newPerDay : 12, _newInDeck);

  /// Разово поднимает лимит на сегодня и пересобирает очередь на месте.
  Future<void> _studyMoreNew() async {
    await _repo.addExtraNewToday(_extraOffer, _start);
    if (!mounted) return;
    setState(() => _ready = false);
    await _prepare();
  }

  /// Открывает настройки и пересобирает очередь на возврате: человек ушёл
  /// туда менять лимит, и возвращаться к прежнему «слов нет» бессмысленно.
  Future<void> _openLimitSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
    if (!mounted) return;
    setState(() => _ready = false);
    await _prepare();
  }

  @override
  void dispose() {
    _speedCtrl?.dispose();
    super.dispose();
  }

  void _startSpeedCountdown() => _speedCtrl?.forward(from: 0);
  void _freezeSpeed() => _speedCtrl?.stop();

  void _onTimeout() {
    if (!mounted || !_isSpeed) return;
    if (_resolvedIndex == _index) return;
    // Время вышло — засчитываем как неверно и идём дальше.
    _onGraded(_queue[_index], false, Rating.again);
  }

  _ExData _dataForIndex(int i) {
    final ex = _queue[i];
    switch (ex.kind) {
      case ExerciseKind.choose:
      case ExerciseKind.listen:
        final opts = [ex.answer, ..._builder.distractors(ex, _pool)]..shuffle();
        return _ExData(options: opts);
      case ExerciseKind.trueFalse:
        final showTrue = DateTime.now().microsecond.isEven;
        final wrong = _builder.wrongAnswer(ex, _pool);
        if (showTrue || wrong == null) {
          return _ExData(tfShown: ex.answer, tfIsTrue: true);
        }
        return _ExData(tfShown: wrong, tfIsTrue: false);
      case ExerciseKind.oddOne:
        return _ExData(
          odd: buildOddOne(ex.card, _pool, widget.deck.languageCode),
        );
      case ExerciseKind.ruleChoose:
        return _ExData(rule: buildRuleChoice(ex.card, _ruleNames));
      case ExerciseKind.twins:
        return _ExData(twins: buildTwins(ex.card, _pool));
      case ExerciseKind.flip:
      case ExerciseKind.type:
      case ExerciseKind.cloze:
      case ExerciseKind.spell:
      case ExerciseKind.assemble:
        return const _ExData();
    }
  }

  /// Запоминает ответ, признанный верным вопреки переводу на карточке.
  ///
  /// Пишем `updateCards`, а НЕ `saveCards`: последний заменяет весь словарь
  /// целиком и уже однажды схлопнул базу до нескольких строк.
  void _rememberAnswer(WordCard card, String answer) {
    final before = card.accepted.length;
    card.accept(answer);
    if (card.accepted.length != before) _repo.updateCards([card]);
  }

  Future<void> _onGraded(
    Exercise ex,
    bool correct,
    Rating rating, {
    int? answerMs,
  }) async {
    // Один вопрос разрешается один раз (тап пользователя ИЛИ таймаут).
    if (_resolvedIndex == _index) return;
    _resolvedIndex = _index;

    if (_isSpeed) {
      _speedCtrl?.stop();
      if (correct) {
        _combo++;
        _score += 10 + (_combo - 1) * 2; // бонус за серию
        if (_combo > _bestCombo) _bestCombo = _combo;
      } else {
        _combo = 0;
      }
    }

    _answered++;
    if (correct) _correct++;

    if (widget.mode.affectsSchedule) {
      if (widget.mode == StudyMode.learn) {
        ex.card.review.phase =
            _nextPhase(ex.card.review.phase, correct, ex.card.review);
      }
      await _repo.rateCard(
        ex.card,
        rating,
        DateTime.now(),
        answerMs: answerMs ?? _elapsedMs,
        // Чем отвечали — без этого замер времени не с чем сравнивать: набор и
        // тап живут в разных темпах.
        kind: ex.kind.index,
      );
      // Из сессии можно выйти прямо во время записи оценки — тогда двигать
      // очередь уже некуда (иначе «setState() called after dispose()»).
      if (!mounted) return;
      _maybeReinsert(ex, correct);
    }
    _advance();
  }

  /// Уникальных карт в сессии (переспросы — та же карта, счёт не раздувают).
  int get _totalCards => _queue.map((e) => e.card.id).toSet().length;

  /// Сколько карт закрыто: их больше нет впереди в очереди.
  int get _doneCards {
    final ahead = <String>{};
    for (var i = _index; i < _queue.length; i++) {
      ahead.add(_queue[i].card.id);
    }
    return _totalCards - ahead.length;
  }

  /// Неверную карту (осталась в learning/relearning — не закрепили)
  /// переспрашиваем в этой же сессии через несколько карт: настоящее
  /// закрепление ошибки во ВСЕХ режимах, а не «ошибся и забыл до завтра». Верные
  /// ответы очередь не раздувают; игру «Скорость» не трогаем (крисп).
  void _maybeReinsert(Exercise ex, bool correct) {
    if (correct || _isSpeed) return;
    final st = ex.card.review.state;
    if (st != FsrsState.learning && st != FsrsState.relearning) return;
    final n = _reinserts[ex.card.id] ?? 0;
    if (n >= _maxReinserts) return;
    _reinserts[ex.card.id] = n + 1;
    final pos = min(_index + 1 + _reinsertGap, _queue.length);
    _queue.insert(
      pos,
      Exercise(ex.card, ex.kind, reversed: ex.reversed, reason: ex.reason),
    );
  }

  LearnPhase _nextPhase(LearnPhase p, bool correct, ReviewState r) {
    final base = p == LearnPhase.unseen ? LearnPhase.recognize : p;
    final ni = (correct ? base.index + 1 : base.index - 1).clamp(
      LearnPhase.recognize.index,
      LearnPhase.mastered.index,
    );
    // Не пускаем в продуктивные фазы, пока память слаба, — иначе можно
    // «намастерить» за одно сидение (зубрёжка). Порог по стабильности FSRS:
    // «recall» (ввод) — от нескольких дней, «mastered» — только зрелая карта.
    final maxByMemory = r.stability >= 21
        ? LearnPhase.mastered.index
        : r.stability >= 4
            ? LearnPhase.recall.index
            : LearnPhase.produce.index;
    return LearnPhase.values[min(ni, maxByMemory)];
  }

  void _advance() {
    if (_index + 1 >= _queue.length) {
      _finish();
    } else {
      setState(() {
        _index++;
        _shownAt = DateTime.now();
      });
    }
  }

  /// Записывает итог сессии в журнал занятий (для стрика/цели/статистики).
  /// Защищено флагом, чтобы выход и финиш не посчитались дважды.
  void _logProgress() {
    if (_logged || _answered == 0) return;
    _logged = true;
    _repo.logSession(reviews: _answered, correct: _correct);
  }

  void _finish() {
    _logProgress();
    final result = SessionResult(
      _answered,
      _correct,
      DateTime.now().difference(_start),
      score: _isSpeed ? _score : null,
      plan: SessionPlan(
        byReason: Map.of(_byReason),
        separatedPairs: _builder.separatedPairs,
      ),
    );
    // Захватываем нужное в локальные переменные: колбэк переживёт уничтожение
    // этого SessionScreen (кнопка «Ещё» на экране результатов).
    final deck = widget.deck;
    final mode = widget.mode;
    final repo = _repo;
    final reload = widget.reload;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => ResultsScreen(
          result: result,
          onStudyMore: (resultsContext) async {
            final cards =
                reload != null ? await reload() : await repo.cardsForDeck(deck.id);
            if (!resultsContext.mounted) return;
            Navigator.of(resultsContext).pushReplacement(
              MaterialPageRoute(
                builder: (_) => SessionScreen(
                  deck: deck,
                  mode: mode,
                  cards: cards,
                  reload: reload,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  /// Спрашивает про выход листом снизу. Кнопки во всю ширину и в столбик:
  /// в узком ряду «Выйти» и «Отмена» стоят вплотную, а промах здесь стоит
  /// незасчитанной сессии.
  Future<bool?> _askLeave() {
    final scheme = Theme.of(context).colorScheme;
    return showModalBottomSheet<bool>(
      context: context,
      backgroundColor: scheme.surfaceContainerHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                tr('exit_session_title'),
                style: TextStyle(
                  fontFamily: AppTheme.displayFont,
                  fontWeight: FontWeight.w800,
                  fontSize: 22,
                  color: scheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                tr('exit_session_sub'),
                style: TextStyle(
                  fontFamily: AppTheme.bodyFont,
                  fontSize: 15,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(tr('leave')),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, 52),
                  shape: const StadiumBorder(),
                ),
                child: Text(tr('cancel')),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmExit() async {
    if (_exitAsked) return;
    // Пока висит диалог, экран сессии живёт: отсчёт «Быстрого повтора»
    // продолжал тикать, карточки получали «не помню» каждые восемь секунд и
    // портили расписание человеку, который просто задумался над выходом.
    //
    // Одной заморозки мало. Подсветка выбранного варианта отложена на 850 мс,
    // и если выйти сразу после ответа, она добегает уже под диалогом, двигает
    // очередь и заставляет `build` запустить отсчёт заново — дальше провалы
    // сыплются до конца очереди по карточкам, которых никто не видел.
    _exitAsked = true;
    _freezeSpeed();
    // Лист снизу, а не диалог по центру: рука уже у нижнего края экрана —
    // там кнопки оценки, — и тянуться к середине ради ответа незачем.
    final leave = await _askLeave();
    if (leave == true && mounted) {
      _logProgress(); // засчитываем то, что успели пройти
      Navigator.of(context).pop();
      return;
    }
    _exitAsked = false;
    // Остались — отсчёт начинается заново, с полного времени: доигрывать
    // остаток, пока человек читал диалог, нечестно.
    if (mounted && _isSpeed) _startSpeedCountdown();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (!_ready) {
      return const Scaffold(body: Center(child: Waiting(size: 34)));
    }
    if (_queue.isEmpty) return _emptyState(scheme);

    if (_dataFor != _index) {
      _data = _dataForIndex(_index);
      _dataFor = _index;
      _resolvedIndex = -1; // новый вопрос ещё не разрешён
      // Под открытым диалогом выхода отсчёт не заводим: вопрос не виден.
      if (_isSpeed && !_exitAsked) _startSpeedCountdown();
    }
    final ex = _queue[_index];
    // Считаем по КАРТАМ, а не по длине очереди: переспрос ошибки вставляет ту же
    // карту ещё раз, и счётчик «3 / 10» на глазах превращался в «3 / 13» — будто
    // работа не убывает, а прибывает.
    final total = _totalCards;
    final done = _doneCards;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmExit();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: _confirmExit,
          ),
          title: Text('${(done + 1).clamp(1, total)} / $total'),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(16),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: SessionProgress(done: done, total: total),
            ),
          ),
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: _isSpeed
                ? Column(
                    children: [
                      _speedHeader(scheme),
                      Expanded(child: _switcher(ex, scheme)),
                    ],
                  )
                : Column(
                    children: [
                      _reasonChip(scheme, ex.reason),
                      Expanded(child: _switcher(ex, scheme)),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  /// Смена вопроса: уходящая карточка гаснет со сдвигом вверх, следующая
  /// приходит снизу. Подмена кадром читается как рывок, а человек проводит
  /// в этом экране почти всё время в приложении.
  ///
  /// Ключ — номер в очереди: переспрос той же карточки тоже считается новым
  /// показом, иначе повтор появлялся бы без перехода.
  Widget _switcher(Exercise ex, ColorScheme scheme) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      switchInCurve: AppTheme.emphasizedDecelerate,
      switchOutCurve: Curves.easeInCubic,
      // Уходящая и приходящая карточки не должны толкать друг друга по layout.
      layoutBuilder: (current, previous) =>
          Stack(alignment: Alignment.topCenter, children: [...previous, ?current]),
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.045),
            end: Offset.zero,
          ).animate(anim),
          child: child,
        ),
      ),
      child: KeyedSubtree(
        key: ValueKey(_index),
        child: _exerciseWidget(ex, scheme),
      ),
    );
  }

  /// Шапка «Быстрого повтора»: комбо, очки и убывающий обратный отсчёт.
  Widget _speedHeader(ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.local_fire_department_rounded,
                    size: 20,
                    color: _combo > 0
                        ? const Color(0xFFFF8A34)
                        : scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '×$_combo',
                    style: TextStyle(
                      fontFamily: AppTheme.displayFont,
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                      color: scheme.onSurface,
                    ),
                  ),
                ],
              ),
              Text(
                '$_score',
                style: TextStyle(
                  fontFamily: AppTheme.displayFont,
                  fontWeight: FontWeight.w800,
                  fontSize: 20,
                  color: scheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          AnimatedBuilder(
            animation: _speedCtrl!,
            builder: (_, _) {
              final left = 1 - _speedCtrl!.value;
              return ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: left,
                  minHeight: 8,
                  color: left < 0.3 ? scheme.error : scheme.primary,
                  backgroundColor: scheme.surfaceContainerHighest,
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _exerciseWidget(Exercise ex, ColorScheme scheme) {
    final key = ValueKey(_index);
    switch (ex.kind) {
      case ExerciseKind.flip:
        return _FlipExercise(
          key: key,
          ex: ex,
          languageCode: widget.deck.languageCode,
          previews: Fsrs.instance.preview(ex.card.review, DateTime.now()),
          autoGrade: _autoGrade,
          twoButtons: _twoButtons,
          onRated: (r, ms) =>
              _onGraded(ex, r != Rating.again, r, answerMs: ms),
        );
      case ExerciseKind.oddOne:
        final odd = _data.odd;
        // Связи могли исчезнуть, пока сессия шла (карточку правили) — тогда
        // молча отдаём флип, а не пустой экран.
        if (odd == null) {
          return _FlipExercise(
            key: key,
            ex: ex,
            languageCode: widget.deck.languageCode,
            previews: Fsrs.instance.preview(ex.card.review, DateTime.now()),
            autoGrade: _autoGrade,
            twoButtons: _twoButtons,
            onRated: (r, ms) =>
                _onGraded(ex, r != Rating.again, r, answerMs: ms),
          );
        }
        return _OddOneExercise(
          key: key,
          odd: odd,
          onAnswered: (correct) =>
              _onGraded(ex, correct, correct ? Rating.good : Rating.again),
        );
      case ExerciseKind.listen:
        return _ListenExercise(
          key: key,
          ex: ex,
          languageCode: widget.deck.languageCode,
          options: _data.options,
          onAnswered: (correct) =>
              _onGraded(ex, correct, correct ? Rating.good : Rating.again),
        );
      case ExerciseKind.choose:
        return _ChooseExercise(
          key: key,
          ex: ex,
          options: _data.options,
          onSelected: _isSpeed ? _freezeSpeed : null,
          onAnswered: (correct) =>
              _onGraded(ex, correct, correct ? Rating.good : Rating.again),
        );
      case ExerciseKind.type:
        return _TypeExercise(
          key: key,
          ex: ex,
          autoGrade: _autoGrade,
          languageCode: widget.deck.languageCode,
          onGraded: (r, ms) =>
              _onGraded(ex, r != Rating.again, r, answerMs: ms),
          onAccepted: (answer) => _rememberAnswer(ex.card, answer),
        );
      case ExerciseKind.cloze:
        return _ClozeExercise(
          key: key,
          ex: ex,
          languageCode: widget.deck.languageCode,
          onAnswered: (correct) =>
              _onGraded(ex, correct, correct ? Rating.good : Rating.again),
        );
      case ExerciseKind.spell:
        return _SpellExercise(
          key: key,
          ex: ex,
          languageCode: widget.deck.languageCode,
          autoGrade: _autoGrade,
          onGraded: (r, ms) =>
              _onGraded(ex, r != Rating.again, r, answerMs: ms),
        );
      case ExerciseKind.assemble:
        return _AssembleExercise(
          key: key,
          ex: ex,
          languageCode: widget.deck.languageCode,
          onAnswered: (correct) =>
              _onGraded(ex, correct, correct ? Rating.good : Rating.again),
        );
      case ExerciseKind.trueFalse:
        return _TrueFalseExercise(
          key: key,
          ex: ex,
          shown: _data.tfShown,
          isTrue: _data.tfIsTrue,
          onAnswered: (correct) =>
              _onGraded(ex, correct, correct ? Rating.good : Rating.again),
        );
      case ExerciseKind.twins:
        final twins = _data.twins;
        // Двойник мог исчезнуть, пока сессия шла (карточку правили или
        // удалили) — тогда спрашиваем обычным флипом.
        if (twins == null) {
          return _FlipExercise(
            key: key,
            ex: ex,
            languageCode: widget.deck.languageCode,
            previews: Fsrs.instance.preview(ex.card.review, DateTime.now()),
            autoGrade: _autoGrade,
            twoButtons: _twoButtons,
            onRated: (r, ms) =>
                _onGraded(ex, r != Rating.again, r, answerMs: ms),
          );
        }
        return _TwinsExercise(
          key: key,
          twins: twins,
          onAnswered: (correct) =>
              _onGraded(ex, correct, correct ? Rating.good : Rating.again),
        );
      case ExerciseKind.ruleChoose:
        final choice = _data.rule;
        // Каталог мог не догрузиться (нет ассета языка) — тогда правило
        // спрашиваем флипом, а не показываем пустой экран.
        if (choice == null) {
          return _FlipExercise(
            key: key,
            ex: ex,
            languageCode: widget.deck.languageCode,
            previews: Fsrs.instance.preview(ex.card.review, DateTime.now()),
            autoGrade: _autoGrade,
            twoButtons: _twoButtons,
            onRated: (r, ms) =>
                _onGraded(ex, r != Rating.again, r, answerMs: ms),
          );
        }
        return _RuleChooseExercise(
          key: key,
          choice: choice,
          ruleCode: ex.card.rule,
          explanation: ex.card.back,
          languageCode: widget.deck.languageCode,
          onAnswered: (correct) =>
              _onGraded(ex, correct, correct ? Rating.good : Rating.again),
        );
    }
  }

  /// Метка «почему эта карточка здесь». Обычный повтор по сроку метки не носит:
  /// объяснять надо неочевидное, иначе подпись превращается в шум.
  Widget _reasonChip(ColorScheme scheme, SelectionReason reason) {
    // Обычный повтор по сроку объяснять нечего — там метки просто нет.
    if (reason == SelectionReason.due) return const SizedBox(height: 4);

    final (IconData icon, String label, Color bg, Color fg) = switch (reason) {
      SelectionReason.newWord => (
          Icons.fiber_new_rounded,
          tr('reason_new'),
          scheme.surfaceContainerHighest,
          scheme.onSurfaceVariant,
        ),
      SelectionReason.book => (
          Icons.menu_book_rounded,
          tr('reason_book'),
          scheme.tertiaryContainer,
          scheme.onTertiaryContainer,
        ),
      // Не errorContainer: роль ошибки в M3 занята настоящими сбоями, а красная
      // плашка над карточкой читается как «что-то сломалось». Здесь же подсказка.
      SelectionReason.neighbourLapse || SelectionReason.due => (
          Icons.hub_rounded,
          tr('reason_neighbour'),
          scheme.secondaryContainer,
          scheme.onSecondaryContainer,
        ),
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
        ),
        padding: const EdgeInsets.fromLTRB(10, 5, 14, 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: fg),
            const SizedBox(width: 6),
            // Немецкое «Nachbar abgerutscht» вдвое длиннее русского — на узком
            // экране подпись должна ужиматься, а не рвать пилюлю.
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: AppTheme.bodyFont,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: fg,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Подпись пустого экрана для режима, которому не хватило материала:
  /// объясняет, ЧТО добавить, а не «зайдите позже».
  String get _modeEmptyKey => switch (widget.mode) {
        StudyMode.cloze || StudyMode.assemble => 'mode_empty_context',
        StudyMode.associations => 'mode_empty_links',
        StudyMode.twins => 'mode_empty_twins',
        _ => 'mode_empty_generic',
      };

  Widget _emptyState(ColorScheme scheme) {
    final limited = _blockedByNewLimit;
    final noFit = !limited && _noFitForMode;
    final title = limited
        ? tr('new_limit_title')
        : (noFit ? tr('mode_empty_title') : tr('nothing_due_title'));
    final sub = limited
        ? trf('new_limit_sub', {
            'n': trn('n_words', _introducedToday),
            'limit': '$_newPerDay',
            'rest': trn('n_words', _newInDeck),
          })
        : (noFit ? tr(_modeEmptyKey) : tr('nothing_due_sub'));
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  limited
                      ? Icons.hourglass_bottom_rounded
                      : (noFit
                          ? Icons.filter_alt_off_rounded
                          : Icons.task_alt_rounded),
                  size: 72,
                  color: scheme.primary,
                ),
                const SizedBox(height: 20),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: AppTheme.displayFont,
                    fontWeight: FontWeight.w700,
                    fontSize: 22,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  sub,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: AppTheme.bodyFont,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 24),
                if (limited) ...[
                  FilledButton.icon(
                    onPressed: _studyMoreNew,
                    icon: const Icon(Icons.add_rounded),
                    label: Text(trf('new_limit_more', {
                      'n': trn('n_words', _extraOffer),
                    })),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _openLimitSettings,
                    child: Text(tr('new_limit_settings')),
                  ),
                  const SizedBox(height: 4),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(tr('back_to_deck')),
                  ),
                ] else
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(tr('back_to_deck')),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Данные, специфичные для текущего упражнения.
class _ExData {
  final List<String> options;
  final String tfShown;
  final bool tfIsTrue;
  /// Данные «третьего лишнего» (режим «Связи»).
  final OddOne? odd;

  /// Данные «назови конструкцию» (режим «Правила»).
  final RuleChoice? rule;

  /// Данные «разведи двойников».
  final Twins? twins;

  const _ExData({
    this.options = const [],
    this.tfShown = '',
    this.tfIsTrue = true,
    this.odd,
    this.rule,
    this.twins,
  });
}

// ============================ Упражнение: флип-карточка ============================

class _FlipExercise extends StatefulWidget {
  final Exercise ex;
  final String languageCode;
  final Map<Rating, Duration> previews;

  /// Личный темп ответа — по нему подсвечивается рекомендованная ступень.
  final AutoGrade autoGrade;

  /// Режим двух кнопок: «Не помню / Помню», ступень подбирается сама.
  final bool twoButtons;

  /// Оценка и время вспоминания (мс) — от показа вопроса до раскрытия ответа.
  final void Function(Rating rating, int recallMs) onRated;

  const _FlipExercise({
    super.key,
    required this.ex,
    required this.languageCode,
    required this.previews,
    required this.autoGrade,
    required this.twoButtons,
    required this.onRated,
  });

  @override
  State<_FlipExercise> createState() => _FlipExerciseState();
}

class _FlipExerciseState extends State<_FlipExercise> {
  bool _revealed = false;
  bool _done = false;

  /// Момент показа вопроса и время, за которое человек вспомнил.
  ///
  /// Считаем ДО раскрытия ответа: дальше идёт чтение перевода и выбор кнопки,
  /// к вспоминанию это отношения не имеет.
  final DateTime _shownAt = DateTime.now();
  int? _recallMs;

  /// Крючок открыт (по кнопке или после срыва).
  bool _hinted = false;

  /// Срыв уже нажат, но карту держим на экране — показываем крючок.
  bool _pendingAgain = false;

  String get _mnemonic => widget.ex.card.mnemonic.trim();

  /// Крючок открывают, чтобы вспомнить САМОМУ — ответ при этом остаётся
  /// закрытым, иначе подсказка превращается в подглядывание.
  void _showHook() {
    HapticFeedback.selectionClick();
    setState(() => _hinted = true);
  }

  /// Раскрывает ответ, зафиксировав время вспоминания.
  void _reveal() {
    if (_revealed) return;
    setState(() {
      _recallMs =
          DateTime.now().difference(_shownAt).inMilliseconds.clamp(0, 600000);
      _revealed = true;
    });
  }

  /// Ступень, которую подсказывает время ответа. Пока ответ закрыт — нет.
  Rating? get _suggested {
    final ms = _recallMs;
    if (ms == null) return null;
    return widget.autoGrade.recalled(ms);
  }

  void _rate(Rating r) {
    if (_done) return;

    // Срыв на карте с крючком: сперва показать крючок, оценку отдать следующим
    // тапом. Момент ошибки — единственный, когда подсказка попадает точно.
    if (r == Rating.again && !_hinted && _mnemonic.isNotEmpty) {
      HapticFeedback.selectionClick();
      setState(() {
        _hinted = true;
        _revealed = true;
        _pendingAgain = true;
      });
      return;
    }

    _done = true;
    HapticFeedback.selectionClick();
    widget.onRated(_withHintPenalty(r), _recallMs ?? 0);
  }

  /// Вспомнил с подсказкой — это не то же, что вспомнил сам: оценка едет на
  /// ступень вниз. Срыв и «трудно» не трогаем, ниже уже некуда.
  Rating _withHintPenalty(Rating r) {
    if (!_hinted) return r;
    return switch (r) {
      Rating.easy => Rating.good,
      Rating.good => Rating.hard,
      Rating.hard || Rating.again => r,
    };
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ex = widget.ex;

    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  onTap: _reveal,
                  child: _FlipCard(
                    showBack: _revealed,
                    front: _cardFace(scheme, ex.prompt, null, isFront: true),
                    back: _cardFace(
                      scheme,
                      ex.answer,
                      ex.card.example,
                      isFront: false,
                      imagePath: CardImages.resolve(ex.card.image),
                    ),
                  ),
                ),
              ),
              // Динамик — озвучивает изучаемое слово в любой момент.
              Positioned(
                top: 8,
                right: 8,
                child: SpeakerButton(
                  text: ex.card.front,
                  languageCode: widget.languageCode,
                  size: 24,
                  sourceUrl: ex.card.sourceUrl,
                  clipStartMs: ex.card.clipStartMs,
                  clipEndMs: ex.card.clipEndMs,
                ),
              ),
              if (_mnemonic.isNotEmpty)
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 12,
                  child: _hookSlot(scheme),
                ),
            ],
          ),
        ),
        // «Повтори за диктором» — только на раскрытой карточке: до ответа
        // произносить слово вслух значит подсказывать себе.
        if (_revealed) ...[
          const SizedBox(height: 12),
          Center(
            child: ShadowButton(
              text: ex.card.front,
              languageCode: widget.languageCode,
            ),
          ),
        ],
        const SizedBox(height: 16),
        if (_pendingAgain)
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () {
                _done = true;
                widget.onRated(Rating.again, _recallMs ?? 0);
              },
              icon: const Icon(Icons.arrow_forward_rounded),
              label: Text(tr('hook_next')),
            ),
          )
        else if (!_revealed)
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _reveal,
              icon: const Icon(Icons.visibility_rounded),
              label: Text(tr('show_answer')),
            ),
          )
        else if (widget.twoButtons)
          Row(
            children: [
              _rateBtn(
                scheme,
                Rating.again,
                tr('rate_again'),
                scheme.errorContainer,
                scheme.onErrorContainer,
              ),
              const SizedBox(width: 8),
              // «Помню» — ступень подберёт время ответа.
              _rateBtn(
                scheme,
                _suggested ?? Rating.good,
                tr('rate_knew'),
                scheme.primaryContainer,
                scheme.onPrimaryContainer,
                showPreview: false,
              ),
            ],
          )
        else
          Row(
            children: [
              _rateBtn(
                scheme,
                Rating.again,
                tr('rate_again'),
                scheme.errorContainer,
                scheme.onErrorContainer,
              ),
              const SizedBox(width: 8),
              _rateBtn(
                scheme,
                Rating.hard,
                tr('rate_hard'),
                scheme.tertiaryContainer,
                scheme.onTertiaryContainer,
              ),
              const SizedBox(width: 8),
              _rateBtn(
                scheme,
                Rating.good,
                tr('rate_good'),
                scheme.primaryContainer,
                scheme.onPrimaryContainer,
              ),
              const SizedBox(width: 8),
              _rateBtn(
                scheme,
                Rating.easy,
                tr('rate_easy'),
                scheme.secondaryContainer,
                scheme.onSecondaryContainer,
              ),
            ],
          ),
        if (_revealed && !_pendingAgain && !widget.twoButtons)
          _suggestionNote(scheme),
        if (_hinted && !_pendingAgain) ...[
          const SizedBox(height: 8),
          Text(
            tr('hook_used'),
            style: TextStyle(
              fontFamily: AppTheme.bodyFont,
              fontSize: 11.5,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }

  /// Внизу карточки: кнопка «Крючок», пока подсказка закрыта, и сама подсказка
  /// после открытия.
  Widget _hookSlot(ColorScheme scheme) {
    if (!_hinted) {
      return Align(
        alignment: Alignment.bottomCenter,
        child: ActionChip(
          avatar: const Icon(Icons.lightbulb_outline_rounded, size: 18),
          label: Text(tr('hook_show')),
          onPressed: _showHook,
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.lightbulb_rounded,
            size: 20,
            color: scheme.onTertiaryContainer,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr('hook_label'),
                  style: TextStyle(
                    fontFamily: AppTheme.bodyFont,
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                    letterSpacing: 0.9,
                    color: scheme.onTertiaryContainer.withValues(alpha: 0.75),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _mnemonic,
                  style: TextStyle(
                    fontFamily: AppTheme.bodyFont,
                    fontSize: 15,
                    height: 1.35,
                    color: scheme.onTertiaryContainer,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _cardFace(
    ColorScheme scheme,
    String text,
    String? example, {
    required bool isFront,
    String? imagePath,
  }) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: isFront ? scheme.surfaceContainerHigh : scheme.primaryContainer,
        borderRadius: BorderRadius.circular(28),
      ),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (imagePath != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 210),
                child: Image.file(
                  File(imagePath),
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            ),
            const SizedBox(height: 18),
          ],
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: AppTheme.wordFont,
              fontWeight: FontWeight.w700,
              fontSize: 34,
              color: isFront ? scheme.onSurface : scheme.onPrimaryContainer,
            ),
          ),
          if (example != null && example.trim().isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              example,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: AppTheme.bodyFont,
                fontSize: 15,
                fontStyle: FontStyle.italic,
                color: scheme.onPrimaryContainer.withValues(alpha: 0.8),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Подпись под кнопками: откуда взялась подсветка. Без неё подсветка читается
  /// как «правильный ответ», а это подсказка, а не приговор.
  Widget _suggestionNote(ColorScheme scheme) {
    final ms = _recallMs;
    if (ms == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.timer_outlined,
            size: 13,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              trf('rate_hint_timing', {
                'time': trf('dur_sec', {'s': (ms / 1000).round().clamp(1, 999)}),
              }),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: AppTheme.bodyFont,
                fontSize: 11.5,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _rateBtn(
    ColorScheme scheme,
    Rating r,
    String label,
    Color bg,
    Color fg, {
    bool showPreview = true,
  }) {
    final dur = showPreview ? widget.previews[r] : null;
    // Подсветка рекомендации: обводка, а не другой цвет — цвета ступеней уже
    // заняты смыслом, менять их значило бы сбить привычку.
    final picked = !widget.twoButtons && _suggested == r;
    return Expanded(
      // Кнопка вдавливается под пальцем: экран занятия был единственным
      // местом без физического отклика на нажатие.
      child: PressableScale(
        child: Material(
          color: bg,
          clipBehavior: Clip.antiAlias,
        // borderRadius и shape вместе Material не принимает — форма задаётся
        // одним shape, обводка появляется только у рекомендованной ступени.
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: picked ? BorderSide(color: fg, width: 2) : BorderSide.none,
        ),
        child: InkWell(
          onTap: () => _rate(r),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
            child: Column(
              children: [
                Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  style: TextStyle(
                    fontFamily: AppTheme.bodyFont,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: fg,
                  ),
                ),
                if (dur != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    durationLabel(dur),
                    maxLines: 1,
                    style: TextStyle(
                      fontFamily: AppTheme.bodyFont,
                      fontSize: 10.5,
                      color: fg.withValues(alpha: 0.75),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        ),
      ),
    );
  }
}

/// Плавный поворот по оси Y при показе ответа (M3 flip).
class _FlipCard extends StatefulWidget {
  final bool showBack;
  final Widget front;
  final Widget back;

  const _FlipCard({
    required this.showBack,
    required this.front,
    required this.back,
  });

  @override
  State<_FlipCard> createState() => _FlipCardState();
}

class _FlipCardState extends State<_FlipCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
    value: widget.showBack ? 1 : 0,
  );

  @override
  void didUpdateWidget(covariant _FlipCard old) {
    super.didUpdateWidget(old);
    if (widget.showBack && !old.showBack) _c.forward();
    if (!widget.showBack && old.showBack) _c.reverse();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final angle = _c.value * 3.1415926;
        final showingBack = _c.value > 0.5;
        final content = showingBack
            ? Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()..rotateY(3.1415926),
                child: widget.back,
              )
            : widget.front;
        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.001)
            ..rotateY(angle),
          child: content,
        );
      },
    );
  }
}

// ============================ Упражнение: выбор варианта ============================

class _ChooseExercise extends StatefulWidget {
  final Exercise ex;
  final List<String> options;
  final void Function(bool correct) onAnswered;

  /// Немедленный сигнал в момент выбора (до задержки-подсветки) — «Быстрый
  /// повтор» использует его, чтобы заморозить таймер.
  final VoidCallback? onSelected;

  const _ChooseExercise({
    super.key,
    required this.ex,
    required this.options,
    required this.onAnswered,
    this.onSelected,
  });

  @override
  State<_ChooseExercise> createState() => _ChooseExerciseState();
}

class _ChooseExerciseState extends State<_ChooseExercise> {
  String? _picked;

  void _pick(String opt) {
    if (_picked != null) return;
    final correct =
        opt.trim().toLowerCase() == widget.ex.answer.trim().toLowerCase();
    widget.onSelected?.call();
    setState(() => _picked = opt);
    HapticFeedback.mediumImpact();
    Future.delayed(const Duration(milliseconds: 850), () {
      if (mounted) widget.onAnswered(correct);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ex = widget.ex;
    final correctAns = ex.answer.trim().toLowerCase();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        Text(
          ex.reversed ? tr('choose_word') : tr('choose_translation'),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: AppTheme.bodyFont,
            fontSize: 13,
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(28),
          ),
          alignment: Alignment.center,
          child: Text(
            ex.prompt,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: AppTheme.wordFont,
              fontWeight: FontWeight.w700,
              fontSize: 30,
              color: scheme.onSurface,
            ),
          ),
        ),
        const SizedBox(height: 20),
        Expanded(
          child: ListView.separated(
            itemCount: widget.options.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (_, i) {
              final opt = widget.options[i];
              final isCorrect = opt.trim().toLowerCase() == correctAns;
              Color bg = scheme.surfaceContainerHigh;
              Color fg = scheme.onSurface;
              if (_picked != null) {
                if (isCorrect) {
                  bg = scheme.primaryContainer;
                  fg = scheme.onPrimaryContainer;
                } else if (opt == _picked) {
                  bg = scheme.errorContainer;
                  fg = scheme.onErrorContainer;
                }
              }
              return Material(
                color: bg,
                borderRadius: BorderRadius.circular(18),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => _pick(opt),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 18,
                    ),
                    child: Text(
                      opt,
                      style: TextStyle(
                        // Шрифт слова: в обратном выборе варианты — изучаемые
                        // слова, и «I» среди них обязана читаться.
                        fontFamily: AppTheme.wordFont,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: fg,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ============================ Упражнение: аудио (слушай и выбери) ============================

class _ListenExercise extends StatefulWidget {
  final Exercise ex;
  final String languageCode;
  final List<String> options;
  final void Function(bool correct) onAnswered;

  const _ListenExercise({
    super.key,
    required this.ex,
    required this.languageCode,
    required this.options,
    required this.onAnswered,
  });

  @override
  State<_ListenExercise> createState() => _ListenExerciseState();
}

class _ListenExerciseState extends State<_ListenExercise> {
  String? _picked;

  @override
  void initState() {
    super.initState();
    // Автопроигрывание слова при появлении.
    WidgetsBinding.instance.addPostFrameCallback((_) => _play());
  }

  void _play() {
    TtsService.instance.speak(widget.ex.card.front, widget.languageCode);
  }

  void _pick(String opt) {
    if (_picked != null) return;
    final correct =
        opt.trim().toLowerCase() == widget.ex.answer.trim().toLowerCase();
    setState(() => _picked = opt);
    HapticFeedback.mediumImpact();
    Future.delayed(const Duration(milliseconds: 850), () {
      if (mounted) widget.onAnswered(correct);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final correctAns = widget.ex.answer.trim().toLowerCase();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        Text(
          tr('listen_prompt'),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: AppTheme.bodyFont,
            fontSize: 13,
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        // Большая кнопка-динамик: тап — повторить слово.
        GestureDetector(
          onTap: _play,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 32),
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(28),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.volume_up_rounded,
                  size: 56,
                  color: scheme.onPrimaryContainer,
                ),
                const SizedBox(height: 8),
                Text(
                  tr('tap_to_replay'),
                  style: TextStyle(
                    fontFamily: AppTheme.bodyFont,
                    fontSize: 12,
                    color: scheme.onPrimaryContainer.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        Expanded(
          child: ListView.separated(
            itemCount: widget.options.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (_, i) {
              final opt = widget.options[i];
              final isCorrect = opt.trim().toLowerCase() == correctAns;
              Color bg = scheme.surfaceContainerHigh;
              Color fg = scheme.onSurface;
              if (_picked != null) {
                if (isCorrect) {
                  bg = scheme.primaryContainer;
                  fg = scheme.onPrimaryContainer;
                } else if (opt == _picked) {
                  bg = scheme.errorContainer;
                  fg = scheme.onErrorContainer;
                }
              }
              return Material(
                color: bg,
                borderRadius: BorderRadius.circular(18),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => _pick(opt),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 18,
                    ),
                    child: Text(
                      opt,
                      style: TextStyle(
                        // Шрифт слова: в обратном выборе варианты — изучаемые
                        // слова, и «I» среди них обязана читаться.
                        fontFamily: AppTheme.wordFont,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: fg,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ============================ Упражнение: ввод перевода ============================

class _TypeExercise extends StatefulWidget {
  final Exercise ex;
  final AutoGrade autoGrade;

  /// Язык колоды: на нём написано изучаемое слово.
  final String languageCode;

  /// Ввод оценивает себя сам: сверка с эталоном и время набора говорят больше,
  /// чем самооценка после подглядывания в ответ.
  final void Function(Rating rating, int answerMs) onGraded;

  /// Ответ признан верным, хотя с переводом карточки не совпал. Карточка его
  /// запоминает, и спорить об этом слове больше не придётся.
  final void Function(String answer) onAccepted;

  const _TypeExercise({
    super.key,
    required this.ex,
    required this.autoGrade,
    required this.languageCode,
    required this.onGraded,
    required this.onAccepted,
  });

  @override
  State<_TypeExercise> createState() => _TypeExerciseState();
}

class _TypeExerciseState extends State<_TypeExercise> {
  final TextEditingController _controller = TextEditingController();
  final DateTime _shownAt = DateTime.now();
  TypedMatch? _match;
  int _answerMs = 0;

  /// Идёт сверка ответа переводчиком.
  bool _checking = false;

  /// Ответ засчитан человеком вручную. Оценивать такой ответ по времени нельзя:
  /// в него вошло чтение правильного ответа и раздумье над кнопкой.
  bool _acceptedByHand = false;

  bool get _correct => _match != TypedMatch.wrong;

  /// Язык набранного ответа и язык слова, о котором спросили. В обратном
  /// упражнении стороны меняются местами.
  String get _typedLang =>
      widget.ex.reversed ? widget.languageCode : LocaleController.instance.code;
  String get _promptLang =>
      widget.ex.reversed ? LocaleController.instance.code : widget.languageCode;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  int get _elapsedMs =>
      DateTime.now().difference(_shownAt).inMilliseconds.clamp(0, 600000);

  void _resolve(TypedMatch match, [int? answerMs]) {
    if (_match != null) return;
    setState(() {
      _answerMs = answerMs ?? _elapsedMs;
      _match = match;
    });
    HapticFeedback.mediumImpact();
  }

  /// Сверка в три захода: точное совпадение, ранее засчитанные варианты
  /// карточки и — если ответ всё ещё «мимо» — переводчик.
  ///
  /// Время ответа снимается ДО переводчика: секунды ожидания движка к памяти
  /// человека отношения не имеют, а автооценка судит именно по ним.
  Future<void> _check() async {
    if (_match != null || _checking) return;
    final typed = _controller.text;
    final elapsed = _elapsedMs;
    final local =
        typedQuality(typed, widget.ex.answer, also: widget.ex.acceptedVariants);
    if (local != TypedMatch.wrong) {
      _resolve(local, elapsed);
      return;
    }
    // Пустой ввод — это Enter на пустом поле, сверять переводчиком нечего.
    if (typed.trim().isEmpty) {
      _resolve(TypedMatch.wrong, elapsed);
      return;
    }

    setState(() => _checking = true);
    final same = await AnswerCheck.meansTheSame(
      typed: typed,
      typedLang: _typedLang,
      source: widget.ex.prompt,
      sourceLang: _promptLang,
    );
    if (!mounted) return;
    setState(() => _checking = false);
    // Запоминаем только перевод (прямое направление): в обратном человек ввёл
    // синоним ТЕРМИНА, и класть его в список переводов значит заражать прямую
    // проверку чужим языком.
    if (same && !widget.ex.reversed) widget.onAccepted(typed);
    _resolve(same ? TypedMatch.exact : TypedMatch.wrong, elapsed);
  }

  /// «Всё равно засчитать»: у слова оказалось другое значение, и человек прав.
  /// Зачёт работает в обе стороны, а запоминается только перевод — список
  /// `accepted` хранит сторону back, и термин в нём был бы миной.
  void _acceptAnyway() {
    if (_match != TypedMatch.wrong) return;
    if (!widget.ex.reversed) widget.onAccepted(_controller.text);
    setState(() {
      _acceptedByHand = true;
      _match = TypedMatch.exact;
    });
    HapticFeedback.selectionClick();
  }

  /// Ручной зачёт — «хорошо»: слово человек знал, но время замера уже испорчено
  /// чтением ответа.
  Rating get _rating => _acceptedByHand
      ? Rating.good
      : widget.autoGrade.typed(_match!, _answerMs);

  /// Описка — своё состояние: ответ засчитан, но оценка будет «трудно».
  /// Зелёная галочка рядом с «одна буква мимо» противоречила бы сама себе.
  Color _verdictColor(ColorScheme scheme) => switch (_match) {
        TypedMatch.exact => scheme.primary,
        TypedMatch.typo => scheme.tertiary,
        _ => scheme.error,
      };

  IconData get _verdictIcon => switch (_match) {
        TypedMatch.exact => Icons.check_rounded,
        TypedMatch.typo => Icons.spellcheck_rounded,
        _ => Icons.close_rounded,
      };

  void _skip() => _resolve(TypedMatch.wrong);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ex = widget.ex;
    final answered = _match != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        Text(
          ex.reversed ? tr('type_word') : tr('type_answer'),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: AppTheme.bodyFont,
            fontSize: 13,
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(28),
          ),
          alignment: Alignment.center,
          child: Text(
            ex.prompt,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: AppTheme.wordFont,
              fontWeight: FontWeight.w800,
              fontSize: 30,
              color: scheme.onSurface,
            ),
          ),
        ),
        // Часть речи снимает половину споров ещё до ответа: у `back` спрашивают
        // «спину», а не «назад», и метка «сущ.» это говорит.
        if (ex.card.pos.isNotEmpty && !ex.reversed) ...[
          const SizedBox(height: 10),
          Center(child: PosBadge(code: ex.card.pos)),
        ],
        const SizedBox(height: 20),
        TextField(
          controller: _controller,
          autofocus: true,
          enabled: !answered && !_checking,
          textAlign: TextAlign.center,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _check(),
          style: TextStyle(
            // Шрифт слова: в обратном направлении здесь набирают изучаемое
            // слово, и своя «I» обязана выглядеть как на карточке.
            fontFamily: AppTheme.wordFont,
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: answered ? _verdictColor(scheme) : scheme.onSurface,
          ),
          decoration: InputDecoration(
            hintText: '…',
            suffixIcon: answered
                ? Icon(_verdictIcon, color: _verdictColor(scheme))
                : null,
          ),
        ),
        if (_match == TypedMatch.typo) ...[
          const SizedBox(height: 10),
          Text(
            trf('typed_typo_note', {'a': ex.answer}),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: AppTheme.bodyFont,
              fontSize: 13,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
        if (answered && !_correct) ...[
          const SizedBox(height: 12),
          Text(
            trf('answer_was', {'a': ex.answer}),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: AppTheme.wordFont,
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: scheme.primary,
            ),
          ),
        ],
        const Spacer(),
        if (_checking)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Waiting(size: 22),
              const SizedBox(width: 12),
              Text(
                tr('checking_answer'),
                style: TextStyle(
                  fontFamily: AppTheme.bodyFont,
                  fontSize: 14,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          )
        else if (!answered)
          Row(
            children: [
              // Ширина по надписи, а не доля строки: в трети экрана «Не знаю»
              // ломалось на две строки, а немецкое «Ich weiß nicht» и подавно.
              // Потолок в 42% держит главную кнопку широкой.
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.sizeOf(context).width * 0.42,
                ),
                child: FilledButton.tonal(
                  onPressed: _skip,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      tr('dont_know'),
                      maxLines: 1,
                      softWrap: false,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _check,
                  child: Text(tr('check')),
                ),
              ),
            ],
          )
        else
          Column(
            children: [
              // Ответ мимо перевода — но у слова бывает второе значение.
              // Кнопка отдаёт последнее слово человеку и учит этому карточку.
              if (!_correct && _controller.text.trim().isNotEmpty) ...[
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonal(
                    onPressed: _acceptAnyway,
                    child: Text(tr('count_anyway')),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => widget.onGraded(_rating, _answerMs),
                  child: Text(tr('continue_btn')),
                ),
              ),
            ],
          ),
      ],
    );
  }
}

// ============================ Упражнение: контекст (клоуз) ============================

class _ClozeExercise extends StatefulWidget {
  final Exercise ex;
  final String languageCode;
  final void Function(bool correct) onAnswered;

  const _ClozeExercise({
    super.key,
    required this.ex,
    required this.languageCode,
    required this.onAnswered,
  });

  @override
  State<_ClozeExercise> createState() => _ClozeExerciseState();
}

class _ClozeExerciseState extends State<_ClozeExercise> {
  final TextEditingController _controller = TextEditingController();
  bool? _correct;
  late final Cloze? _cloze = buildCloze(widget.ex.card);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _check() {
    if (_correct != null) return;
    final cloze = _cloze;
    final ok =
        cloze != null &&
        (answerMatches(_controller.text, cloze.answer) ||
            answerMatches(_controller.text, widget.ex.card.front));
    setState(() => _correct = ok);
    HapticFeedback.mediumImpact();
  }

  void _skip() {
    if (_correct != null) return;
    setState(() => _correct = false);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cloze = _cloze;
    final answered = _correct != null;
    final answer = cloze?.answer ?? widget.ex.card.front;
    // После ответа показываем предложение целиком (со вставленным словом).
    final sentence = cloze == null
        ? widget.ex.card.front
        : (answered
              ? cloze.blanked.replaceFirst('_____', answer)
              : cloze.blanked);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        Text(
          tr('cloze_prompt'),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: AppTheme.bodyFont,
            fontSize: 13,
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(28),
          ),
          child: Column(
            children: [
              Text(
                sentence,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: AppTheme.bodyFont,
                  fontSize: 20,
                  height: 1.45,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface,
                ),
              ),
              if (widget.ex.card.back.trim().isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(
                  '≈ ${widget.ex.card.back}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: AppTheme.bodyFont,
                    fontSize: 15,
                    fontStyle: FontStyle.italic,
                    color: scheme.primary,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _controller,
          autofocus: true,
          enabled: !answered,
          textAlign: TextAlign.center,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _check(),
          style: TextStyle(
            fontFamily: AppTheme.bodyFont,
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: answered
                ? (_correct! ? scheme.primary : scheme.error)
                : scheme.onSurface,
          ),
          decoration: InputDecoration(
            hintText: '…',
            suffixIcon: answered
                ? Icon(
                    _correct! ? Icons.check_rounded : Icons.close_rounded,
                    color: _correct! ? scheme.primary : scheme.error,
                  )
                : null,
          ),
        ),
        if (answered && !_correct!) ...[
          const SizedBox(height: 12),
          Text(
            trf('answer_was', {'a': answer}),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: AppTheme.wordFont,
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: scheme.primary,
            ),
          ),
        ],
        const Spacer(),
        if (!answered)
          Row(
            children: [
              // Ширина по надписи, а не доля строки: в трети экрана «Не знаю»
              // ломалось на две строки, а немецкое «Ich weiß nicht» и подавно.
              // Потолок в 42% держит главную кнопку широкой.
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.sizeOf(context).width * 0.42,
                ),
                child: FilledButton.tonal(
                  onPressed: _skip,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      tr('dont_know'),
                      maxLines: 1,
                      softWrap: false,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _check,
                  child: Text(tr('check')),
                ),
              ),
            ],
          )
        else
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => widget.onAnswered(_correct!),
              child: Text(tr('continue_btn')),
            ),
          ),
      ],
    );
  }
}

// ============================ Упражнение: верно / неверно ============================

class _TrueFalseExercise extends StatefulWidget {
  final Exercise ex;
  final String shown;
  final bool isTrue;
  final void Function(bool correct) onAnswered;

  const _TrueFalseExercise({
    super.key,
    required this.ex,
    required this.shown,
    required this.isTrue,
    required this.onAnswered,
  });

  @override
  State<_TrueFalseExercise> createState() => _TrueFalseExerciseState();
}

class _TrueFalseExerciseState extends State<_TrueFalseExercise> {
  bool? _picked;

  void _pick(bool value) {
    if (_picked != null) return;
    final correct = value == widget.isTrue;
    setState(() => _picked = value);
    HapticFeedback.mediumImpact();
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) widget.onAnswered(correct);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ex = widget.ex;
    final answered = _picked != null;
    final correctPick = widget.isTrue;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        Text(
          tr('true_false_q'),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: AppTheme.bodyFont,
            fontSize: 13,
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(28),
            ),
            alignment: Alignment.center,
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  ex.prompt,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: AppTheme.wordFont,
                    fontWeight: FontWeight.w700,
                    fontSize: 30,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 12),
                Icon(Icons.swap_vert_rounded, color: scheme.onSurfaceVariant),
                const SizedBox(height: 12),
                Text(
                  widget.shown,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: AppTheme.wordFont,
                    fontWeight: FontWeight.w700,
                    fontSize: 26,
                    color: scheme.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            _tfButton(
              scheme,
              false,
              tr('false_label'),
              Icons.close_rounded,
              answered,
              correctPick,
            ),
            const SizedBox(width: 12),
            _tfButton(
              scheme,
              true,
              tr('true_label'),
              Icons.check_rounded,
              answered,
              correctPick,
            ),
          ],
        ),
      ],
    );
  }

  Widget _tfButton(
    ColorScheme scheme,
    bool value,
    String label,
    IconData icon,
    bool answered,
    bool correctPick,
  ) {
    Color bg = value ? scheme.primaryContainer : scheme.errorContainer;
    Color fg = value ? scheme.onPrimaryContainer : scheme.onErrorContainer;
    if (answered) {
      final isThisCorrect = value == widget.isTrue;
      if (!isThisCorrect) {
        bg = scheme.surfaceContainerHighest;
        fg = scheme.onSurfaceVariant;
      }
    }
    return Expanded(
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _pick(value),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Column(
              children: [
                Icon(icon, color: fg, size: 28),
                const SizedBox(height: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: AppTheme.bodyFont,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: fg,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================ Упражнение: диктант (Spell) ============================

/// Слышим слово на изучаемом языке (озвучка) + видим перевод-подсказку —
/// вписываем само слово по буквам. Тренирует восприятие на слух и правописание.
class _SpellExercise extends StatefulWidget {
  final Exercise ex;
  final String languageCode;
  final AutoGrade autoGrade;
  final void Function(Rating rating, int answerMs) onGraded;

  const _SpellExercise({
    super.key,
    required this.ex,
    required this.languageCode,
    required this.autoGrade,
    required this.onGraded,
  });

  @override
  State<_SpellExercise> createState() => _SpellExerciseState();
}

class _SpellExerciseState extends State<_SpellExercise> {
  final TextEditingController _controller = TextEditingController();
  final DateTime _shownAt = DateTime.now();
  TypedMatch? _match;
  int _answerMs = 0;

  bool get _correct => _match != TypedMatch.wrong;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _play());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _play() => TtsService.instance.speak(widget.ex.card.front, widget.languageCode);

  void _resolve(TypedMatch match) {
    if (_match != null) return;
    setState(() {
      _answerMs =
          DateTime.now().difference(_shownAt).inMilliseconds.clamp(0, 600000);
      _match = match;
    });
    HapticFeedback.mediumImpact();
  }

  void _check() =>
      _resolve(typedQuality(_controller.text, widget.ex.card.front));

  /// Описка — своё состояние: ответ засчитан, но оценка будет «трудно».
  /// Зелёная галочка рядом с «одна буква мимо» противоречила бы сама себе.
  Color _verdictColor(ColorScheme scheme) => switch (_match) {
        TypedMatch.exact => scheme.primary,
        TypedMatch.typo => scheme.tertiary,
        _ => scheme.error,
      };

  IconData get _verdictIcon => switch (_match) {
        TypedMatch.exact => Icons.check_rounded,
        TypedMatch.typo => Icons.spellcheck_rounded,
        _ => Icons.close_rounded,
      };

  void _skip() => _resolve(TypedMatch.wrong);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ex = widget.ex;
    final answered = _match != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        Text(
          tr('spell_prompt'),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: AppTheme.bodyFont,
            fontSize: 13,
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        // Большая кнопка-динамик — тап повторяет слово.
        GestureDetector(
          onTap: _play,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 28),
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(28),
            ),
            child: Column(
              children: [
                Icon(Icons.volume_up_rounded,
                    size: 52, color: scheme.onPrimaryContainer),
                const SizedBox(height: 6),
                Text(
                  ex.card.back,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: AppTheme.bodyFont,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: scheme.onPrimaryContainer.withValues(alpha: 0.9),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _controller,
          autofocus: true,
          enabled: !answered,
          textAlign: TextAlign.center,
          textInputAction: TextInputAction.done,
          autocorrect: false,
          enableSuggestions: false,
          onSubmitted: (_) => _check(),
          style: TextStyle(
            // Шрифт слова: здесь набирают изучаемое слово по звуку, и своя
            // «I» в поле обязана выглядеть как на карточке.
            fontFamily: AppTheme.wordFont,
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: answered ? _verdictColor(scheme) : scheme.onSurface,
          ),
          decoration: InputDecoration(
            hintText: '…',
            suffixIcon: answered
                ? Icon(_verdictIcon, color: _verdictColor(scheme))
                : null,
          ),
        ),
        if (_match == TypedMatch.typo) ...[
          const SizedBox(height: 10),
          Text(
            trf('typed_typo_note', {'a': ex.card.front}),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: AppTheme.bodyFont,
              fontSize: 13,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
        if (answered && !_correct) ...[
          const SizedBox(height: 12),
          Text(
            trf('answer_was', {'a': ex.card.front}),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: AppTheme.wordFont,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: scheme.primary,
            ),
          ),
        ],
        const Spacer(),
        if (!answered)
          Row(
            children: [
              // Ширина по надписи, а не доля строки: в трети экрана «Не знаю»
              // ломалось на две строки, а немецкое «Ich weiß nicht» и подавно.
              // Потолок в 42% держит главную кнопку широкой.
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.sizeOf(context).width * 0.42,
                ),
                child: FilledButton.tonal(
                  onPressed: _skip,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      tr('dont_know'),
                      maxLines: 1,
                      softWrap: false,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _check,
                  child: Text(tr('check')),
                ),
              ),
            ],
          )
        else
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => widget.onGraded(
                  widget.autoGrade.typed(_match!, _answerMs), _answerMs),
              child: Text(tr('continue_btn')),
            ),
          ),
      ],
    );
  }
}

// ============================ Упражнение: собери фразу ============================

/// Из перемешанных слов собрать предложение-контекст (порядок слов). После
/// ответа показываем эталон и озвучиваем его.
// ============================ Упражнение: третий лишний ============================

/// «Связи»: два слова рядом по смыслу, третье чужое. Проверяет не перевод, а
/// смысловое соседство, поэтому расписание FSRS не двигает.
class _OddOneExercise extends StatefulWidget {
  final OddOne odd;
  final void Function(bool correct) onAnswered;

  const _OddOneExercise({
    super.key,
    required this.odd,
    required this.onAnswered,
  });

  @override
  State<_OddOneExercise> createState() => _OddOneExerciseState();
}

class _OddOneExerciseState extends State<_OddOneExercise> {
  int? _picked;

  void _pick(int i) {
    if (_picked != null) return;
    setState(() => _picked = i);
    final correct = i == widget.odd.oddIndex;
    HapticFeedback.selectionClick();
    Future.delayed(const Duration(milliseconds: 1100), () {
      if (mounted) widget.onAnswered(correct);
    });
  }

  /// Пара, ради которой всё затевалось: два оставшихся слова.
  String get _pairExplanation {
    final pair = [
      for (var i = 0; i < widget.odd.options.length; i++)
        if (i != widget.odd.oddIndex) widget.odd.options[i].front,
    ];
    return trf('odd_one_because', {
      'a': pair.isNotEmpty ? pair.first : '',
      'b': pair.length > 1 ? pair[1] : '',
      'kind': tr(widget.odd.kind.titleKey).toLowerCase(),
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final answered = _picked != null;

    return Column(
      children: [
        const SizedBox(height: 8),
        Text(
          tr('odd_one_prompt'),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: AppTheme.displayFont,
            fontWeight: FontWeight.w600,
            fontSize: 20,
            color: scheme.onSurface,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          tr('odd_one_sub'),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: AppTheme.bodyFont,
            fontSize: 13,
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),
        for (var i = 0; i < widget.odd.options.length; i++) ...[
          _option(i, scheme),
          const SizedBox(height: 11),
        ],
        const Spacer(),
        if (answered)
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: scheme.secondaryContainer,
              borderRadius: BorderRadius.circular(20),
            ),
            padding: const EdgeInsets.fromLTRB(16, 13, 16, 15),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr('odd_one_link'),
                  style: TextStyle(
                    fontFamily: AppTheme.bodyFont,
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                    letterSpacing: 0.9,
                    color: scheme.onSecondaryContainer.withValues(alpha: 0.75),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _pairExplanation,
                  style: TextStyle(
                    fontFamily: AppTheme.bodyFont,
                    fontSize: 15,
                    height: 1.35,
                    color: scheme.onSecondaryContainer,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _option(int i, ColorScheme scheme) {
    final card = widget.odd.options[i];
    final answered = _picked != null;
    final isOdd = i == widget.odd.oddIndex;

    var bg = scheme.surfaceContainerHigh;
    var fg = scheme.onSurface;
    if (answered && isOdd) {
      bg = scheme.primaryContainer;
      fg = scheme.onPrimaryContainer;
    } else if (answered && _picked == i) {
      bg = scheme.errorContainer;
      fg = scheme.onErrorContainer;
    }

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: answered ? null : () => _pick(i),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 17),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  card.front,
                  style: TextStyle(
                    fontFamily: AppTheme.bodyFont,
                    fontWeight: FontWeight.w600,
                    fontSize: 18,
                    color: fg,
                  ),
                ),
              ),
              Text(
                card.back,
                style: TextStyle(
                  fontFamily: AppTheme.bodyFont,
                  fontSize: 12.5,
                  color: fg.withValues(alpha: 0.75),
                ),
              ),
              if (answered && isOdd) ...[
                const SizedBox(width: 10),
                Icon(Icons.check_rounded, size: 20, color: fg),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _AssembleExercise extends StatefulWidget {
  final Exercise ex;
  final String languageCode;
  final void Function(bool correct) onAnswered;

  const _AssembleExercise({
    super.key,
    required this.ex,
    required this.languageCode,
    required this.onAnswered,
  });

  @override
  State<_AssembleExercise> createState() => _AssembleExerciseState();
}

class _AssembleExerciseState extends State<_AssembleExercise> {
  late final Assemble? _asm = buildAssemble(widget.ex.card);
  // Индексы слов исходного предложения: в пуле (перемешаны) и уже выбранные.
  late final List<int> _pool;
  final List<int> _chosen = [];
  bool? _correct;

  @override
  void initState() {
    super.initState();
    final n = _asm?.tokens.length ?? 0;
    _pool = [for (var i = 0; i < n; i++) i]..shuffle(Random());
  }

  List<String> get _chosenWords => [for (final i in _chosen) _asm!.tokens[i]];

  void _pick(int i) {
    if (_correct != null) return;
    setState(() {
      _pool.remove(i);
      _chosen.add(i);
    });
  }

  void _unpick(int i) {
    if (_correct != null) return;
    setState(() {
      _chosen.remove(i);
      _pool.add(i);
    });
  }

  void _check() {
    final asm = _asm;
    if (_correct != null || asm == null) return;
    final ok = assembleMatches(_chosenWords, asm.sentence);
    setState(() => _correct = ok);
    HapticFeedback.mediumImpact();
    TtsService.instance.speak(asm.sentence, widget.languageCode);
  }

  void _skip() {
    if (_correct != null) return;
    setState(() => _correct = false);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final asm = _asm;
    if (asm == null) {
      // Подстраховка: карта без пригодного предложения — засчитываем «дальше».
      WidgetsBinding.instance
          .addPostFrameCallback((_) => widget.onAnswered(false));
      return const SizedBox.shrink();
    }
    final answered = _correct != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        Text(
          tr('assemble_prompt'),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: AppTheme.bodyFont,
            fontSize: 13,
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        // Изучаемое слово (тема) — слово + перевод.
        Text(
          '${widget.ex.card.front}  ·  ${widget.ex.card.back}',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: AppTheme.wordFont,
            fontWeight: FontWeight.w700,
            fontSize: 17,
            color: scheme.onSurface,
          ),
        ),
        const SizedBox(height: 16),
        // Область собранного предложения.
        Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 96),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: answered
                ? (_correct!
                    ? scheme.primary.withValues(alpha: 0.12)
                    : scheme.error.withValues(alpha: 0.12))
                : scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(20),
          ),
          child: _chosen.isEmpty
              ? Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '…',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                )
              : Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final i in _chosen)
                      _chip(asm.tokens[i], scheme,
                          onTap: answered ? null : () => _unpick(i),
                          filled: true),
                  ],
                ),
        ),
        if (answered && !_correct!) ...[
          const SizedBox(height: 12),
          Text(
            asm.sentence,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: AppTheme.bodyFont,
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: scheme.primary,
            ),
          ),
        ],
        const SizedBox(height: 16),
        // Пул слов.
        if (!answered)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              for (final i in _pool)
                _chip(asm.tokens[i], scheme, onTap: () => _pick(i)),
            ],
          ),
        const Spacer(),
        if (!answered)
          Row(
            children: [
              // Ширина по надписи, а не доля строки: в трети экрана «Не знаю»
              // ломалось на две строки, а немецкое «Ich weiß nicht» и подавно.
              // Потолок в 42% держит главную кнопку широкой.
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.sizeOf(context).width * 0.42,
                ),
                child: FilledButton.tonal(
                  onPressed: _skip,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      tr('dont_know'),
                      maxLines: 1,
                      softWrap: false,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _pool.isEmpty ? _check : null,
                  child: Text(tr('check')),
                ),
              ),
            ],
          )
        else
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => widget.onAnswered(_correct!),
              child: Text(tr('continue_btn')),
            ),
          ),
      ],
    );
  }

  Widget _chip(String word, ColorScheme scheme,
      {VoidCallback? onTap, bool filled = false}) {
    return Material(
      color: filled ? scheme.primaryContainer : scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Text(
            word,
            style: TextStyle(
              fontFamily: AppTheme.bodyFont,
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: filled ? scheme.onPrimaryContainer : scheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

// ======================= Упражнение: назови конструкцию =======================

/// «Какая это конструкция?» — предложение из СВОЕГО текста и варианты правил.
///
/// Оборот подсвечен: в длинном предложении иначе непонятно, о какой его части
/// спрашивают, и человек отвечает наугад при знании правила.
class _RuleChooseExercise extends StatefulWidget {
  final RuleChoice choice;
  final String ruleCode;
  final String explanation;
  final String languageCode;
  final void Function(bool correct) onAnswered;

  const _RuleChooseExercise({
    super.key,
    required this.choice,
    required this.ruleCode,
    required this.explanation,
    required this.languageCode,
    required this.onAnswered,
  });

  @override
  State<_RuleChooseExercise> createState() => _RuleChooseExerciseState();
}

class _RuleChooseExerciseState extends State<_RuleChooseExercise> {
  int? _picked;
  (int, int)? _span;

  @override
  void initState() {
    super.initState();
    _span = _findSpan();
  }

  /// Границы оборота в примере: гоняем детектор по одному предложению и берём
  /// находку со своим кодом. Хранить границы в карточке незачем — пример
  /// короткий, а правила разбора со временем уточняются.
  (int, int)? _findSpan() {
    final a = TextParse.analyze(widget.choice.sentence, widget.languageCode);
    for (final hit in Constructions.find(a, widget.languageCode)) {
      if (hit.code == widget.ruleCode) return (hit.start, hit.end);
    }
    return null;
  }

  void _pick(int i) {
    if (_picked != null) return;
    setState(() => _picked = i);
    HapticFeedback.selectionClick();
    final correct = i == widget.choice.correctIndex;
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (mounted) widget.onAnswered(correct);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final answered = _picked != null;

    return Column(
      children: [
        const SizedBox(height: 8),
        Text(
          tr('rule_choose_prompt'),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: AppTheme.displayFont,
            fontWeight: FontWeight.w600,
            fontSize: 20,
            color: scheme.onSurface,
          ),
        ),
        const SizedBox(height: 18),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(22),
          ),
          child: _sentence(scheme),
        ),
        const SizedBox(height: 22),
        for (var i = 0; i < widget.choice.options.length; i++) ...[
          _option(i, scheme),
          const SizedBox(height: 10),
        ],
        const Spacer(),
        if (answered && widget.explanation.trim().isNotEmpty)
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: scheme.secondaryContainer,
              borderRadius: BorderRadius.circular(20),
            ),
            padding: const EdgeInsets.fromLTRB(16, 13, 16, 15),
            child: Text(
              widget.explanation,
              style: TextStyle(
                fontFamily: AppTheme.bodyFont,
                fontSize: 15,
                height: 1.35,
                color: scheme.onSecondaryContainer,
              ),
            ),
          ),
      ],
    );
  }

  /// Предложение с выделенным оборотом (шрифт изучаемого слова — как везде,
  /// где человек читает чужой язык).
  Widget _sentence(ColorScheme scheme) {
    final text = widget.choice.sentence;
    final base = TextStyle(
      fontFamily: AppTheme.wordFont,
      fontSize: 19,
      height: 1.4,
      color: scheme.onSurface,
    );
    final span = _span;
    if (span == null) return Text(text, style: base);
    final (start, end) = span;
    return RichText(
      text: TextSpan(
        style: base,
        children: [
          TextSpan(text: text.substring(0, start)),
          TextSpan(
            text: text.substring(start, end),
            style: base.copyWith(
              fontWeight: FontWeight.w700,
              color: scheme.primary,
            ),
          ),
          TextSpan(text: text.substring(end)),
        ],
      ),
    );
  }

  Widget _option(int i, ColorScheme scheme) {
    final answered = _picked != null;
    final isCorrect = i == widget.choice.correctIndex;
    var bg = scheme.surfaceContainerHigh;
    var fg = scheme.onSurface;
    if (answered && isCorrect) {
      bg = scheme.primaryContainer;
      fg = scheme.onPrimaryContainer;
    } else if (answered && _picked == i) {
      bg = scheme.errorContainer;
      fg = scheme.onErrorContainer;
    }
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: answered ? null : () => _pick(i),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.choice.options[i],
                  style: TextStyle(
                    fontFamily: AppTheme.displayFont,
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                    color: fg,
                  ),
                ),
              ),
              if (answered && isCorrect)
                Icon(Icons.check_rounded, size: 20, color: fg),
            ],
          ),
        ),
      ),
    );
  }
}

// ======================= Упражнение: разведи двойников =======================

/// Два слова, которые человек путает, и один перевод.
///
/// Обычно планировщик их РАЗВОДИТ (см. `services/interference.dart`), чтобы
/// пара не портила обе карточки разом. Здесь наоборот: когда оба слова уже
/// знакомы, их показывают рядом — различать похожее нужно учиться отдельно.
class _TwinsExercise extends StatefulWidget {
  final Twins twins;
  final void Function(bool correct) onAnswered;

  const _TwinsExercise({
    super.key,
    required this.twins,
    required this.onAnswered,
  });

  @override
  State<_TwinsExercise> createState() => _TwinsExerciseState();
}

class _TwinsExerciseState extends State<_TwinsExercise> {
  int? _picked;

  void _pick(int i) {
    if (_picked != null) return;
    setState(() => _picked = i);
    HapticFeedback.selectionClick();
    final correct = i == widget.twins.correctIndex;
    Future.delayed(const Duration(milliseconds: 1300), () {
      if (mounted) widget.onAnswered(correct);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final answered = _picked != null;
    final t = widget.twins;

    return Column(
      children: [
        const SizedBox(height: 8),
        Text(
          tr('twins_prompt'),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: AppTheme.bodyFont,
            fontSize: 13,
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          t.prompt,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: AppTheme.displayFont,
            fontWeight: FontWeight.w700,
            fontSize: 26,
            color: scheme.onSurface,
          ),
        ),
        const SizedBox(height: 26),
        for (var i = 0; i < t.options.length; i++) ...[
          _option(i, scheme),
          const SizedBox(height: 12),
        ],
        const Spacer(),
        if (answered)
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: scheme.secondaryContainer,
              borderRadius: BorderRadius.circular(20),
            ),
            padding: const EdgeInsets.fromLTRB(16, 13, 16, 15),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _difference(t.target.front, t.target.back, scheme),
                const SizedBox(height: 6),
                _difference(t.twin.front, t.twin.back, scheme),
              ],
            ),
          ),
      ],
    );
  }

  /// Строка «слово — перевод»: после ответа видно оба значения сразу, ради
  /// этого упражнение и затевалось.
  Widget _difference(String word, String meaning, ColorScheme scheme) => Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: word,
              style: TextStyle(
                fontFamily: AppTheme.wordFont,
                fontWeight: FontWeight.w700,
                color: scheme.onSecondaryContainer,
              ),
            ),
            TextSpan(
              text: ' — $meaning',
              style: TextStyle(
                fontFamily: AppTheme.bodyFont,
                color: scheme.onSecondaryContainer,
              ),
            ),
          ],
        ),
        style: const TextStyle(fontSize: 15, height: 1.35),
      );

  Widget _option(int i, ColorScheme scheme) {
    final answered = _picked != null;
    final isCorrect = i == widget.twins.correctIndex;
    var bg = scheme.surfaceContainerHigh;
    var fg = scheme.onSurface;
    if (answered && isCorrect) {
      bg = scheme.primaryContainer;
      fg = scheme.onPrimaryContainer;
    } else if (answered && _picked == i) {
      bg = scheme.errorContainer;
      fg = scheme.onErrorContainer;
    }
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: answered ? null : () => _pick(i),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
          child: Center(
            child: Text(
              widget.twins.options[i],
              style: TextStyle(
                fontFamily: AppTheme.wordFont,
                fontWeight: FontWeight.w600,
                fontSize: 20,
                color: fg,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
