import 'locale_controller.dart';
import 'translations.dart';

/// Перевод строки по ключу на текущий язык.
///
/// Базовые ru/en лежат в [_strings]; остальные языки — в [kTranslations]
/// (translations.dart). Если перевода на выбранный язык нет — откатываемся на
/// английский, затем на русский, затем на сам ключ.
String tr(String key) {
  final code = LocaleController.instance.code;
  final extra = kTranslations[code]?[key];
  if (extra != null && extra.isNotEmpty) return extra;
  final entry = _strings[key];
  if (entry == null) return key;
  return entry[code] ?? entry['en'] ?? entry['ru'] ?? key;
}

/// Перевод с подстановкой `{name}` → значение.
String trf(String key, Map<String, Object> params) {
  var s = tr(key);
  params.forEach((k, v) => s = s.replaceAll('{$k}', '$v'));
  return s;
}

/// Выбирает перевод значения карточки (`back`) под текущий язык интерфейса.
///
/// В ассете `back` может быть строкой (легаси-формат, русский) или картой
/// `{код_языка: перевод}`. Порядок отката: язык UI → английский → русский →
/// первое доступное значение.
String localizedBack(Object? back, [String? uiLang]) {
  if (back is String) return back;
  if (back is Map) {
    final lang = uiLang ?? LocaleController.instance.code;
    final v = back[lang] ?? back['en'] ?? back['ru'];
    if (v is String && v.isNotEmpty) return v;
    for (final e in back.values) {
      if (e is String && e.isNotEmpty) return e;
    }
  }
  return '';
}

/// Локализованное имя готовой/дефолтной колоды: если задан [nameKey] и он есть
/// в словаре — через [tr], иначе — литерал [name].
String localizedDeckName({String? nameKey, String? name}) {
  if (nameKey != null && nameKey.isNotEmpty) {
    final t = tr(nameKey);
    if (t != nameKey) return t; // ключ найден в словаре
  }
  return name ?? '—';
}

