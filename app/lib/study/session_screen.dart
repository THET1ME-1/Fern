import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/strings.dart';
import '../models/deck.dart';
import '../models/fsrs.dart';
import '../models/word_card.dart';
import '../services/deck_repository.dart';
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

  const SessionScreen({
    super.key,
    required this.deck,
    required this.mode,
    required this.cards,
  });

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen>
    with SingleTickerProviderStateMixin {
  final DeckRepository _repo = DeckRepository.instance;
  final SessionBuilder _builder = SessionBuilder();

  late List<Exercise> _queue;
  late List<WordCard> _pool;
  int _index = 0;
  int _answered = 0;
  int _correct = 0;
  bool _logged = false;
  late DateTime _start;

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

  bool get _isSpeed => widget.mode == StudyMode.speed;

  @override
  void initState() {
    super.initState();
    _start = DateTime.now();
    _pool = widget.cards;
    _queue = _builder.build(
      widget.mode,
      widget.cards,
      _start,
      direction: studyDirectionFromIndex(widget.deck.directionIndex),
    );
    if (_isSpeed) {
      _speedCtrl =
          AnimationController(
            vsync: this,
            duration: const Duration(seconds: _speedSeconds),
          )..addStatusListener((s) {
            if (s == AnimationStatus.completed) _onTimeout();
          });
    }
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
      case ExerciseKind.flip:
      case ExerciseKind.type:
        return const _ExData();
    }
  }

  Future<void> _onGraded(Exercise ex, bool correct, Rating rating) async {
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
        ex.card.review.phase = _nextPhase(ex.card.review.phase, correct);
      }
      await _repo.rateCard(ex.card, rating, DateTime.now());
    }

    // В режиме «Учить» неверные карты возвращаются в конец очереди.
    if (!correct && widget.mode == StudyMode.learn) {
      _queue.add(Exercise(ex.card, ex.kind, reversed: ex.reversed));
    }
    _advance();
  }

  LearnPhase _nextPhase(LearnPhase p, bool correct) {
    final base = p == LearnPhase.unseen ? LearnPhase.recognize : p;
    final ni = (correct ? base.index + 1 : base.index - 1).clamp(
      LearnPhase.recognize.index,
      LearnPhase.mastered.index,
    );
    return LearnPhase.values[ni];
  }

  void _advance() {
    if (_index + 1 >= _queue.length) {
      _finish();
    } else {
      setState(() => _index++);
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
    );
    // Захватываем нужное в локальные переменные: колбэк переживёт уничтожение
    // этого SessionScreen (кнопка «Ещё» на экране результатов).
    final deck = widget.deck;
    final mode = widget.mode;
    final repo = _repo;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => ResultsScreen(
          result: result,
          onStudyMore: (resultsContext) async {
            final cards = await repo.cardsForDeck(deck.id);
            if (!resultsContext.mounted) return;
            Navigator.of(resultsContext).pushReplacement(
              MaterialPageRoute(
                builder: (_) =>
                    SessionScreen(deck: deck, mode: mode, cards: cards),
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

    if (_queue.isEmpty) return _emptyState(scheme);

    if (_dataFor != _index) {
      _data = _dataForIndex(_index);
      _dataFor = _index;
      _resolvedIndex = -1; // новый вопрос ещё не разрешён
      if (_isSpeed) _startSpeedCountdown();
    }
    final ex = _queue[_index];
    final progress = _queue.isEmpty ? 0.0 : _index / _queue.length;

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
          title: Text('${_index + 1} / ${_queue.length}'),
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
                : _exerciseWidget(ex, scheme),
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
          onRated: (r) => _onGraded(ex, r != Rating.again, r),
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
  const _ExData({
    this.options = const [],
    this.tfShown = '',
    this.tfIsTrue = true,
  });
}

// ============================ Упражнение: флип-карточка ============================

class _FlipExercise extends StatefulWidget {
  final Exercise ex;
  final String languageCode;
  final Map<Rating, Duration> previews;
  final void Function(Rating) onRated;

  const _FlipExercise({
    super.key,
    required this.ex,
    required this.languageCode,
    required this.previews,
    required this.onRated,
  });

  @override
  State<_FlipExercise> createState() => _FlipExerciseState();
}

class _FlipExerciseState extends State<_FlipExercise> {
  bool _revealed = false;
  bool _done = false;

  void _rate(Rating r) {
    if (_done) return;
    _done = true;
    HapticFeedback.selectionClick();
    widget.onRated(r);
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
                  onTap: () => setState(() => _revealed = true),
                  child: _FlipCard(
                    showBack: _revealed,
                    front: _cardFace(scheme, ex.prompt, null, isFront: true),
                    back: _cardFace(
                      scheme,
                      ex.answer,
                      ex.card.example,
                      isFront: false,
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
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (!_revealed)
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => setState(() => _revealed = true),
              icon: const Icon(Icons.visibility_rounded),
              label: Text(tr('show_answer')),
            ),
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
      ],
    );
  }

  Widget _cardFace(
    ColorScheme scheme,
    String text,
    String? example, {
    required bool isFront,
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

  Widget _rateBtn(
    ColorScheme scheme,
    Rating r,
    String label,
    Color bg,
    Color fg,
  ) {
    final dur = widget.previews[r];
    return Expanded(
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
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
  final void Function(bool correct) onAnswered;

  const _TypeExercise({super.key, required this.ex, required this.onAnswered});

  @override
  State<_TypeExercise> createState() => _TypeExerciseState();
}

class _TypeExerciseState extends State<_TypeExercise> {
  final TextEditingController _controller = TextEditingController();
  bool? _correct;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _check() {
    if (_correct != null) return;
    final ok = answerMatches(_controller.text, widget.ex.answer);
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
    final ex = widget.ex;
    final answered = _correct != null;

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
