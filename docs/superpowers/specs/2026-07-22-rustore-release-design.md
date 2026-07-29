# Четыре канала выпуска: GitHub, Google Play, RuStore, iOS

Дата: 2026-07-22

## Задача

Добавить RuStore четвёртым каналом распространения и свести выпуск к одному
тегу: Actions собирает всё и заливает в магазины сам.

Каналов после работы четыре:

| Канал | Формат | Подпись | Обновления | Pro |
|---|---|---|---|---|
| GitHub / Obtainium | 3 split-APK | `fern-release.jks` | свой апдейтер | ключ от бота |
| Google Play | AAB | ключ Google (Play App Signing) | Play In-App Update | покупка в Play |
| RuStore | 1 универсальный APK | `fern-release.jks` | магазин | ключ от бота |
| iOS | неподписанный `.ipa` | ставит тот, кто устанавливает | вручную | ключ от бота |

## Почему Pro в RuStore идёт ключом, а не платежами магазина

RuStore разрешает сторонние платёжные системы и комиссию за них не берёт.
Отдельно: с 1 февраля 2026 его собственные платёжные инструменты (платные
приложения, подписки, встроенные покупки) работают только у ИП и юрлиц, а у
физлица платные приложения скрывают с витрины и BillingClient SDK отключают.
Владелец Fern — физлицо, поэтому выбор один: ключ, который выдаёт @SnTAppsBot
после оплаты на lava.top. В интерфейсе RuStore-сборки это та же ветка, что и в
GitHub-сборке (`_keyButtons` в `pro_sheet.dart`).

## Почему универсальный APK, а не AAB

AAB RuStore переподписывает своим ключом, и версия из магазина перестаёт
вставать поверх версии с GitHub. APK нашим ключом сохраняет кросс-обновление
между каналами, и RuStore сам это рекомендует. Решено: один универсальный APK
(около 110 МБ), не сплиты.

## Часть 1. Флейвор `rustore`

**`android/app/build.gradle.kts`** — третий productFlavor в измерении `store`.

**`android/app/src/rustore/AndroidManifest.xml`** — копия play-манифеста:
`REQUEST_INSTALL_PACKAGES` удаляется через `tools:node="remove"`. Приложение из
магазина не ставит APK само.

**`lib/utils/build_config.dart`** — развилка на три значения:

```dart
const String kStore = String.fromEnvironment('STORE', defaultValue: 'github');
const bool kPlayBuild = kStore == 'play';        // биллинг Google + In-App Update
const bool kRuStoreBuild = kStore == 'rustore';  // магазин обновляет сам
const bool kSelfUpdate = kStore == 'github';     // свой апдейтер
```

Важно: `kSelfUpdate` перестаёт быть `!kPlayBuild`. Каждое место, которое сейчас
опирается на это отрицание, проверяется отдельно.

**Что меняется в поведении:**

| Файл | Сейчас | После |
|---|---|---|
| `services/store_update.dart` | `kPlayBuild` → In-App Update, иначе свой апдейтер | добавляется ранний выход при `kRuStoreBuild`: обновление приносит магазин |
| `settings_screen.dart` | кнопка «Проверить обновления» видна всем, кроме Play | в RuStore-сборке скрыта |
| `settings_screen.dart:1117` | «Восстановить покупки» при `kPlayBuild` | без изменений |
| `widgets/pro_sheet.dart` | `kPlayBuild` → кнопки магазина, иначе ключ | без изменений, RuStore попадает в ветку ключа |
| `services/billing_service.dart` | выходит, если не `kPlayBuild` | без изменений |

## Часть 2. Скрипт сборки

**`tool/build_rustore.sh`** по образцу `build_play.sh`:

```
flutter build apk --release --flavor rustore --dart-define=STORE=rustore
```

Результат копируется в `dist/Fern-<версия>-rustore.apk`. Скрипт падает, если нет
`android/key.properties` и `fern-release.jks`, и проверяет, что
`REQUEST_INSTALL_PACKAGES` в готовом APK нет (`aapt dump permissions`).

## Часть 3. Actions

Один workflow `release.yml`, четыре job'а. Job'ы магазинов идут после `release`
и не блокируют друг друга.

```
release ──┬── play      (AAB → Publisher API, трек internal)
          ├── rustore   (APK → RuStore API, черновик)
          └── ios       (ipa → GitHub Release)
```

**Мягкий пропуск.** Каждый магазинный job начинается с проверки секретов и
завершается успехом с пометкой в лог, если их нет. Пока Play-аккаунт и
RuStore-консоль не готовы, тег всё равно даёт GitHub-релиз.

**Секреты:**

| Секрет | Для чего |
|---|---|
| `PLAY_SERVICE_ACCOUNT_JSON` | ключ сервисного аккаунта Google Cloud с доступом в Play Console |
| `RUSTORE_KEY_ID` | идентификатор ключа из RuStore Консоли |
| `RUSTORE_PRIVATE_KEY` | приватный ключ RuStore в base64 |

**Загрузка в Play:** `r0adkll/upload-google-play`, `track: internal`,
`status: completed`. Промоушен на production жмётся руками.

**Загрузка в RuStore:** свой скрипт `tool/rustore_upload.py` на стандартной
библиотеке python. Чужой Action брать не хочется: он получает доступ к
приватному ключу. Порядок вызовов API (сверить с актуальной документацией при
реализации):

1. `POST /public/auth` — timestamp плюс подпись RSA-SHA512, в ответ JWE-токен
2. `POST /public/v1/application/{package}/version` — черновик версии
3. `POST /public/v1/application/{package}/version/{id}/apk` — файл multipart
4. `POST /public/v1/application/{package}/version/{id}/commit?publishType=MANUAL`

`publishType=MANUAL` оставляет версию в черновике: публикацию после модерации
жмёт человек.

**Ограничения, которые не обойти автоматизацией:**

- Первый релиз в Play заливается через консоль руками. Publisher API не создаёт
  приложение и не принимает первую сборку.
- Первая версия в RuStore тоже создаётся через консоль (нужны карточка,
  скриншоты, категория, возрастной рейтинг).

## Часть 4. iOS

Job `ios` остаётся как есть: неподписанный ipa на macos-раннере. Место под
App Store оставляется комментарием в workflow. Заводить его будем, когда
появится приложение в App Store Connect: понадобятся Apple Developer Program,
сертификат распространения, provisioning-профиль и ключ App Store Connect API.

## Часть 5. Документы

**`docs/rustore-checklist.md`** по образцу play-чеклиста: карточка (описание из
`docs/play/description-ru.txt`), скриншоты, категория, возрастной рейтинг,
политика конфиденциальности, ключ подписи, порядок выпуска новой версии.

**`CLAUDE.md`** — таблица «Что помнить про каналы» расширяется с двух до
четырёх строк, плюс правило: `versionCode` общий для всех каналов и обязан расти.

## Проверка

- `flutter analyze` и `flutter test` зелёные (тесты флейворов не касаются)
- `tool/build_rustore.sh` даёт подписанный APK, `apksigner verify --print-certs`
  показывает отпечаток `51:6E:FD:...`
- в собранном APK нет `REQUEST_INSTALL_PACKAGES`
- сборка с `--dart-define=STORE=rustore` не показывает «Проверить обновления»
  и открывает Pro через ключ
- workflow проходит на теге при отсутствующих секретах магазинов
