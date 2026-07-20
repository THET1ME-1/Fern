import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/strings.dart';
import '../models/deck.dart';
import '../models/fsrs.dart';
import '../models/word_card.dart';
import '../services/auto_grade.dart';
import '../services/card_images.dart';
import '../services/deck_repository.dart';
import '../services/reading_horizon.dart';
import '../services/word_links.dart';
import '../services/tts_service.dart';
import '../theme/app_theme.dart';
import '../widgets/speaker_button.dart';
import 'results_screen.dart';
import 'study_models.dart';

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
  AutoGrade _autoGrade = const AutoGrade(medianMs: AutoGrade.fallbackMedianMs);
  bool _twoButtons = false;

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
    _builder.setReadingHorizon(
      await ReadingHorizon.upcoming(widget.deck.languageCode),
      widget.deck.languageCode,
    );
    final newPerDay = await _repo.newPerDay();
    final introduced = await _repo.newIntroducedToday(_start);
    final maxReviews = await _repo.maxReviews();
    // newPerDay == 0 → без лимита новых.
    final newAllowed =
        newPerDay <= 0 ? 1 << 20 : max(0, newPerDay - introduced);
    final queue = _builder.build(
      widget.mode,
      widget.cards,
      _start,
      newAllowed: newAllowed,
      maxReviews: maxReviews,
      direction: studyDirectionFromIndex(widget.deck.directionIndex),
      language: widget.deck.languageCode,
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
      _shownAt = DateTime.now();
      _ready = true;
    });
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
      case ExerciseKind.flip:
      case ExerciseKind.type:
      case ExerciseKind.cloze:
      case ExerciseKind.spell:
      case ExerciseKind.assemble:
        return const _ExData();
    }
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

  Future<void> _confirmExit() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('exit_session_title')),
        content: Text(tr('exit_session_sub')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('leave')),
          ),
        ],
      ),
    );
    if (leave == true && mounted) {
      _logProgress(); // засчитываем то, что успели пройти
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (!_ready) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_queue.isEmpty) return _emptyState(scheme);

    if (_dataFor != _index) {
      _data = _dataForIndex(_index);
      _dataFor = _index;
      _resolvedIndex = -1; // новый вопрос ещё не разрешён
      if (_isSpeed) _startSpeedCountdown();
    }
    final ex = _queue[_index];
    // Считаем по КАРТАМ, а не по длине очереди: переспрос ошибки вставляет ту же
    // карту ещё раз, и счётчик «3 / 10» на глазах превращался в «3 / 13» — будто
    // работа не убывает, а прибывает.
    final total = _totalCards;
    final done = _doneCards;
    final progress = total == 0 ? 0.0 : done / total;

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
            preferredSize: const Size.fromHeight(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 6,
                  backgroundColor: scheme.surfaceContainerHighest,
                ),
              ),
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
                      Expanded(child: _exerciseWidget(ex, scheme)),
                    ],
                  )
                : Column(
                    children: [
                      _reasonChip(scheme, ex.reason),
                      Expanded(child: _exerciseWidget(ex, scheme)),
                    ],
                  ),
          ),
        ),
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
          onGraded: (r, ms) =>
              _onGraded(ex, r != Rating.again, r, answerMs: ms),
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

  Widget _emptyState(ColorScheme scheme) {
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.task_alt_rounded, size: 72, color: scheme.primary),
                const SizedBox(height: 20),
                Text(
                  tr('nothing_due_title'),
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
                  tr('nothing_due_sub'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: AppTheme.bodyFont,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 24),
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

  const _ExData({
    this.options = const [],
    this.tfShown = '',
    this.tfIsTrue = true,
    this.odd,
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
              fontFamily: AppTheme.displayFont,
              fontWeight: FontWeight.w800,
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
              fontFamily: AppTheme.displayFont,
              fontWeight: FontWeight.w800,
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
                        fontFamily: AppTheme.bodyFont,
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
                        fontFamily: AppTheme.bodyFont,
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

  /// Ввод оценивает себя сам: сверка с эталоном и время набора говорят больше,
  /// чем самооценка после подглядывания в ответ.
  final void Function(Rating rating, int answerMs) onGraded;

  const _TypeExercise({
    super.key,
    required this.ex,
    required this.autoGrade,
    required this.onGraded,
  });

  @override
  State<_TypeExercise> createState() => _TypeExerciseState();
}

class _TypeExerciseState extends State<_TypeExercise> {
  final TextEditingController _controller = TextEditingController();
  final DateTime _shownAt = DateTime.now();
  TypedMatch? _match;
  int _answerMs = 0;

  bool get _correct => _match != TypedMatch.wrong;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _resolve(TypedMatch match) {
    if (_match != null) return;
    setState(() {
      _answerMs =
          DateTime.now().difference(_shownAt).inMilliseconds.clamp(0, 600000);
      _match = match;
    });
    HapticFeedback.mediumImpact();
  }

  void _check() => _resolve(typedQuality(_controller.text, widget.ex.answer));

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
              fontFamily: AppTheme.displayFont,
              fontWeight: FontWeight.w800,
              fontSize: 30,
              color: scheme.onSurface,
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
          onSubmitted: (_) => _check(),
          style: TextStyle(
            fontFamily: AppTheme.bodyFont,
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
              fontFamily: AppTheme.bodyFont,
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
              Expanded(
                child: FilledButton.tonal(
                  onPressed: _skip,
                  child: Text(tr('dont_know')),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
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
              onPressed: () =>
                  widget.onGraded(widget.autoGrade.typed(_match!, _answerMs),
                      _answerMs),
              child: Text(tr('continue_btn')),
            ),
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
              fontFamily: AppTheme.bodyFont,
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
              Expanded(
                child: FilledButton.tonal(
                  onPressed: _skip,
                  child: Text(tr('dont_know')),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
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
                    fontFamily: AppTheme.displayFont,
                    fontWeight: FontWeight.w800,
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
                    fontFamily: AppTheme.displayFont,
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
            fontFamily: AppTheme.bodyFont,
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
              fontFamily: AppTheme.bodyFont,
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
              Expanded(
                child: FilledButton.tonal(
                  onPressed: _skip,
                  child: Text(tr('dont_know')),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
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
            fontFamily: AppTheme.displayFont,
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
              Expanded(
                child: FilledButton.tonal(
                  onPressed: _skip,
                  child: Text(tr('dont_know')),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
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
