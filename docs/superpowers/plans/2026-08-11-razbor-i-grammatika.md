# Разбор, грамматика и захват слов — план работ

**Цель:** превратить Fern из «красивого Anki» в инструмент, которым пользуются
каждый день по делу: вставил чужое сообщение — получил разбор по словам и по
грамматике, ответил на него, поймал слово прямо в чужом приложении, а правила
языка выросли из собственных текстов, а не из учебника.

**Почему именно это.** Четыре тестировщика Google Play поставили 8–9 из 10 и
назвали одну причину, почему не десять: грамматики нет. Задел под неё в коде уже
лежит (`sentence`/`example` на карточке, режим «Контекст», теги частей речи из
словаря Moby, лемматизатор), не хватает слоя, который читает предложение
целиком.

**Архитектура.** Ядро разбора не знает про экраны: `TextAnalysis` отдаёт токены с
позициями, леммой, частью речи и статусом по личному словарю, `Constructions`
находит в этих токенах грамматические конструкции. Каталог конструкций лежит
ассетом (`assets/grammar/en.json`) с объяснениями на семь языков интерфейса —
так он не раздувает `strings.dart` и расширяется на новые изучаемые языки файлом.
Правила становятся обычными карточками с `ReviewState`, поэтому FSRS, сессии,
статистика и резервная копия работают без правок.

## Общие ограничения

- Экраны и сервисы на семь языков интерфейса: `ru`/`en` в `strings.dart`,
  остальные пять в `translations.dart`; `test/l10n_coverage_test.dart` стережёт.
- Числа с существительными — только через `trn(base, n)`.
- Офлайн-first: разбор работает без сети. Перевод берётся из выбранного
  движка (`TranslationManager`), его отсутствие не ломает разбор.
- Часть речи для английского берётся из `PosDictionary` (Moby), для остальных
  языков честно остаётся пустой.
- Роль `error` — только настоящие сбои. Метки статуса слов идут на
  `secondaryContainer` / `surfaceContainerHighest` / `tertiaryContainer`.
- Дни считаются через `utils/day.dart`.
- `switch` по `StudyMode`/`ExerciseKind`/`SelectionReason` исчерпывающие: новая
  ветка ломает сборку в нескольких местах, компилятор их перечислит.
- Ветка не заводится: коммиты идут в `main` под `THET1ME-1 <badzoff@gmail.com>`.
- Сборка — один раз в конце, после всех задач.

---

## Задача 1. Ядро разбора текста

**Файлы:** создать `app/lib/services/text_analysis.dart`, тест
`app/test/text_analysis_test.dart`.

**Отдаёт:**

- `enum WordStatus { known, learning, unknown, ignored }` — `ignored` для чисел
  и однобуквенных токенов;
- `class AnalyzedToken { String surface; String lemma; String pos; WordStatus
  status; int start; int end; int sentence; String? cardId; }`;
- `class AnalyzedSentence { String text; int start; int end; }`;
- `class TextAnalysis { List<AnalyzedToken> tokens; List<AnalyzedSentence>
  sentences; int knownTokens; int totalWords; double coverage; List<String>
  unknownWords; }`;
- `TextAnalysis TextParse.analyze(String text, String languageCode)`;
- `List<AnalyzedSentence> TextParse.sentences(String text)`.

**Тест-кейсы:**

1. Позиции токенов совпадают с исходным текстом (`text.substring(start, end) ==
   surface`) — на этом держится подсветка.
2. Разбивка на предложения не режет `Mr.`, `e.g.`, многоточие и цифры с точкой.
3. Слово из словаря опознаётся по основе (`foxes` → карточка `fox`), статус
   `known` при крепкой памяти и `learning` при слабой.
4. Числа и пунктуация получают `ignored` и не портят покрытие.
5. Покрытие считается по токенам с повторами, как в `BookAnalysis`.

## Задача 2. Детектор грамматических конструкций

**Файлы:** создать `app/lib/services/constructions.dart`,
`app/assets/grammar/en.json`, тест `app/test/constructions_test.dart`;
изменить `app/pubspec.yaml` (ассет).

**Отдаёт:**

- `class Construction { String code; String level; String name; String hint;
  List<String> examples; }` — `name`/`hint` уже под язык интерфейса;
- `class ConstructionHit { Construction rule; int sentence; int start; int end;
  String snippet; }`;
- `ConstructionCatalog.instance.ensureLoaded(String languageCode)`;
- `List<Construction> ConstructionCatalog.instance.all(String languageCode)`;
- `List<ConstructionHit> Constructions.find(TextAnalysis a, String
  languageCode)`.

Правила английского покрывают A1–C1: времена группы Simple/Continuous/Perfect
(настоящее, прошедшее, будущее), `going to`, пассив, модальные, условные нулевого
и трёх типов, сравнительная и превосходная степень, герундий против инфинитива,
`there is/are`, `used to`, вопрос и отрицание со вспомогательным глаголом.

**Тест-кейсы:**

1. `I have been waiting` даёт `present_perfect_cont`, а не `present_perfect`
   (длинный шаблон побеждает короткий).
2. `The house was built in 1920` даёт пассив, `He was building` — прошедшее
   продолженное.
3. `If I had known, I would have told you` даёт третий тип условного.
4. Ассет читается, у каждого правила есть перевод на все семь языков (проверка
   идёт по файлу, а не по `strings.dart`).
5. Найденный фрагмент указывает на реальные позиции в тексте.

