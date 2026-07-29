# RuStore как четвёртый канал: план работ

Спека: `docs/superpowers/specs/2026-07-22-rustore-release-design.md`

**Цель:** тег `vX.Y.Z` собирает и раскладывает Fern по четырём каналам:
GitHub (split APK), Google Play (AAB), RuStore (универсальный APK), iOS (ipa).

**Общие ограничения**

- Проект Flutter лежит в `app/`, команды оттуда.
- `applicationId` = `com.fern.app`, один на все каналы.
- Подпись RuStore и GitHub — `fern-release.jks`, отпечаток SHA-256
  `516efd44e8af672ba7a9b101090db54698f5bb42e109c1b00ad4aaa52a2ce3a1`.
- `versionCode` общий из `pubspec.yaml`, обязан расти.
- Секреты уже в репозитории: `RUSTORE_KEY_ID`, `RUSTORE_PRIVATE_KEY`,
  `KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD`.
  Не хватает `PLAY_SERVICE_ACCOUNT_JSON`.

---

## Задача 1. Флейвор `rustore`

**Файлы:**
- Изменить: `app/android/app/build.gradle.kts` (блок `productFlavors`)
- Создать: `app/android/app/src/rustore/AndroidManifest.xml`
- Изменить: `app/lib/utils/build_config.dart`
- Изменить: `app/lib/services/store_update.dart`
- Изменить: `app/lib/settings_screen.dart` (тайл «Проверить обновления», строка ~394)

**Производит:** константы `kRuStoreBuild`, `kSelfUpdate` (= `kStore == 'github'`).

- [x] Третий flavor в `build.gradle.kts`
- [x] Манифест `src/rustore/AndroidManifest.xml` с `REQUEST_INSTALL_PACKAGES` через `tools:node="remove"`
- [x] `build_config.dart`: `kRuStoreBuild`, `kSelfUpdate` переписан с `!kPlayBuild` на `kStore == 'github'`
- [x] `store_update.dart`: ранний выход в `checkOnStart` и `checkManually` при `kRuStoreBuild`
- [x] `settings_screen.dart`: тайл проверки обновлений только при `kSelfUpdate || kPlayBuild`
- [x] `flutter analyze` = 0, `flutter test` зелёный

Тестов на константы не пишем: они compile-time, в тестовой среде `STORE` всегда
`github`. Проверка — сборка и ручной прогон.

## Задача 2. Скрипт сборки

**Файлы:** создать `app/tool/build_rustore.sh`

- [x] Скрипт по образцу `build_play.sh`: `flutter build apk --release --flavor rustore --dart-define=STORE=rustore`
- [x] Копия в `dist/Fern-<версия>-rustore.apk`
- [x] Проверка отпечатка ключа через `apksigner verify --print-certs`
- [x] Проверка, что `REQUEST_INSTALL_PACKAGES` в APK нет
- [x] Прогон скрипта локально (сборка Android на этой машине работает)

## Задача 3. Загрузка в RuStore

**Файлы:** создать `app/tool/rustore_upload.py`

Только стандартная библиотека плюс `openssl` для подписи: `cryptography` на
раннер не ставим, RSA в stdlib нет.

Порядок вызовов:

1. `POST https://public-api.rustore.ru/public/auth/`
   тело `{keyId, timestamp, signature}`, timestamp ISO 8601 с зоной,
   signature = base64(RSA-SHA512(keyId + timestamp)), живёт 60 секунд
2. `POST /public/v1/application/com.fern.app/version`
   заголовок `Public-Token: <jwe>`, тело `{publishType: "MANUAL", whatsNew, ...}`
   → `body` = versionId
3. `POST /public/v1/application/com.fern.app/version/{id}/apk?servicesType=Unknown&isMainApk=true`
   multipart, поле `file`
4. `POST /public/v1/application/com.fern.app/version/{id}/commit`

- [x] Функция подписи: base64-ключ → PEM → `openssl dgst -sha512 -sign`
- [x] Самопроверка `--selftest`: сгенерировать временный ключ, подписать, сверить `openssl dgst -verify`
- [x] Остальные шаги с понятными сообщениями об ошибках (черновик уже существует, версия без main APK)
- [x] `whatsNew` берётся из раздела текущей версии `CHANGELOG.md`, обрезается до лимита
- [x] Прогон `python3 tool/rustore_upload.py --selftest`

## Задача 4. Actions

**Файлы:** изменить `.github/workflows/release.yml`

- [x] Job `play`: AAB флейвора play, автозалив `r0adkll/upload-google-play`, трек internal
- [x] Job `rustore`: универсальный APK, заливка своим скриптом, публикация MANUAL
- [x] Оба job'а мягко пропускаются, если секретов нет (guard-шаг с output, `secrets` в job-level `if` не работает)
- [x] Общий шаг восстановления keystore вынесен без дублирования логики
- [x] Комментарий-заготовка под App Store job
- [x] Проверка синтаксиса: разбор YAML python-парсером (actionlint на машине нет)

## Задача 5. Документы

**Файлы:** создать `docs/rustore-checklist.md`, изменить `CLAUDE.md`

- [x] Чеклист RuStore: карточка, описание из `docs/play/description-ru.txt`, скриншоты, категория, возрастной рейтинг, политика, ключ подписи, порядок выпуска
- [x] Таблица каналов в `CLAUDE.md` расширена с двух до четырёх строк
- [x] Раздел про секреты Actions и про то, что первый релиз в оба магазина заливается руками