/// Словарь интерфейсных строк (ru/en). Доп. языки — в translations.dart.
const Map<String, Map<String, String>> _strings = {
  // ----------------------------- Общее -----------------------------
  'cancel': {'ru': 'Отмена', 'en': 'Cancel'},
  'save': {'ru': 'Сохранить', 'en': 'Save'},
  'delete': {'ru': 'Удалить', 'en': 'Delete'},
  'reset': {'ru': 'Сбросить', 'en': 'Reset'},
  'apply': {'ru': 'Применить', 'en': 'Apply'},
  'done': {'ru': 'Готово', 'en': 'Done'},
  'add': {'ru': 'Добавить', 'en': 'Add'},
  'edit': {'ru': 'Изменить', 'en': 'Edit'},
  'close': {'ru': 'Закрыть', 'en': 'Close'},
  'continue_btn': {'ru': 'Дальше', 'en': 'Continue'},
  'start': {'ru': 'Начать', 'en': 'Start'},

  // ----------------------------- Навигация -----------------------------
  'nav_decks': {'ru': 'Колоды', 'en': 'Decks'},
  'nav_progress': {'ru': 'Прогресс', 'en': 'Progress'},
  'nav_settings': {'ru': 'Настройки', 'en': 'Settings'},

  // ----------------------------- Баннер языка / колоды -----------------------------
  'studying': {'ru': 'Изучаю', 'en': 'Studying'},
  'choose_language': {'ru': 'Выбор языка', 'en': 'Choose language'},
  'add_language': {'ru': 'Другой язык', 'en': 'Other language'},
  'language_code_hint': {'ru': 'Код языка (напр. nl)', 'en': 'Language code (e.g. nl)'},
  'no_decks_title': {'ru': 'Пока нет колод', 'en': 'No decks yet'},
  'no_decks_sub': {
    'ru': 'Создайте колоду и наполните её словами',
    'en': 'Create a deck and fill it with words'
  },
  'create_deck': {'ru': 'Новая колода', 'en': 'New deck'},
  'new_deck': {'ru': 'Новая колода', 'en': 'New deck'},
  'edit_deck': {'ru': 'Изменить колоду', 'en': 'Edit deck'},
  'deck_name': {'ru': 'Название колоды', 'en': 'Deck name'},
  'deck_color': {'ru': 'Цвет обложки', 'en': 'Cover color'},
  'deck_shape': {'ru': 'Форма обложки', 'en': 'Cover shape'},
  'deck_direction': {'ru': 'Направление', 'en': 'Direction'},
  'dir_forward': {'ru': 'Слово → перевод', 'en': 'Word → translation'},
  'dir_reverse': {'ru': 'Перевод → слово', 'en': 'Translation → word'},
  'dir_both': {'ru': 'В обе стороны', 'en': 'Both ways'},
  'match_record': {'ru': 'Рекорд: {t} с', 'en': 'Best: {t}s'},
  'match_new_record': {'ru': 'Новый рекорд!', 'en': 'New record!'},
  'delete_deck': {'ru': 'Удалить колоду', 'en': 'Delete deck'},
  'delete_deck_confirm': {
    'ru': 'Удалить колоду и все её карточки?',
    'en': 'Delete the deck and all its cards?'
  },
  'cards_n': {'ru': '{n} карт.', 'en': '{n} cards'},
  'due_n': {'ru': '{n} к повтору', 'en': '{n} due'},
  'new_n': {'ru': '{n} новых', 'en': '{n} new'},
  'all_learned': {'ru': 'Всё повторено', 'en': 'All reviewed'},

  // ----------------------------- Экран колоды: режимы -----------------------------
  'modes_title': {'ru': 'Как учить', 'en': 'Study modes'},
  'mode_learn': {'ru': 'Учить', 'en': 'Learn'},
  'mode_learn_sub': {
    'ru': 'Умный микс: новые + повторы',
    'en': 'Smart mix: new + reviews'
  },
  'mode_flashcards': {'ru': 'Карточки', 'en': 'Flashcards'},
  'mode_flashcards_sub': {'ru': 'Классический повтор', 'en': 'Classic review'},
  'mode_test': {'ru': 'Тест', 'en': 'Test'},
  'mode_test_sub': {'ru': 'Проверь себя', 'en': 'Check yourself'},
  'mode_match': {'ru': 'Подбор', 'en': 'Match'},
  'mode_match_sub': {'ru': 'Соедини пары на скорость', 'en': 'Match pairs fast'},
  'mode_write': {'ru': 'Письмо', 'en': 'Write'},
  'mode_write_sub': {'ru': 'Впиши перевод', 'en': 'Type the translation'},
  'mode_spell': {'ru': 'Диктант', 'en': 'Dictation'},
  'mode_spell_sub': {'ru': 'Слушай и пиши слово', 'en': 'Listen and spell'},
  'mode_assemble': {'ru': 'Собери фразу', 'en': 'Build a phrase'},
  'mode_assemble_sub': {
    'ru': 'Слова в правильном порядке',
    'en': 'Words in the right order'
  },
  'mode_audio': {'ru': 'Аудио', 'en': 'Audio'},
  'mode_audio_sub': {'ru': 'Слушай и отвечай', 'en': 'Listen and answer'},
  'mode_hard': {'ru': 'Трудные слова', 'en': 'Hard words'},
  'mode_hard_sub': {'ru': 'Только сложные карты', 'en': 'Only tricky cards'},
  'mode_speed': {'ru': 'Быстрый повтор', 'en': 'Speed review'},
  'mode_speed_sub': {'ru': 'Короткая разминка', 'en': 'Quick warm-up'},
  'mode_cloze': {'ru': 'Контекст', 'en': 'Context'},
  'mode_cloze_sub': {
    'ru': 'Слово в предложении из книги',
    'en': 'Word in a sentence from a book'
  },
  'mode_cram': {'ru': 'Перед экзаменом', 'en': 'Cram'},
  'mode_cram_sub': {
    'ru': 'Прогон всех карт, интервалы не меняются',
    'en': 'Run all cards, schedule untouched'
  },
  'cloze_prompt': {
    'ru': 'Впишите пропущенное слово',
    'en': 'Fill in the missing word'
  },
  'spell_prompt': {
    'ru': 'Послушайте и впишите слово',
    'en': 'Listen and type the word'
  },
  'assemble_prompt': {
    'ru': 'Соберите предложение из слов',
    'en': 'Put the words in the right order'
  },
  'soon': {'ru': 'Скоро', 'en': 'Soon'},

  // ----------------------------- Экран колоды: карточки -----------------------------
  'cards_section': {'ru': 'Карточки', 'en': 'Cards'},
  'add_card': {'ru': 'Добавить карточку', 'en': 'Add card'},
  'edit_card': {'ru': 'Изменить карточку', 'en': 'Edit card'},
  'card_front': {'ru': 'Слово', 'en': 'Word'},
  'card_back': {'ru': 'Перевод', 'en': 'Translation'},
  'card_example': {'ru': 'Пример (необязательно)', 'en': 'Example (optional)'},
  'translate_action': {'ru': 'Перевести', 'en': 'Translate'},
  'translate_downloading': {
    'ru': 'Загрузка языковой модели…',
    'en': 'Downloading language model…'
  },
  'translate_failed': {'ru': 'Не удалось перевести', 'en': 'Translation failed'},
  'translate_variants': {'ru': 'Варианты', 'en': 'Variants'},
  'delete_card': {'ru': 'Удалить карточку', 'en': 'Delete card'},

  // ----------------------------- Части речи -----------------------------
  'split_by_pos': {
    'ru': 'Разложить по частям речи',
    'en': 'Split by part of speech'
  },
  'split_confirm': {
    'ru': 'Создать раздельные колоды для каждой части речи?',
    'en': 'Create separate decks for each part of speech?'
  },
  'dont_ask_again': {'ru': 'Больше не спрашивать', 'en': "Don't ask again"},
  'pos_split_ask': {
    'ru': 'Спрашивать перед разбивкой',
    'en': 'Ask before splitting'
  },
  'pos_split_ask_sub': {
    'ru': 'Подтверждать создание отдельных колод по частям речи',
    'en': 'Confirm creating separate decks by part of speech'
  },
  'split_by_pos_offer': {
    'ru': 'Разложить {n} слов по частям речи (глаголы, существительные…) в отдельные колоды?',
    'en': 'Split {n} words by part of speech (verbs, nouns…) into separate decks?'
  },
  'split_done': {'ru': 'Готово: {n} колод', 'en': 'Done: {n} decks'},
  'split_none': {
    'ru': 'Не удалось определить части речи',
    'en': "Couldn't detect parts of speech"
  },
  'split_pack': {'ru': '{name} · по типам', 'en': '{name} · by type'},
  'pos_deck_noun': {'ru': 'Существительные', 'en': 'Nouns'},
  'pos_deck_verb': {'ru': 'Глаголы', 'en': 'Verbs'},
  'pos_deck_adj': {'ru': 'Прилагательные', 'en': 'Adjectives'},
  'pos_deck_adv': {'ru': 'Наречия', 'en': 'Adverbs'},
  'pos_deck_pronoun': {'ru': 'Местоимения', 'en': 'Pronouns'},
  'pos_deck_article': {'ru': 'Артикли', 'en': 'Articles'},
  'pos_deck_prep': {'ru': 'Предлоги', 'en': 'Prepositions'},
  'pos_deck_conj': {'ru': 'Союзы', 'en': 'Conjunctions'},
  'pos_deck_num': {'ru': 'Числительные', 'en': 'Numerals'},
  'pos_deck_particle': {'ru': 'Частицы', 'en': 'Particles'},
  'pos_deck_interj': {'ru': 'Междометия', 'en': 'Interjections'},
  'pos_deck_other': {'ru': 'Прочее', 'en': 'Other'},
  'pos_filter_all': {'ru': 'Все', 'en': 'All'},
  'part_of_speech': {'ru': 'Часть речи', 'en': 'Part of speech'},
  'pos_none': {'ru': 'Не указана', 'en': 'None'},
  'pos_short_noun': {'ru': 'сущ.', 'en': 'n.'},
  'pos_short_verb': {'ru': 'гл.', 'en': 'v.'},
  'pos_short_adj': {'ru': 'прил.', 'en': 'adj.'},
  'pos_short_adv': {'ru': 'нареч.', 'en': 'adv.'},
  'pos_short_pronoun': {'ru': 'мест.', 'en': 'pron.'},
  'pos_short_article': {'ru': 'арт.', 'en': 'art.'},
  'pos_short_prep': {'ru': 'предл.', 'en': 'prep.'},
  'pos_short_conj': {'ru': 'союз', 'en': 'conj.'},
  'pos_short_num': {'ru': 'числ.', 'en': 'num.'},
  'pos_short_particle': {'ru': 'част.', 'en': 'part.'},
  'pos_short_interj': {'ru': 'межд.', 'en': 'interj.'},

  // ----------------------------- Перевод и модели -----------------------------
  'providers_title': {'ru': 'Перевод и модели', 'en': 'Translation & models'},
  'providers_sub': {
    'ru': 'Движок перевода, свои серверы',
    'en': 'Translation engine, your servers'
  },
  'providers_intro': {
    'ru': 'Встроенный ML Kit — лёгкий и офлайн. Для качества выше подключите '
        'онлайн-перевод или свой сервер.',
    'en': 'Built-in ML Kit is light and offline. For higher quality add online '
        'translation or your own server.'
  },
  'providers_active': {'ru': 'Активный переводчик', 'en': 'Active translator'},
  'providers_servers': {'ru': 'Свои серверы', 'en': 'Your servers'},
  'providers_add_server': {'ru': 'Добавить сервер', 'en': 'Add server'},
  'providers_edit_server': {'ru': 'Сервер перевода', 'en': 'Translation server'},
  'providers_hint': {
    'ru': 'Свой сервер (Ollama, LibreTranslate, OpenAI-совместимый, DeepL) '
        'работает без Google — полезно, если он недоступен.',
    'en': 'Your own server (Ollama, LibreTranslate, OpenAI-compatible, DeepL) '
        'works without Google — handy when it is blocked.'
  },
  'provider_offline': {'ru': 'Офлайн', 'en': 'Offline'},
  'provider_online': {'ru': 'Онлайн', 'en': 'Online'},
  'provider_endpoint': {'ru': 'Свой сервер', 'en': 'Your server'},
  'provider_local': {'ru': 'Локальная модель', 'en': 'Local model'},
  'provider_mlkit_sub': {
    'ru': 'Лёгкий, офлайн, встроен',
    'en': 'Light, offline, built-in'
  },
  'provider_google_sub': {
    'ru': 'Высокое качество, нужна сеть',
    'en': 'High quality, needs network'
  },
  'server_kind': {'ru': 'Тип сервера', 'en': 'Server type'},
  'server_name': {'ru': 'Название', 'en': 'Name'},
  'server_url': {'ru': 'Адрес (URL)', 'en': 'Address (URL)'},
  'server_key': {'ru': 'Ключ / токен', 'en': 'Key / token'},
  'server_model': {'ru': 'Модель', 'en': 'Model'},
  'server_test': {'ru': 'Проверить', 'en': 'Test'},
  'server_test_ok': {'ru': 'Работает: {res}', 'en': 'Works: {res}'},
  'server_test_fail': {
    'ru': 'Сервер не ответил или ошибка',
    'en': 'No response or error'
  },
  'field_required': {'ru': 'Укажите адрес сервера', 'en': 'Enter server URL'},

  // ----------------------------- Разбор видео -----------------------------
  'video_banner_title': {'ru': 'Разобрать видео', 'en': 'Learn from a video'},
  'video_banner_sub': {
    'ru': 'Слова из субтитров — в колоду',
    'en': 'Turn subtitles into cards'
  },
  'video_import_title': {'ru': 'Видео', 'en': 'Video'},
  'video_import_headline': {
    'ru': 'Учи слова из видео',
    'en': 'Learn words from video'
  },
  'video_import_sub': {
    'ru': 'Вставь ссылку на YouTube — разберём субтитры по словам с переводом '
        'и озвучкой живым голосом.',
    'en': 'Paste a YouTube link — we break subtitles into words with '
        'translation and real-voice audio.'
  },
  'video_url_label': {'ru': 'Ссылка на видео', 'en': 'Video link'},
  'paste': {'ru': 'Вставить', 'en': 'Paste'},
  'video_parse': {'ru': 'Разобрать', 'en': 'Parse'},
  'video_parsing': {'ru': 'Загрузка субтитров…', 'en': 'Loading subtitles…'},
  'video_bad_url': {
    'ru': 'Не похоже на ссылку YouTube',
    'en': 'Not a valid YouTube link'
  },
  'video_no_captions': {
    'ru': 'У видео нет субтитров',
    'en': 'This video has no subtitles'
  },
  'video_network_error': {
    'ru': 'Не удалось загрузить (проверь сеть)',
    'en': 'Could not load (check network)'
  },
  'video_tip_voice': {
    'ru': 'Озвучка живым голосом из видео или роботом',
    'en': 'Audio in the real voice from the video, or a robot'
  },
  'video_tip_tap': {
    'ru': 'Тап по слову — перевод и значения',
    'en': 'Tap a word for translation and senses'
  },
  'video_tip_deck': {
    'ru': 'Сложные слова уходят в колоду на повтор',
    'en': 'Hard words go to a deck for review'
  },
  'translating': {'ru': 'Перевод…', 'en': 'Translating…'},
  'audio_live': {'ru': 'Живой', 'en': 'Real'},
  'audio_robot': {'ru': 'Робот', 'en': 'Robot'},
  'play_word': {'ru': 'Слушать слово', 'en': 'Play word'},
  'add_to_deck': {'ru': 'В колоду', 'en': 'Add to deck'},
  'added': {'ru': 'Добавлено', 'en': 'Added'},
  'already_in_deck': {'ru': 'Уже в колоде', 'en': 'Already added'},
  'video_deck_name': {'ru': 'Из видео', 'en': 'From video'},
  'pick_deck': {'ru': 'Выберите колоду', 'en': 'Choose a deck'},
  'add_new_deck_video': {
    'ru': 'Новая колода «Из видео»',
    'en': 'New "From video" deck'
  },
  'add_new_named_deck': {
    'ru': 'Новая колода «{name}»',
    'en': 'New "{name}" deck'
  },
  'word_added_to': {'ru': 'Добавлено в «{deck}»', 'en': 'Added to "{deck}"'},
  // Настройка добавления слов из видео.
  'add_word_mode': {'ru': 'Добавление слов', 'en': 'Adding words'},
  'add_mode_auto': {'ru': 'Автоматически', 'en': 'Automatically'},
  'add_mode_auto_sub': {
    'ru': 'Сразу в колоду «Из видео»',
    'en': 'Straight to the "From video" deck'
  },
  'add_mode_manual': {'ru': 'Спрашивать колоду', 'en': 'Ask for a deck'},
  'add_mode_manual_sub': {
    'ru': 'Выбирать колоду при разборе',
    'en': 'Pick a deck while parsing'
  },
  'add_mode_remember': {'ru': 'Запомнить выбор', 'en': 'Remember choice'},
  'add_mode_remember_sub': {
    'ru': 'Использовать последнюю колоду',
    'en': 'Reuse the last chosen deck'
  },
  'empty_deck_title': {'ru': 'В колоде нет карточек', 'en': 'No cards yet'},
  'empty_deck_sub': {
    'ru': 'Добавьте слова, чтобы начать учить',
    'en': 'Add words to start learning'
  },
  'quick_add_hint': {
    'ru': 'Списком: «слово — перевод» построчно',
    'en': 'By list: "word — translation" per line'
  },
  'quick_add': {'ru': 'Вставить списком', 'en': 'Paste as list'},
  'quick_add_apply': {'ru': 'Добавить все', 'en': 'Add all'},
  'nothing_to_add': {'ru': 'Нечего добавить', 'en': 'Nothing to add'},
  'added_n_cards': {'ru': 'Добавлено {n} карт.', 'en': 'Added {n} cards'},
  // Поиск / сортировка / статус карты
  'search_cards': {'ru': 'Поиск слова', 'en': 'Search words'},
  'no_matches': {'ru': 'Ничего не найдено', 'en': 'No matches'},
  'sort_by': {'ru': 'Сортировка', 'en': 'Sort'},
  'sort_added': {'ru': 'По добавлению', 'en': 'By date added'},
  'sort_alpha': {'ru': 'По алфавиту', 'en': 'Alphabetical'},
  'sort_status': {'ru': 'По прогрессу', 'en': 'By progress'},
  'sort_due': {'ru': 'Сначала к повтору', 'en': 'Due first'},
  'status_new': {'ru': 'Новое', 'en': 'New'},
  'status_learning': {'ru': 'Учится', 'en': 'Learning'},
  'status_young': {'ru': 'Закрепляется', 'en': 'Growing'},
  'status_mature': {'ru': 'Выучено', 'en': 'Mastered'},
  'due_now': {'ru': 'к повтору', 'en': 'due now'},
  'due_in': {'ru': 'через {t}', 'en': 'in {t}'},
  // Дневная сводка / серия
  'today_title': {'ru': 'Сегодня', 'en': 'Today'},
  'of_goal': {'ru': 'из {n}', 'en': 'of {n}'},
  'goal_done': {'ru': 'Цель дня выполнена', 'en': 'Daily goal done'},
  'streak_suffix': {'ru': 'дн. подряд', 'en': 'day streak'},
  'start_streak': {'ru': 'Начни серию', 'en': 'Start a streak'},
  'reviews_word': {'ru': 'повторов', 'en': 'reviews'},
  // Экран прогресса: активность/статистика
  'activity': {'ru': 'Активность', 'en': 'Activity'},
  'less': {'ru': 'меньше', 'en': 'less'},
  'more': {'ru': 'больше', 'en': 'more'},
  'stat_streak': {'ru': 'Серия', 'en': 'Streak'},
  'stat_accuracy_7d': {'ru': 'Точность 7 дн.', 'en': 'Accuracy 7d'},
  'stat_reviews_total': {'ru': 'Повторов всего', 'en': 'Reviews total'},
  'days_short': {'ru': 'дн.', 'en': 'd'},
  // Достижения
  'achievements': {'ru': 'Достижения', 'en': 'Achievements'},
  'ach_earned': {'ru': '{n} из {m}', 'en': '{n} of {m}'},
  'ach_first': {'ru': 'Первые шаги', 'en': 'First steps'},
  'ach_first_desc': {'ru': 'Сделай первый повтор', 'en': 'Do your first review'},
  'ach_warmup': {'ru': 'Разминка', 'en': 'Warm-up'},
  'ach_worker': {'ru': 'Труженик', 'en': 'Hard worker'},
  'ach_marathon': {'ru': 'Марафонец', 'en': 'Marathoner'},
  'ach_desc_reviews': {'ru': '{n} повторов', 'en': '{n} reviews'},
  'ach_streak3': {'ru': 'В ритме', 'en': 'In rhythm'},
  'ach_streak7': {'ru': 'Неделя силы', 'en': 'Week of power'},
  'ach_streak30': {'ru': 'Несокрушимый', 'en': 'Unstoppable'},
  'ach_desc_streak': {'ru': '{n} дн. подряд', 'en': '{n}-day streak'},
  'ach_hello': {'ru': 'Знакомство', 'en': 'Getting started'},
  'ach_vocab': {'ru': 'Словарный запас', 'en': 'Vocabulary'},
  'ach_desc_seen': {'ru': 'Открой {n} слов', 'en': 'Discover {n} words'},
  'ach_ten': {'ru': 'Первая десятка', 'en': 'First ten'},
  'ach_fifty': {'ru': 'Полсотни', 'en': 'Half a hundred'},
  'ach_polyglot': {'ru': 'Полиглот', 'en': 'Polyglot'},
  'ach_desc_mastered': {'ru': 'Выучи {n} слов', 'en': 'Master {n} words'},
  // Готовые колоды
  'starter_decks': {'ru': 'Готовые колоды', 'en': 'Ready-made decks'},
  'starter_decks_sub': {
    'ru': 'Добавьте набор слов и начните сразу',
    'en': 'Add a word pack and start right away'
  },
  'starter_none': {
    'ru': 'Для этого языка пока нет готовых колод',
    'en': 'No ready-made decks for this language yet'
  },
  'words_n': {'ru': '{n} слов', 'en': '{n} words'},
  'starter_added': {'ru': 'Колода добавлена', 'en': 'Deck added'},
  'added_label': {'ru': 'Добавлено', 'en': 'Added'},
  // Озвучка / аудио-режим
  'listen': {'ru': 'Прослушать', 'en': 'Listen'},
  'listen_prompt': {'ru': 'Прослушайте и выберите перевод',
      'en': 'Listen and choose the translation'},
  'tap_to_replay': {'ru': 'Нажмите, чтобы повторить', 'en': 'Tap to replay'},
  // Напоминания
  'reminders': {'ru': 'Напоминания', 'en': 'Reminders'},
  'daily_reminder': {'ru': 'Ежедневное напоминание', 'en': 'Daily reminder'},
  'daily_reminder_sub': {
    'ru': 'Мягко напомним позаниматься',
    'en': 'A gentle nudge to study'
  },
  'reminder_time': {'ru': 'Время напоминания', 'en': 'Reminder time'},
  'reminder_push_title': {'ru': 'Пора учить слова 🌿', 'en': 'Time to learn 🌿'},
  'reminder_push_body': {
    'ru': 'Загляни в Fern и повтори слова дня',
    'en': "Open Fern and review today's words"
  },
  'notifications_blocked': {
    'ru': 'Уведомления запрещены в настройках телефона',
    'en': 'Notifications are blocked in system settings'
  },
  // Обновление приложения
  // Онбординг
  'onb_welcome': {'ru': 'Добро пожаловать', 'en': 'Welcome'},
  'onb_tagline': {
    'ru': 'Учи слова красиво и легко',
    'en': 'Learn words beautifully'
  },
  'onb_pick_lang': {'ru': 'Что хочешь учить?', 'en': 'What do you want to learn?'},
  'onb_start': {'ru': 'Начать', 'en': 'Get started'},
  'check_updates': {'ru': 'Проверить обновления', 'en': 'Check for updates'},
  'checking_updates': {'ru': 'Проверяем обновления…', 'en': 'Checking for updates…'},
  'up_to_date': {'ru': 'У вас последняя версия', 'en': "You're up to date"},
  'update_available': {'ru': 'Доступно обновление', 'en': 'Update available'},
  'update_new_version': {'ru': 'Новая: {v}', 'en': 'New: {v}'},
  'update_current_version': {'ru': 'у вас: {v}', 'en': 'yours: {v}'},
  'update_whats_new': {'ru': 'Что нового', 'en': "What's new"},
  'update_now': {'ru': 'Обновить', 'en': 'Update'},
  'update_downloading': {'ru': 'Загрузка… {p}%', 'en': 'Downloading… {p}%'},
  'update_installing': {'ru': 'Запуск установки…', 'en': 'Starting install…'},
  'update_failed': {
    'ru': 'Не удалось обновить. Откройте релиз на GitHub и скачайте вручную.',
    'en': 'Update failed. Open the release on GitHub and download manually.'
  },
  'update_open_github': {'ru': 'Открыть на GitHub', 'en': 'Open on GitHub'},
  'update_later': {'ru': 'Позже', 'en': 'Later'},

  // ----------------------------- Упражнения / повтор -----------------------------
  'show_answer': {'ru': 'Показать ответ', 'en': 'Show answer'},
  'rate_again': {'ru': 'Не помню', 'en': 'Again'},
  'rate_hard': {'ru': 'Трудно', 'en': 'Hard'},
  'rate_good': {'ru': 'Хорошо', 'en': 'Good'},
  'rate_easy': {'ru': 'Легко', 'en': 'Easy'},
  'dont_know': {'ru': 'Не знаю', 'en': "Don't know"},
  'choose_translation': {'ru': 'Выберите перевод', 'en': 'Choose the translation'},
  'choose_word': {'ru': 'Выберите слово', 'en': 'Choose the word'},
  'type_answer': {'ru': 'Введите перевод', 'en': 'Type the translation'},
  'type_word': {'ru': 'Введите слово', 'en': 'Type the word'},
  'check': {'ru': 'Проверить', 'en': 'Check'},
  'correct': {'ru': 'Верно!', 'en': 'Correct!'},
  'incorrect': {'ru': 'Неверно', 'en': 'Incorrect'},
  'answer_was': {'ru': 'Ответ: {a}', 'en': 'Answer: {a}'},
  'true_false_q': {'ru': 'Это верный перевод?', 'en': 'Is this the correct translation?'},
  'true_label': {'ru': 'Верно', 'en': 'True'},
  'false_label': {'ru': 'Неверно', 'en': 'False'},
  'match_hint': {'ru': 'Соедините пары', 'en': 'Match the pairs'},
  'assemble_hint': {'ru': 'Соберите перевод', 'en': 'Assemble the translation'},
  'exit_session_title': {'ru': 'Выйти из сессии?', 'en': 'Leave the session?'},
  'exit_session_sub': {
    'ru': 'Прогресс сессии не сохранится',
    'en': 'Session progress will be lost'
  },
  'leave': {'ru': 'Выйти', 'en': 'Leave'},

  // ----------------------------- Результаты -----------------------------
  'session_done': {'ru': 'Сессия завершена', 'en': 'Session complete'},
  'nothing_due_title': {'ru': 'Пока нечего повторять', 'en': 'Nothing to review'},
  'nothing_due_sub': {
    'ru': 'Возвращайтесь позже или добавьте новые слова',
    'en': 'Come back later or add new words'
  },
  'res_reviewed': {'ru': 'Повторено', 'en': 'Reviewed'},
  'res_accuracy': {'ru': 'Точность', 'en': 'Accuracy'},
  'res_time': {'ru': 'Время', 'en': 'Time'},
  'res_score': {'ru': 'очков', 'en': 'points'},
  'res_correct': {'ru': 'Верно', 'en': 'Correct'},
  'back_to_deck': {'ru': 'К колоде', 'en': 'Back to deck'},
  'study_more': {'ru': 'Ещё сессия', 'en': 'Study more'},

  // ----------------------------- Прогресс -----------------------------
  'progress_title': {'ru': 'Прогресс', 'en': 'Progress'},
  'streak': {'ru': 'Серия', 'en': 'Streak'},
  'streak_days': {'ru': '{n} дн. подряд', 'en': '{n}-day streak'},
  'goal_today': {'ru': 'Цель на сегодня', 'en': "Today's goal"},
  'reviews_today': {'ru': 'Повторов сегодня', 'en': 'Reviews today'},
  'daily_goal': {'ru': 'Цель в день', 'en': 'Daily goal'},
  'leech_hint': {
    'ru': 'Часто забывается — добавьте пример или мнемонику',
    'en': 'Often forgotten — add an example or mnemonic'
  },
  'new_per_day': {'ru': 'Новых в день', 'en': 'New per day'},
  'new_per_day_sub': {
    'ru': 'Сколько новых слов вводить (0 — без лимита)',
    'en': 'How many new words to introduce (0 — no limit)'
  },
  'max_reviews': {'ru': 'Повторов за раз', 'en': 'Reviews per session'},
  'max_reviews_sub': {
    'ru': 'Потолок повторов в сессии — без «лавины»',
    'en': 'Cap on reviews per session — no avalanche'
  },
  'retention_target': {'ru': 'Целевое удержание', 'en': 'Target retention'},
  'retention_sub': {
    'ru': 'Выше — повторов больше, но помните лучше',
    'en': 'Higher — more reviews, better recall'
  },
  'optimize_fsrs': {'ru': 'Оптимизация FSRS', 'en': 'Optimize FSRS'},
  'optimize_run': {'ru': 'Оптимизировать', 'en': 'Optimize'},
  'optimize_active': {
    'ru': 'Используются ваши персональные веса',
    'en': 'Using your personal weights'
  },
  'optimize_progress': {
    'ru': 'Повторов накоплено: {n} / {need}',
    'en': 'Reviews collected: {n} / {need}'
  },
  'optimize_done': {
    'ru': 'Готово. Ваше удержание ≈ {r}%',
    'en': 'Done. Your retention ≈ {r}%'
  },
  'optimize_need_more': {
    'ru': 'Пока мало данных — позанимайтесь ещё',
    'en': 'Not enough data yet — keep studying'
  },
  'optimize_reset_done': {
    'ru': 'Вернули стандартные веса',
    'en': 'Reset to default weights'
  },
  'cards_total': {'ru': 'Всего карточек', 'en': 'Total cards'},
  'stat_new': {'ru': 'Новые', 'en': 'New'},
  'stat_learning': {'ru': 'Учатся', 'en': 'Learning'},
  'stat_mature': {'ru': 'Выучено', 'en': 'Mature'},
  'stat_due': {'ru': 'К повтору', 'en': 'Due'},
  'best_streak': {'ru': 'Рекорд серии', 'en': 'Best streak'},
  'days_studied': {'ru': 'Дней занятий', 'en': 'Days studied'},
  'reviews_per_day': {'ru': 'Повторов/день', 'en': 'Reviews/day'},
  'mastered_pct': {'ru': 'Выучено', 'en': 'Mastered'},
  'vocabulary': {'ru': 'Словарь', 'en': 'Vocabulary'},
  'by_pos': {'ru': 'По частям речи', 'en': 'By part of speech'},
  'weekly_reviews': {'ru': 'Повторы за 2 недели', 'en': 'Reviews · 14 days'},
  'by_language': {'ru': 'По языкам', 'en': 'By language'},
  'reading_stats': {'ru': 'Чтение', 'en': 'Reading'},
  'stat_read_time': {'ru': 'Время чтения', 'en': 'Reading time'},
  'stat_read_speed': {'ru': 'Слов/мин', 'en': 'Words/min'},
  'stat_books_read': {'ru': 'Книг прочитано', 'en': 'Books read'},
  'stat_books_reading': {'ru': 'В процессе', 'en': 'In progress'},
  'read_min': {'ru': '{m} мин', 'en': '{m} min'},
  'read_hr': {'ru': '{h} ч', 'en': '{h} h'},
  'read_hr_min': {'ru': '{h} ч {m} мин', 'en': '{h}h {m}m'},
  'forecast': {'ru': 'Нагрузка на неделю', 'en': 'Week forecast'},
  'hardest_words': {'ru': 'Трудные слова', 'en': 'Hardest words'},
  'no_data': {'ru': 'Пока нет данных', 'en': 'No data yet'},
  'overview': {'ru': 'Обзор', 'en': 'Overview'},

  // ----------------------------- Настройки -----------------------------
  'settings_title': {'ru': 'Настройки', 'en': 'Settings'},
  'appearance': {'ru': 'Внешний вид', 'en': 'Appearance'},
  'language': {'ru': 'Язык интерфейса', 'en': 'App language'},
  'theme_mode': {'ru': 'Тема', 'en': 'Theme'},
  'theme_light': {'ru': 'Светлая', 'en': 'Light'},
  'theme_dark': {'ru': 'Тёмная', 'en': 'Dark'},
  'theme_system': {'ru': 'Системная', 'en': 'System'},
  'theme_auto': {'ru': 'Авто (по времени)', 'en': 'Auto (by time)'},
  'dynamic_color': {'ru': 'Material You', 'en': 'Material You'},
  'dynamic_color_sub': {
    'ru': 'Цвет из обоев системы (Android 12+)',
    'en': 'Color from system wallpaper (Android 12+)'
  },
  'amoled': {'ru': 'AMOLED-чёрный', 'en': 'AMOLED black'},
  'amoled_sub': {
    'ru': 'Чистый чёрный фон в тёмной теме',
    'en': 'Pure black background in dark theme'
  },
  'theme_color': {'ru': 'Цвет оформления', 'en': 'Theme color'},
  'theme_color_default': {'ru': 'Зелёный (стандартный)', 'en': 'Green (default)'},
  'study': {'ru': 'Обучение', 'en': 'Studying'},
  'data': {'ru': 'Данные', 'en': 'Data'},
  'export_vocab': {'ru': 'Экспорт словаря', 'en': 'Export vocabulary'},
  'export_done': {'ru': 'Экспортировано {n} слов', 'en': 'Exported {n} words'},
  'export_empty': {'ru': 'Словарь пуст', 'en': 'Vocabulary is empty'},
  'fmt_csv_sub': {'ru': 'Excel, Google Таблицы, Quizlet', 'en': 'Excel, Google Sheets, Quizlet'},
  'fmt_anki_sub': {'ru': 'Импорт в Anki и Quizlet', 'en': 'Import into Anki and Quizlet'},
  'fmt_json_sub': {'ru': 'Универсальный формат', 'en': 'Universal format'},
  'fmt_list': {'ru': 'Список слов', 'en': 'Word list'},
  'fmt_list_sub': {'ru': 'Только слова, по одному в строке', 'en': 'Words only, one per line'},
  'import_deck': {'ru': 'Импорт колоды', 'en': 'Import deck'},
  'import_deck_sub': {'ru': 'Anki .apkg, CSV, TSV', 'en': 'Anki .apkg, CSV, TSV'},
  'importing': {'ru': 'Импортируем…', 'en': 'Importing…'},
  'import_done': {
    'ru': 'Импортировано {n} карт. в «{name}»',
    'en': 'Imported {n} cards into "{name}"'
  },
  'import_unsupported': {
    'ru': 'Новый формат .apkg не поддержан. Экспортируйте из Anki в CSV или в старый формат.',
    'en': 'New .apkg format is unsupported. Export from Anki as CSV or an older format.'
  },
  'import_empty': {'ru': 'Нечего импортировать', 'en': 'Nothing to import'},
  'import_failed': {'ru': 'Не удалось импортировать', 'en': 'Import failed'},
  'create_backup': {'ru': 'Создать резервную копию', 'en': 'Create backup'},
  'restore_backup': {'ru': 'Восстановить из копии', 'en': 'Restore from backup'},
  'backup_done': {'ru': 'Копия создана', 'en': 'Backup created'},
  'backup_failed': {
    'ru': 'Не удалось создать копию',
    'en': 'Backup failed'
  },
  'export_failed': {
    'ru': 'Не удалось экспортировать',
    'en': 'Export failed'
  },
  'restore_done': {'ru': 'Данные восстановлены', 'en': 'Data restored'},
  'restore_failed': {'ru': 'Не удалось восстановить', 'en': 'Restore failed'},
  'wipe_data': {'ru': 'Удалить все данные', 'en': 'Delete all data'},
  'wipe_data_sub': {
    'ru': 'Колоды, слова, книги, статистику — как после установки',
    'en': 'Decks, words, books, stats — like a fresh install'
  },
  'wipe_data_confirm': {
    'ru': 'Все колоды, слова, прогресс, книги и настройки будут удалены '
        'безвозвратно. Сделайте резервную копию заранее.',
    'en': 'All decks, words, progress, books and settings will be erased '
        'permanently. Make a backup first.'
  },
  'wipe_data_btn': {'ru': 'Удалить всё', 'en': 'Delete all'},
  'wipe_data_done': {'ru': 'Все данные удалены', 'en': 'All data deleted'},
  'restore_mode_title': {'ru': 'Как восстановить?', 'en': 'How to restore?'},
  'restore_mode_replace': {'ru': 'Заменить всё', 'en': 'Replace all'},
  'restore_mode_replace_sub': {
    'ru': 'Текущие данные заменятся содержимым копии',
    'en': 'Current data is replaced with the backup'
  },
  'restore_mode_merge': {'ru': 'Объединить', 'en': 'Merge'},
  'restore_mode_merge_sub': {
    'ru': 'Добавит недостающие колоды и слова, прогресс сохранится',
    'en': 'Adds missing decks and words, keeps your progress'
  },
  'about': {'ru': 'О приложении', 'en': 'About'},
  'version': {'ru': 'Версия', 'en': 'Version'},

  // ----------------------------- Библиотека -----------------------------
  'library_title': {'ru': 'Библиотека', 'en': 'Library'},
  'library_recent': {'ru': 'Недавнее', 'en': 'Recent'},
  'reading_now': {'ru': 'Читаю сейчас', 'en': 'Reading now'},
  'library_search_hint': {
    'ru': 'Поиск: название, автор, жанр…',
    'en': 'Search: title, author, genre…'
  },
  'sort_recent': {'ru': 'Сначала новые', 'en': 'Newest first'},
  'sort_progress': {'ru': 'По прогрессу', 'en': 'By progress'},
  'sort_known': {'ru': 'По знакомости', 'en': 'By familiarity'},
  'library_video_sub': {
    'ru': 'Слова из субтитров',
    'en': 'Words from subtitles'
  },
  'library_add_book': {'ru': 'Добавить книгу', 'en': 'Add a book'},
  'library_book_sub': {'ru': 'Читай и учи слова', 'en': 'Read and learn words'},
  'book_import_failed': {
    'ru': 'Не удалось открыть файл',
    'en': 'Could not open the file'
  },
  'source_open_failed': {
    'ru': 'Не удалось открыть источник',
    'en': 'Could not open this source'
  },
  'source_kind_video': {'ru': 'Видео', 'en': 'Video'},
  'source_kind_book': {'ru': 'Книга', 'en': 'Book'},
  'source_words_added': {'ru': '{n} слов', 'en': '{n} words'},
  'library_empty_title': {
    'ru': 'Здесь появятся ваши материалы',
    'en': 'Your materials will appear here'
  },
  'library_empty_sub': {
    'ru': 'Разберите видео или добавьте книгу — новые слова уйдут в колоды на '
        'повтор.',
    'en': 'Parse a video or add a book — new words go to your decks for review.'
  },

  // ----------------------------- Читалка книг -----------------------------
  'book_deck_name': {'ru': 'Из книги', 'en': 'From book'},
  'bookmark': {'ru': 'Закладка', 'en': 'Bookmark'},
  'bookmarks': {'ru': 'Закладки', 'en': 'Bookmarks'},
  'bookmark_added': {'ru': 'Закладка добавлена', 'en': 'Bookmark added'},
  'bookmark_removed': {'ru': 'Закладка удалена', 'en': 'Bookmark removed'},
  'bookmarks_empty': {'ru': 'Пока нет закладок', 'en': 'No bookmarks yet'},
  'chapters': {'ru': 'Главы', 'en': 'Chapters'},
  'chapter_new_words': {'ru': '{n} новых', 'en': '{n} new'},
  'book_finished': {'ru': 'Прочитано', 'en': 'Finished'},
  'read_aloud': {'ru': 'Читать вслух', 'en': 'Read aloud'},
  'tts_unavailable': {
    'ru': 'Озвучка недоступна для этого языка',
    'en': 'Speech is unavailable for this language'
  },
  'reader_settings': {'ru': 'Оформление', 'en': 'Reading'},
  'reader_mode': {'ru': 'Режим чтения', 'en': 'Reading mode'},
  'read_progress': {'ru': 'прочитано {p}%', 'en': '{p}% read'},
  'reader_mode_scroll': {'ru': 'Прокрутка', 'en': 'Scroll'},
  'reader_mode_paged': {'ru': 'Страницы', 'en': 'Pages'},
  'highlight_words': {'ru': 'Подсветка слов', 'en': 'Highlight words'},
  'highlight_known': {'ru': 'Знакомые', 'en': 'Known'},
  'highlight_unknown': {'ru': 'Незнакомые', 'en': 'Unknown'},
  'highlight_off': {'ru': 'Выкл', 'en': 'Off'},
  'reader_theme': {'ru': 'Тема страницы', 'en': 'Page theme'},
  'reader_font_size': {'ru': 'Размер шрифта', 'en': 'Font size'},
  'reader_line_height': {'ru': 'Межстрочный интервал', 'en': 'Line spacing'},
  'reader_font': {'ru': 'Шрифт', 'en': 'Font'},
  'reader_font_serif': {'ru': 'С засечками', 'en': 'Serif'},
  'reader_font_sans': {'ru': 'Без засечек', 'en': 'Sans'},
  'word_already_known': {'ru': 'Уже в словаре', 'en': 'Already in your words'},

  // ----------------------------- Страница книги -----------------------------
  'read_continue': {'ru': 'Продолжить чтение', 'en': 'Continue reading'},
  'read_start': {'ru': 'Читать', 'en': 'Read'},
  'book_edit': {'ru': 'Изменить книгу', 'en': 'Edit book'},
  'book_delete': {'ru': 'Удалить книгу', 'en': 'Delete book'},
  'book_delete_confirm': {
    'ru': 'Удалить книгу и её текст? Слова в колодах останутся.',
    'en': 'Delete the book and its text? Words in your decks are kept.'
  },
  'book_title_label': {'ru': 'Название', 'en': 'Title'},
  'book_author': {'ru': 'Автор', 'en': 'Author'},
  'book_language': {'ru': 'Язык книги', 'en': 'Book language'},
  'book_unknown_author': {'ru': 'Автор не указан', 'en': 'Unknown author'},
  'book_description': {'ru': 'Описание', 'en': 'Description'},
  'book_genres': {'ru': 'Жанры', 'en': 'Genres'},
  'book_tags': {'ru': 'Теги', 'en': 'Tags'},
  'chips_add_hint': {'ru': 'Введите и Enter', 'en': 'Type and press Enter'},
  'book_about': {'ru': 'О книге', 'en': 'About the book'},
  'book_no_text': {
    'ru': 'Текст книги недоступен',
    'en': 'Book text is unavailable'
  },
  'book_reading_progress': {'ru': 'Прогресс чтения', 'en': 'Reading progress'},
  'book_bookmarks_n': {'ru': 'Закладок: {n}', 'en': 'Bookmarks: {n}'},
  'book_analysis_title': {'ru': 'Анализ слов', 'en': 'Word analysis'},
  'analyzing': {'ru': 'Анализируем…', 'en': 'Analyzing…'},
  'book_coverage': {
    'ru': 'Знакомо {p}% текста',
    'en': 'You know {p}% of the text'
  },
  'book_coverage_sub': {
    'ru': 'Доля всех слов книги (с повторами), которые вы уже знаете',
    'en': "Share of all the book's running words you already know"
  },
  'analysis_known': {'ru': 'Помнит', 'en': 'Knows'},
  'analysis_known_sub': {'ru': 'Крепко в памяти', 'en': 'Solid in memory'},
  'analysis_learning': {'ru': 'Учит', 'en': 'Learning'},
  'analysis_learning_sub': {'ru': 'В словаре, слабо', 'en': 'In dictionary, weak'},
  'analysis_unknown': {'ru': 'Не знает', 'en': 'New'},
  'analysis_unknown_sub': {'ru': 'Ещё нет в словаре', 'en': 'Not in dictionary'},
  'book_vocab_line': {
    'ru': 'Уникальных слов: {unique}. В словаре: {indict} ({share}%).',
    'en': 'Unique words: {unique}. In your dictionary: {indict} ({share}%).'
  },
  'book_study_first': {'ru': 'Учить в первую очередь', 'en': 'Learn these first'},
  'book_study_first_sub': {
    'ru': 'Самые частые незнакомые слова — тап, чтобы добавить',
    'en': 'Most frequent new words — tap to add'
  },
  'select': {'ru': 'Выбрать', 'en': 'Select'},
  'select_all': {'ru': 'Выбрать все', 'en': 'Select all'},
  'n_selected': {'ru': 'Выбрано: {n}', 'en': '{n} selected'},
  'delete_n_decks': {'ru': 'Удалить {n} колод?', 'en': 'Delete {n} decks?'},
  'delete_n_decks_confirm': {
    'ru': 'Колоды и все их карточки будут удалены.',
    'en': 'The decks and all their cards will be deleted.'
  },
  'tap_to_select': {'ru': 'Отметьте слова', 'en': 'Tap words to select'},
  'add_selected_n': {'ru': 'Добавить ({n})', 'en': 'Add ({n})'},
  'add_all_n': {'ru': 'Добавить все ({n})', 'en': 'Add all ({n})'},
  'batch_adding': {'ru': 'Добавляем {i} / {n}', 'en': 'Adding {i} / {n}'},

  // ----------------------------- Паки -----------------------------
  'deck_pack': {'ru': 'Пак', 'en': 'Pack'},
  'pack_none': {'ru': 'Без пака', 'en': 'No pack'},
  'pack_new': {'ru': 'Новый пак', 'en': 'New pack'},
  'new_deck_in_pack': {'ru': 'Новая колода в паке', 'en': 'New deck in pack'},
  'source_pack_fallback': {'ru': 'Материал', 'en': 'Material'},
  'deck_words_default': {'ru': 'Слова', 'en': 'Words'},
  'pack_name': {'ru': 'Название пака', 'en': 'Pack name'},
  'pack_color': {'ru': 'Цвет пака', 'en': 'Pack color'},
  'create_pack': {'ru': 'Новый пак', 'en': 'New pack'},
  'create_pack_sub': {
    'ru': 'Папка из нескольких колод',
    'en': 'A folder of several decks'
  },
  'create_deck_sub': {'ru': 'Одна колода со словами', 'en': 'One deck of words'},
  'open_pack': {'ru': 'Открыть', 'en': 'Open'},
  'edit_pack': {'ru': 'Изменить пак', 'en': 'Edit pack'},
  'delete_pack': {'ru': 'Удалить пак', 'en': 'Delete pack'},
  'delete_pack_keeps_decks': {
    'ru': 'Колоды внутри сохранятся',
    'en': 'Its decks will be kept'
  },
  'delete_pack_confirm': {
    'ru': 'Удалить пак? Колоды внутри останутся.',
    'en': 'Delete the pack? Its decks will be kept.'
  },
  'remove_from_pack': {'ru': 'Убрать из пака', 'en': 'Remove from pack'},
  'add_existing_decks': {
    'ru': 'Добавить существующие колоды',
    'en': 'Add existing decks'
  },
  'manage_decks': {'ru': 'Колоды в паке', 'en': 'Decks in the folder'},
  'manage_decks_sub': {
    'ru': 'Отметьте, какие колоды входят в пак. Снятие галочки убирает колоду '
        'из папки — сама колода и её карточки остаются.',
    'en': 'Check which decks belong to the folder. Unchecking removes the deck '
        'from the folder — the deck and its cards are kept.'
  },
  'deck_in_other_pack': {'ru': 'в другом паке', 'en': 'in another folder'},
  'no_free_decks': {
    'ru': 'Нет колод для этого языка',
    'en': 'No decks for this language'
  },
  'decks_n': {'ru': '{n} колод', 'en': '{n} decks'},

  // ----------------------------- Главный экран (настройки) -----------------------------
  'home_screen': {'ru': 'Главный экран', 'en': 'Home screen'},
  'show_video_banner': {
    'ru': 'Баннер «Разобрать видео»',
    'en': '"Learn from a video" banner'
  },
  'show_video_banner_sub': {
    'ru': 'Показывать на главном экране',
    'en': 'Show it on the home screen'
  },
  'search_language': {'ru': 'Поиск языка', 'en': 'Search language'},

  // ----------------------- Готовые/дефолтные колоды: названия ---------------------
  'seed_deck_first_words': {'ru': 'Первые слова', 'en': 'First words'},
  'seed_deck_verbs': {'ru': 'Глаголы', 'en': 'Verbs'},
  'seed_deck_food': {'ru': 'Еда и напитки', 'en': 'Food & drinks'},
  'seed_deck_clothes': {'ru': 'Одежда', 'en': 'Clothes'},

  // ----------------------------- Прочие строки интерфейса -------------------------
  'custom_color': {'ru': 'Свой цвет', 'en': 'Custom color'},
  'quick_add_example': {
    'ru': 'hello — привет\nwater — вода',
    'en': 'hello — hola\nwater — agua'
  },
  'dur_min_sec': {'ru': '{m} мин {s} с', 'en': '{m} min {s} s'},
  'dur_sec': {'ru': '{s} с', 'en': '{s} s'},
  'forecast_today': {'ru': 'Сег', 'en': 'Now'},
  'notif_channel_name': {
    'ru': 'Ежедневные напоминания',
    'en': 'Daily reminders'
  },
  'notif_channel_desc': {
    'ru': 'Напоминание позаниматься в Fern',
    'en': 'A reminder to study in Fern'
  },

  // ----------------------- Видео-страница и проверка языка ------------------------
  'lang_check_title': {'ru': 'Проверьте язык', 'en': 'Check the language'},
  'lang_detect_warning': {
    'ru': 'Язык определён автоматически и может быть неверным — проверьте его '
        'перед изучением.',
    'en': 'The language was detected automatically and may be wrong — check it '
        'before studying.'
  },
  'change_language': {'ru': 'Изменить язык', 'en': 'Change language'},
  'video_open_study': {'ru': 'Смотреть и учить', 'en': 'Watch & learn'},
  'video_delete': {'ru': 'Удалить видео', 'en': 'Delete video'},
  'video_delete_confirm': {
    'ru': 'Удалить видео и его субтитры? Слова в колодах останутся.',
    'en': 'Delete the video and its subtitles? Words in your decks are kept.'
  },
  'video_no_transcript': {
    'ru': 'Субтитры недоступны',
    'en': 'Subtitles are unavailable'
  },

  // ----------------------- Захват слов: буфер / фото / «Поделиться» ---------------
  'paste_clipboard': {'ru': 'Из буфера', 'en': 'From clipboard'},
  'clipboard_empty': {'ru': 'Буфер обмена пуст', 'en': 'Clipboard is empty'},
  // OCR (текст с фото)
  'ocr_title': {'ru': 'Текст с фото', 'en': 'Text from photo'},
  'ocr_hub_title': {'ru': 'Сфотографировать текст', 'en': 'Scan text'},
  'ocr_hub_sub': {'ru': 'Слова с фото — в колоду', 'en': 'Photo words into a deck'},
  'ocr_take_photo': {'ru': 'Снять фото', 'en': 'Take a photo'},
  'ocr_from_gallery': {'ru': 'Из галереи', 'en': 'From gallery'},
  'ocr_recognizing': {'ru': 'Распознаём…', 'en': 'Recognizing…'},
  'ocr_no_text': {'ru': 'Текст не распознан', 'en': 'No text recognized'},
  'ocr_words_title': {'ru': 'Новые слова', 'en': 'New words'},
  'ocr_words_sub': {'ru': 'Тап, чтобы добавить', 'en': 'Tap to add'},
  'ocr_source': {'ru': 'Фото', 'en': 'Photo'},
  'recognized_text': {'ru': 'Распознанный текст', 'en': 'Recognized text'},
  // «Поделиться» → Fern
  'share_import_title': {'ru': 'Добавить в Fern', 'en': 'Add to Fern'},
  'share_as_word': {'ru': 'Как слово', 'en': 'As a word'},
  'share_as_word_sub': {
    'ru': 'В колоду с переводом',
    'en': 'Into a deck with translation'
  },
  'share_as_book': {'ru': 'Как текст для чтения', 'en': 'As reading text'},
  'share_as_book_sub': {
    'ru': 'Импортировать в Библиотеку',
    'en': 'Import into the Library'
  },
  'share_open_video': {'ru': 'Разобрать видео', 'en': 'Learn from video'},
  'shared_text': {'ru': 'Полученный текст', 'en': 'Shared text'},
  'share_source': {'ru': 'Из общего доступа', 'en': 'Shared'},

  // ----------------------------- Грамматика карточки ------------------------------
  'grammar_title': {'ru': 'Грамматика', 'en': 'Grammar'},
  'grammar_present': {'ru': 'Настоящее время', 'en': 'Present tense'},
  'grammar_forms': {'ru': 'Формы', 'en': 'Forms'},
  'grammar_singular': {'ru': 'Ед. ч.', 'en': 'Singular'},
  'grammar_plural': {'ru': 'Мн. ч.', 'en': 'Plural'},
  'grammar_approx': {
    'ru': 'Формы построены по правилам — возможны исключения',
    'en': 'Rule-based forms — exceptions are possible'
  },

  // ----------------------- Свои изучаемые языки / закрепление ---------------------
  'pinned': {'ru': 'Закреплённые', 'en': 'Pinned'},
  'all_languages': {'ru': 'Все языки', 'en': 'All languages'},
  'pin_language': {'ru': 'Закрепить', 'en': 'Pin'},
  'unpin_language': {'ru': 'Открепить', 'en': 'Unpin'},
  'create_language': {'ru': 'Создать свой язык', 'en': 'Add a custom language'},
  'edit_language': {'ru': 'Изменить язык', 'en': 'Edit language'},
  'delete_language': {'ru': 'Удалить язык', 'en': 'Delete language'},
  'delete_language_confirm': {
    'ru': 'Убрать этот язык из списка? Колоды и слова на нём сохранятся.',
    'en': 'Remove this language from the list? Its decks and words are kept.'
  },
  'add_language_named': {'ru': 'Добавить «{code}»', 'en': 'Add "{code}"'},
  'lang_name_hint': {'ru': 'Название (напр. Suomi)', 'en': 'Name (e.g. Suomi)'},
  'lang_emoji_hint': {'ru': 'Флаг / эмодзи', 'en': 'Flag / emoji'},
  'lang_code_taken': {
    'ru': 'Такой код уже используется',
    'en': 'This code is already used'
  },
  'unknown_language': {'ru': 'Неизвестный язык', 'en': 'Unknown language'},
  'custom_lang_tag': {'ru': 'свой', 'en': 'custom'},

  // ----------------------------- Мотивация / итоги недели -------------------------
  'your_week': {'ru': 'Твоя неделя', 'en': 'Your week'},
  'week_days': {'ru': 'дней', 'en': 'days'},
  'freezes_n': {'ru': 'Щиты: {n}', 'en': 'Freezes: {n}'},
  'share': {'ru': 'Поделиться', 'en': 'Share'},
  'streak_saved': {
    'ru': 'Щит спас твою серию за пропущенный день ❄️',
    'en': 'A freeze saved your streak for a missed day ❄️'
  },

  // ----------------------------- Языки (родные названия для баннера) --------------
  'lang_en': {'ru': 'Английский', 'en': 'English'},
  'lang_es': {'ru': 'Испанский', 'en': 'Spanish'},
  'lang_de': {'ru': 'Немецкий', 'en': 'German'},
  'lang_fr': {'ru': 'Французский', 'en': 'French'},
  'lang_it': {'ru': 'Итальянский', 'en': 'Italian'},
  'lang_pt': {'ru': 'Португальский', 'en': 'Portuguese'},
  'lang_tr': {'ru': 'Турецкий', 'en': 'Turkish'},
  'lang_zh': {'ru': 'Китайский', 'en': 'Chinese'},
  'lang_ja': {'ru': 'Японский', 'en': 'Japanese'},
  'lang_ko': {'ru': 'Корейский', 'en': 'Korean'},
  'lang_ar': {'ru': 'Арабский', 'en': 'Arabic'},
  'lang_ru': {'ru': 'Русский', 'en': 'Russian'},
};
