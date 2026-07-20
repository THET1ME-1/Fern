# Google Play — что нужно для публикации

Готовое — отмечено ✅, за тобой — ⬜.

## 1. Сборка

✅ Отдельный вариант для Play: `./tool/build_play.sh` → `app/dist/Fern-<версия>-play.aab`
✅ Из Play-сборки вырезано `REQUEST_INSTALL_PACKAGES` (скрипт это проверяет и падает, если разрешение вернулось)
✅ Обновления в Play-сборке идут через **Play In-App Update**, а не с GitHub
✅ targetSdk 36, нативные библиотеки выровнены под 16 КБ страниц
✅ Подпись постоянным ключом (`android/fern-release.jks`, копия в `~/keys/`)

⬜ **При первой загрузке отдать Google свой ключ подписи.** Play по умолчанию подписывает приложение собственным ключом, и тогда версия из Play и версия с GitHub становятся несовместимы: одна не встанет поверх другой. В Play Console при настройке App Signing выбери «использовать свой ключ» и загрузи `fern-release.jks`.

## 2. Аккаунт и тестирование

⬜ **Аккаунт разработчика** — $25 единоразово.
⬜ **Закрытое тестирование: 12 тестеров, непрерывно 14 дней.** Требование Google для новых личных аккаунтов; без него production не откроется. Тестеров зови заранее (Telegram-канал), они должны реально установить приложение и не удалять две недели.
⬜ Внутреннее тестирование (internal testing) — можно начать сразу, без 14 дней, для себя.

## 3. Карточка приложения

✅ Иконка 512×512: `docs/play/icon-512.png`
✅ Графический баннер 1024×500: `docs/play/feature-graphic-1024x500.png`
⬜ **Скриншоты телефона** — минимум 2, лучше 4–8. Что показать: главный экран с колодами, сессию повторов, читалку с тапом по слову, экран прогресса, разбор видео.

### Название (30 символов)
```
Fern — карточки для языков
```

### Краткое описание (80 символов)
```
Красивые флеш-карточки: учи слова из книг, видео и фото. Офлайн, без аккаунта.
```

### Полное описание (до 4000 символов)
```
Fern — приложение для изучения иностранных слов на основе интервального повторения. Оно показывает слово ровно тогда, когда вы вот-вот его забудете, — так словарь запоминается надолго, а не до завтрашнего дня.

УМНОЕ ПОВТОРЕНИЕ
• Современный алгоритм FSRS — тот же, что в Anki, но включён сразу и не требует настройки
• Приложение подстраивается под вашу память: чем лучше вы помните слово, тем реже оно появляется
• Раздельные лимиты новых слов и повторов — не будет лавины карточек после пропуска
• Ошибку переспрашивает в той же сессии, а не откладывает на завтра

СЛОВА ИЗ ТОГО, ЧТО ВЫ ЧИТАЕТЕ И СМОТРИТЕ
• Читалка книг: тап по незнакомому слову — перевод и карточка. Поддерживаются EPUB, FB2, TXT
• Разбор видео с YouTube по субтитрам: слово можно услышать голосом из самого видео
• Распознавание текста с фото — сфотографировали страницу или вывеску и забрали слова
• Импорт статьи по ссылке, добавление слов из буфера обмена и через «Поделиться»
• Приложение показывает, какую долю текста вы уже знаете, — сразу видно, по силам ли книга

РЕЖИМЫ ЗАНЯТИЙ
Карточки, выбор перевода, ввод слова, диктант на слух, сборка фразы, пропуск в предложении, игра на скорость и подбор пар.

ЧЕСТНЫЙ ОФЛАЙН
• Работает без интернета: и повторение, и перевод слов, и озвучка
• Нет аккаунта и нет облака — словарь и статистика остаются на телефоне
• Резервная копия — обычный файл, который принадлежит вам
• Импорт колод из Anki (.apkg) и CSV — ваши старые колоды никуда не денутся

ЖИВОЙ ИНТЕРФЕЙС
Material You: приложение подхватывает цвета ваших обоев. Тёмная тема, AMOLED-режим, 7 языков интерфейса.

Никакой рекламы, никакой слежки, никаких подписок ради базовых функций.

FERN PRO
Книги, видео, статьи, текст с фотографии и перенос колод из Anki и CSV. Разовая покупка, навсегда и на всех ваших устройствах. Карточки, все режимы, FSRS, статистика и резервная копия остаются бесплатными без лимитов на число колод и карточек.

Первая книга бесплатна. Попробуйте на том, что и правда хотите прочитать.
```