## Задача 3. Экран «Разбор»

**Файлы:** создать `app/lib/analyze/analyze_screen.dart`,
`app/lib/analyze/token_chips.dart`, тест `app/test/analyze_screen_test.dart`;
изменить `library_screen.dart` (вход), `strings.dart`, `translations.dart`.

Экран: поле ввода с кнопками «Вставить» и «Разобрать», перевод целиком,
кольцо покрытия, список слов чипами по статусу (тап открывает `showWordLookup`),
карточки найденных конструкций с объяснением и кнопкой «Учить правило»,
кнопка «Добавить все незнакомые» с прогрессом. Разобранный кусок сохраняется в
Библиотеку источником формата `snip`, поэтому к нему можно вернуться.

**Тест-кейсы:** разбор показывает слова и статусы; тап по незнакомому слову
открывает лист перевода; повторный разбор того же текста не плодит источники.

## Задача 4. Правила как карточки FSRS

**Файлы:** изменить `models/word_card.dart` (поле `rule`),
`study/study_models.dart` (`StudyMode.grammar`, `ExerciseKind.ruleChoose`,
`buildRuleChoice`), `study/session_screen.dart` (виджет упражнения),
`widgets/study_modes.dart` (плитка); создать `services/grammar_deck.dart`,
тест `app/test/grammar_cards_test.dart`.

Карточка правила: `front` — название конструкции, `back` — объяснение,
`sentence` — пример из собственного текста, `rule` — код конструкции.
Упражнение показывает предложение и просит назвать конструкцию; варианты берутся
из соседних правил того же уровня.

**Тест-кейсы:** карточка правила создаётся один раз на код; упражнение даёт
верный ответ и три правдоподобных отвлекающих; режим влияет на FSRS.

## Задача 5. Экран «Грамматика»

**Файлы:** создать `app/lib/grammar_screen.dart`,
`app/lib/services/construction_stats.dart`, тест
`app/test/construction_stats_test.dart`; изменить `decks_screen.dart` (вход).

`ConstructionStats` считает по источникам Библиотеки, сколько раз конструкция
встретилась и в скольких источниках, и кэширует результат по языку. Экран
показывает уровни A1–C1 столбиками, у каждого правила — встречи, статус памяти
карточки и кнопка «Учить».

## Задача 6. Режим «Ответ»

**Файлы:** создать `app/lib/analyze/reply_screen.dart`,
`app/lib/services/reply_hints.dart`, тест `app/test/reply_hints_test.dart`.

Человек пишет черновик, Fern переводит его на изучаемый язык, разбирает перевод
тем же ядром и показывает: какие слова из перевода уже есть в словаре (можно
использовать смелее), каких нет (добавить карточкой), какие конструкции
использованы. Слова, которые он знает, но не применил, предлагаются подсказкой.

## Задача 7. Fern в меню выделения текста

**Файлы:** изменить `android/app/src/main/AndroidManifest.xml`,
`android/app/src/main/kotlin/.../MainActivity.kt`; создать
`app/lib/services/process_text.dart`, тест
`app/test/process_text_test.dart`.

`ACTION_PROCESS_TEXT` в intent-filter, канал `fern/process_text` отдаёт
выделенный текст во Flutter, короткий текст открывает лист перевода, длинный —
экран разбора.

## Задача 8. Слова-преследователи

**Файлы:** создать `app/lib/services/word_pursuit.dart`, тест
`app/test/word_pursuit_test.dart`; изменить `progress_screen.dart`.

Слово считается преследователем, если оно незнакомо и встречается в двух и более
источниках Библиотеки. Ранжирование — число источников, затем суммарная частота,
затем `WordPriority` (служебные слова и имена собственные отсеиваются).

## Задача 9. Микроповтор в шторке

**Файлы:** изменить `services/notification_service.dart`,
`services/deck_repository.dart` (очередь оценок), `main.dart` (применение
очереди на старте); тест `app/test/quick_review_queue_test.dart`.

Уведомление показывает слово и две кнопки. Ответ ловит фоновый обработчик
(`@pragma('vm:entry-point')`), пишет оценку в очередь `SharedPreferencesAsync`, а
приложение применяет её при первом запуске: писать в SQLite из фонового изолята
нельзя без второго соединения, и очередь честнее.

## Задача 10. Упражнение «Разведи двойников»

**Файлы:** изменить `study/study_models.dart` (`StudyMode.twins`,
`ExerciseKind.twins`, `buildTwins`), `study/session_screen.dart`,
`widgets/study_modes.dart`; тест `app/test/twins_test.dart`.

`Interference.conflict` уже находит пары. Упражнение показывает перевод и два
похожих слова, после ответа объясняет разницу.

## Задача 11. Shadowing

**Файлы:** создать `app/lib/services/voice_recorder.dart`,
`app/lib/widgets/shadow_button.dart`; изменить `pubspec.yaml` (пакет `record`),
`AndroidManifest.xml` и `Info.plist` (микрофон), `study/session_screen.dart`;
тест `app/test/voice_recorder_test.dart`.

Кнопка слушает эталон, записывает голос и проигрывает обе дорожки подряд.
Оценки произношения нет: офлайн её честно не посчитать.

## Задача 12. Локализация, проверка, релиз

Все новые ключи на семь языков, `flutter analyze` = 0, полный набор тестов,
`CHANGELOG.md`, бамп версии в `pubspec.yaml`, сборка и тег.
</content>
</invoke>