### Английский листинг

Основной рынок — англоязычный, и Play показывает эту версию всем локалям, для
которых перевода нет.

**Название (30):**
```
Fern: Flashcards & Reading
```

**Краткое описание (80):**
```
Smart flashcards with spaced repetition, plus reading in your own books.
```

**Полное описание:**
```
Fern teaches words the way memory actually works: it shows a card exactly when you are about to forget it, and never sooner.

Under the hood is FSRS — the same scheduling algorithm Anki users switch to when the default one starts wasting their time. Fern turns it on out of the box and tunes it to you: after a couple hundred reviews it measures how fast you personally forget.

WORDS FROM WHAT YOU READ AND WATCH
• Book reader: tap an unknown word for its translation and a card. EPUB, FB2 and TXT
• YouTube videos by subtitles — hear the word in the voice from the video itself
• Text recognition from photos: shoot a page or a sign and take the words with you
• Articles by link, words from the clipboard and from the system share sheet
• Before you start, Fern shows how much of the text you already know — so you can tell whether a book is within reach

STUDY MODES
Flip cards, multiple choice, typing, listening, sentence building, cloze from real sentences, speed round and a matching game.

HONEST OFFLINE
• Reviews, translation and speech all work without a network
• No account and no cloud — your vocabulary and statistics stay on the phone
• The backup is an ordinary file that belongs to you
• Deck import from Anki (.apkg) and CSV — your old decks come with you

LIVING INTERFACE
Material You: the app picks up the colours of your wallpaper. Dark theme, AMOLED mode, seven interface languages.

FERN PRO
Books, videos, articles, photographed text and deck import. One purchase, yours forever, on all your devices. Cards, every study mode, FSRS, statistics and backup stay free, with no limits on how many decks or cards you make.

Your first book is free. Try it on something you actually want to read.

No ads, no tracking, no subscription for the basics.
```

### Категория
Образование → Обучение языкам

## 4. Data Safety (декларация данных)

Отвечать так:

| Вопрос | Ответ |
|---|---|
| Собирает ли приложение данные пользователя? | **Нет** |
| Передаёт ли данные третьим лицам? | **Нет** |
| Шифруется ли передача? | Да (HTTPS; обычный HTTP — только к серверу в локальной сети пользователя, если он сам его настроил) |
| Можно ли запросить удаление данных? | Данные не собираются; всё удаляется вместе с приложением или кнопкой «Удалить все данные» |

Важная оговорка: слова, которые пользователь переводит, уходят к выбранному им сервису перевода (Google, DeepL или его собственный сервер). Это не «сбор данных приложением», но если Google спросит про сетевые обращения — так и объясняй: запрос содержит только переводимое слово, без идентификаторов.

## 5. Обязательные пункты консоли

⬜ **Политика конфиденциальности:** https://thet1me-1.github.io/fern_releases/privacy.html
⬜ **Сайт приложения:** https://thet1me-1.github.io/fern_releases/
⬜ **Возрастной рейтинг** — заполнить анкету (насилия, азартных игр, пользовательского контента нет → выйдет 3+/Everyone)
⬜ **Реклама:** нет
⬜ **Целевая аудитория:** 13+ (не «для детей», иначе включатся жёсткие требования Families Policy)
⬜ **Доступ к приложению:** всё открыто без входа (сообщить, что логина нет)
⬜ **Government apps / финансы / здоровье** — не применимо

## 6. Цена — решено

**Бесплатно + разовая покупка Fern Pro за 4.99 $** (товар `fern_pro`, non-consumable).
Подписки нет, рекламы нет. Разбор решения и границу «что бесплатно, что нет» —
см. [`monetization.md`](monetization.md).

⬜ **Merchant-профиль** в Play Console: банковский счёт и налоговая анкета.
Молдова поддерживается, выплаты приходят банковским переводом в долларах.

⬜ Создать товар `fern_pro` **до** закрытого тестирования: пока товар не активен,
покупку нельзя проверить даже себе.

## 7. Что помнить про два канала

| | GitHub / Obtainium | Google Play |
|---|---|---|
| Сборка | `./tool/build_release.sh` | `./tool/build_play.sh` |
| Формат | APK по ABI | AAB |
| Обновление | своё, с GitHub | Play In-App Update |
| Разрешение на установку APK | есть | вырезано |

`versionCode` (число после `+` в pubspec) обязан расти при каждой загрузке в Play — Play не примет одинаковый дважды, даже если предыдущую сборку удалить.
