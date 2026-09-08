# Подписка Fern Pro — план работ

> **Для исполнителя:** задачи идут по порядку, каждая заканчивается зелёными
> тестами и коммитом. Шаги помечены галочками.

**Цель:** Fern Pro продаётся месячной (299 ₽) и годовой (1990 ₽) подпиской,
доступ открывается сам после оплаты в трёх кассах, без телеграм-бота.

**Устройство:** аккаунт Fern в PocketBase на VPS Togetherly сводит три кассы в
один срок `pro_until`; приложение носит подписанный офлайн-талон.

**Стек:** PocketBase 0.39.4 (JSVM-хуки), Python 3 без зависимостей на сервере,
Flutter 3.41 на клиенте, Ed25519 через `cryptography`.

**Спека:** `docs/superpowers/specs/2026-09-08-fern-subscription-design.md`

## Общие ограничения

- Аккаунты приложений **не смешиваются**: коллекция `fern_users` отдельна от
  `users` Togetherly, сессии не общие, поля не общие.
- Серверный код Fern живёт в репозитории, в папке `server/`, и раскладывается на
  VPS скриптом. На сервере ничего не правится «руками навсегда».
- Правки боевых файлов Togetherly (`pb_hooks/lava.pb.js`) идут с бэкапом
  `.bak-ГГГГММДД-ЧЧММ` и прогоном тестов Togetherly до и после.
- **Грабля JSVM:** обработчик роута исполняется в изолированном пуле и не видит
  функций уровня файла. Всё, что нужно роуту, объявляется внутри него.
- Приватный ключ Ed25519 в репозиторий не попадает никогда.
- Тексты для человека — по-русски, все новые строки клиента переводятся на все
  семь языков.
- Купившие «навсегда» не теряют Pro: формат 2 и `fern_pro` работают как прежде.

---

## Этап 1. Сервер: аккаунты, касса lava, талон

### Задача 1: Формат 3 — талон со сроком

**Файлы:**
- Изменить: `bot/license.py` (добавить `FORMAT_VERSION_TICKET = 3`)
- Тест: `bot/test_license.py` (создать)

**Интерфейсы:**
- Отдаёт: `issue_ticket(uid: str, email: str, until: date, issued: date|None,
  plan: int, key: Ed25519PrivateKey|None) -> str` и разбор в `verify()`,
  который для формата 3 возвращает `{"id", "sku", "email", "issued", "until",
  "plan"}`.

- [ ] **Шаг 1: тест на выпуск и разбор талона**

```python
def test_ticket_carries_until():
    key = Ed25519PrivateKey.generate()
    text = license.issue_ticket("abc123", "a@b.ru", date(2026, 10, 8),
                                issued=date(2026, 9, 8), key=key)
    info = license.verify(text, key.public_key().public_bytes(
        serialization.Encoding.Raw, serialization.PublicFormat.Raw))
    assert info["until"] == date(2026, 10, 8)
    assert info["email"] == "a@b.ru"
```

- [ ] **Шаг 2: прогнать, убедиться что падает** (`python3 bot/test_license.py`,
      ожидается `AttributeError: issue_ticket`)
- [ ] **Шаг 3: реализовать формат 3**

Payload: `struct.pack(">BBIHHB", 3, sku, license_id, days_issued, days_until,
len(email))` плюс почта. `license_id` = `zlib.crc32(uid.encode())`, чтобы номер
конкретного человека можно было внести в `docs/revoked.json`.

- [ ] **Шаг 4: тесты зелёные, старые форматы не сломаны**
      (`for t in bot/test_*.py; do python3 "$t"; done`)
- [ ] **Шаг 5: коммит** `Талон подписки: формат 3 со сроком внутри`

### Задача 2: Служба подписи талонов

**Файлы:**
- Создать: `server/fern_ticket.py` (HTTP на 127.0.0.1:8160)
- Создать: `server/fern-ticket.service`
- Тест: `server/test_fern_ticket.py`

**Интерфейсы:**
- Принимает: `POST /ticket {uid, email, until: "2026-10-08", plan: "month"}`
- Отдаёт: `{"ok": true, "ticket": "FERN…", "until": "2026-10-08"}`

Служба нужна потому, что JSVM PocketBase не умеет Ed25519, как не умел RS256 для
Play (`play_verify.py` появился по той же причине).

- [ ] **Шаг 1: тест** — запрос без `uid` даёт 400; корректный запрос даёт талон,
      который проходит `license.verify`; срок в ответе равен запрошенному.
- [ ] **Шаг 2: прогон, падение**
- [ ] **Шаг 3: реализация** по образцу `/opt/play_verify.py`: `http.server`,
      только loopback, ключ из `FERN_LICENSE_KEY`.
- [ ] **Шаг 4: тесты зелёные**
- [ ] **Шаг 5: коммит** `Служба подписи талонов Fern`

### Задача 3: Коллекции PocketBase

**Файлы:**
- Создать: `server/setup_collections.py`

Скрипт заводит `fern_users` (auth) и `fern_orders` через API суперюзера,
повторный запуск ничего не ломает (проверяет наличие).

`fern_users`: поля `pro_until` (date), `pro_source` (select lava/play/apple/grant),
`pro_status` (select active/cancelled/expired/refunded), `pro_plan` (select
month/year), `lava_contract` (text), `lifetime` (bool). Правила: `listRule` и
`viewRule` — `id = @request.auth.id`, остальные пустые (только суперюзер).

`fern_orders`: `order_key` (text, unique index), `uid`, `source`, `plan`,
`amount` (number), `currency`, `event`, `paid_at` (date), `until` (date), `raw`
(json). Правила пустые целиком: коллекция служебная.

- [ ] **Шаг 1: написать скрипт**
- [ ] **Шаг 2: прогнать на сервере, проверить `GET /api/collections`**
- [ ] **Шаг 3: проверить, что вход в `users` Togetherly не задет**
      (`POST /api/collections/users/auth-with-password` тестовым аккаунтом)
- [ ] **Шаг 4: коммит** `Коллекции аккаунтов и заказов Fern`

### Задача 4: Роуты Fern в PocketBase

**Файлы:**
- Создать: `server/pb_hooks/fern.pb.js`
- Тест: `server/test_fern_routes.py` (ходит по HTTP к живому PocketBase)

**Интерфейсы:**
- `POST /api/fern/checkout {plan, currency, lang}` → `{ok, url, orderId}`
- `GET /api/fern/me` → `{ok, until, status, source, plan, ticket}`
- `POST /api/fern/cancel` → `{ok, until}`

Хук создаёт счёт `POST https://gate.lava.top/api/v2/invoice` с `periodicity`
`MONTHLY` либо `PERIOD_YEAR`, офферы берёт из `FERN_OFFER_MONTH` и
`FERN_OFFER_YEAR`, ключ — `LAVA_API_KEY`. Возврат в приложение:
`successful_return_url: "fern://paid"`.

Талон `me` берёт у службы 8160, срок талона — `pro_until` плюс семь дней, но не
больше сорока дней от выдачи.

- [ ] **Шаг 1: тесты** — без сессии 401; чужой аккаунт Togetherly не пускает;
      `me` без подписки отдаёт `until: null` и пустой талон; отмена без
      подписки — 400.
- [ ] **Шаг 2: прогон, падение**
- [ ] **Шаг 3: реализация**, всё внутри обработчиков (грабля JSVM)
- [ ] **Шаг 4: тесты зелёные**
- [ ] **Шаг 5: коммит** `Роуты подписки Fern: счёт, статус, отмена`

### Задача 5: Приём событий lava для Fern

**Файлы:**
- Изменить: `/opt/pocketbase/pb_hooks/lava.pb.js` (копия в `server/pb_hooks/`)
- Тест: `server/test_lava_fern.py`

Ветка Fern включается, когда в уведомлении узнан оффер Fern. Обработка семи
событий — по таблице спеки. Идемпотентность: `order_key` = `LAVA:<contractId>`.

- [ ] **Шаг 1: тесты** на каждое событие, включая повтор того же `contractId`
      (второй раз срок не двигается) и `subscription.cancelled` с `willExpireAt`
- [ ] **Шаг 2: прогон, падение**
- [ ] **Шаг 3: реализация с бэкапом боевого файла**
- [ ] **Шаг 4: тесты Togetherly и Fern зелёные**
- [ ] **Шаг 5: коммит** `Вебхук lava понимает подписку Fern`

### Задача 6: Страховки от потерянного вебхука

**Файлы:**
- Изменить: `server/pb_hooks/fern.pb.js` (два `cronAdd`)
- Тест: `server/test_fern_cron.py`

Первый крон раз в две минуты добивает заказы `pending` моложе часа через
`GET /api/v1/invoices/{id}`. Второй раз в сутки сверяет `expiredAt` активных
подписок через `GET /api/v1/subscriptions/{parentContractId}`.

- [ ] **Шаг 1: тест** — потерянный вебхук о продлении лечится суточной сверкой
- [ ] **Шаг 2: прогон, падение**
- [ ] **Шаг 3: реализация**
- [ ] **Шаг 4: тесты зелёные**
- [ ] **Шаг 5: коммит** `Кроны добивают потерянные оплаты Fern`

### Задача 7: Раскладка на сервер

**Файлы:**
- Создать: `server/deploy.sh`

Копирует хуки в `/opt/pocketbase/pb_hooks/`, службу в `/opt/`, ставит
systemd-юнит, перезапускает PocketBase, проверяет `/api/health` и отвечает
ненулевым кодом, если проверка не прошла.

- [ ] **Шаг 1: написать**
- [ ] **Шаг 2: прогнать, проверить живость Togetherly**
- [ ] **Шаг 3: коммит** `Раскладка серверной части Fern`

---

## Этап 2. Клиент вне магазинов

### Задача 8: Аккаунт

**Файлы:**
- Создать: `app/lib/services/account_service.dart`
- Тест: `app/test/account_service_test.dart`

**Интерфейсы:**
- `AccountService.instance`: `signUp(email, password)`, `signIn(email, password)`,
  `signInWithGoogle()`, `signInWithApple()`, `signOut()`, `resetPassword(email)`,
  `String? get email`, `String? get token`, `bool get signedIn`.

Сессия в `SharedPreferencesAsync` под ключом `fernAuthToken`. Базовый адрес —
`AccountService.baseUrl` (`https://togetherly.duckdns.org`), задаётся константой,
чтобы тест подменял.

- [ ] **Шаг 1: тесты** на подменном HTTP-клиенте: вход кладёт токен, выход
      чистит, протухший токен обновляется, ошибка сети не роняет экран
- [ ] **Шаг 2: прогон, падение**
- [ ] **Шаг 3: реализация**
- [ ] **Шаг 4: `flutter analyze` = 0, тесты зелёные**
- [ ] **Шаг 5: коммит** `Аккаунт Fern: вход почтой, Google и Apple`

### Задача 9: Талон и статус подписки

**Файлы:**
- Создать: `app/lib/services/subscription_service.dart`
- Изменить: `app/lib/services/license_service.dart` (разбор формата 3)
- Изменить: `app/lib/services/pro.dart` (`active` учитывает талон)
- Тест: `app/test/subscription_test.dart`

**Интерфейсы:**
- `SubscriptionService.instance`: `DateTime? get until`, `bool get active`,
  `Future<void> refresh()`, `Future<void> load()`, `SubStatus get status`.

Формат 3 в `LicenseService.verify` возвращает `LicenseInfo` с полем `until`;
годность считается по `until`, а не по окну активации.

- [ ] **Шаг 1: тесты** — годный талон, просроченный, подделанный, чужая подпись,
      формат 2 работает по-прежнему, `Pro.active` истинно на каждом источнике
- [ ] **Шаг 2: прогон, падение**
- [ ] **Шаг 3: реализация**
- [ ] **Шаг 4: тесты зелёные**
- [ ] **Шаг 5: коммит** `Талон подписки на клиенте`

### Задача 10: Экран подписки

**Файлы:**
- Изменить: `app/lib/widgets/pro_sheet.dart`
- Создать: `app/lib/widgets/account_sheet.dart`
- Изменить: `app/lib/l10n/strings.dart`, `app/lib/l10n/translations.dart`
- Тест: `app/test/pro_sheet_subscription_test.dart`

Порядок: вход или регистрация, затем два тарифа, затем браузер с `paymentUrl`,
затем опрос `/api/fern/me` каждые три секунды до трёх минут. Строка состояния
показывает дату окончания и отдельно говорит про отменённую подписку.

- [ ] **Шаг 1: тесты** — без входа кнопка тарифа ведёт на вход; после возврата
      опрос открывает Pro; отменённая подписка показывает дату
- [ ] **Шаг 2: прогон, падение**
- [ ] **Шаг 3: реализация плюс переводы на семь языков**
- [ ] **Шаг 4: тесты, `l10n_coverage_test`, `screen_overflow_test` зелёные**
- [ ] **Шаг 5: коммит** `Экран подписки Fern`

### Задача 11: Возврат из браузера

**Файлы:**
- Изменить: `app/android/app/src/main/AndroidManifest.xml`
- Изменить: `app/ios/Runner/Info.plist`
- Изменить: `app/lib/main.dart` (обработка `fern://paid`)
- Тест: `app/test/deep_link_test.dart`

- [ ] **Шаг 1: тест** разбора ссылки `fern://paid` и `fern://failed`
- [ ] **Шаг 2: прогон, падение**
- [ ] **Шаг 3: реализация**
- [ ] **Шаг 4: тесты зелёные, `android_permissions_guard_test` не покраснел**
- [ ] **Шаг 5: коммит** `Возврат в приложение после оплаты`

---

## Этап 3. Магазины

### Задача 12: Подписки в play_verify

**Файлы:**
- Изменить: `server/play_verify.py` (копия боевого файла)
- Тест: `server/test_play_subscriptions.py`

`GET /androidpublisher/v3/applications/{пакет}/purchases/subscriptionsv2/tokens/{token}`,
берём `lineItems[].expiryTime` и `subscriptionState`. Пакет приходит параметром
запроса, иначе служба Togetherly сломается.

- [ ] **Шаг 1: тесты** на подменном ответе Google: активная, отменённая,
      просроченная подписка, чужой пакет
- [ ] **Шаг 2: прогон, падение**
- [ ] **Шаг 3: реализация**
- [ ] **Шаг 4: тесты Togetherly и Fern зелёные**
- [ ] **Шаг 5: коммит** `Проверка подписок Google Play`

### Задача 13: Роут приёма чеков

**Файлы:**
- Изменить: `server/pb_hooks/fern.pb.js`
- Тест: `server/test_fern_store.py`

`POST /api/fern/store {platform, productId, token}` → проверка через 8160/8097 →
`pro_until` берётся максимумом со старым значением.

- [ ] **Шаг 1: тесты** — Play, Apple, подделанный токен, повтор
- [ ] **Шаг 2: прогон, падение**
- [ ] **Шаг 3: реализация**
- [ ] **Шаг 4: тесты зелёные**
- [ ] **Шаг 5: коммит** `Приём магазинных чеков Fern`

### Задача 14: Покупка подписки в приложении

**Файлы:**
- Изменить: `app/lib/services/billing_service.dart`
- Тест: `app/test/billing_subscription_test.dart`

Товары `fern_pro_month` и `fern_pro_year`, `buyNonConsumable`, после покупки —
отправка токена на сервер. Разовый `fern_pro` продолжает открывать Pro навсегда.

- [ ] **Шаг 1: тесты** (помнить про `debugDefaultTargetPlatformOverride` и
      `BillingService.debugStoreBilling`)
- [ ] **Шаг 2: прогон, падение**
- [ ] **Шаг 3: реализация**
- [ ] **Шаг 4: тесты зелёные**
- [ ] **Шаг 5: коммит** `Подписка через кассу магазина`

---

## Этап 4. Уведомления о продлении

### Задача 15: RTDN и Server Notifications V2

**Файлы:**
- Изменить: `server/pb_hooks/fern.pb.js` (роуты приёма)
- Тест: `server/test_store_notifications.py`

До этого этапа продление узнаётся при следующем запуске приложения, разрыв
закрывает недельная льгота талона.

- [ ] **Шаг 1: тесты** на разбор уведомлений о продлении, отмене, возврате
- [ ] **Шаг 2: прогон, падение**
- [ ] **Шаг 3: реализация**
- [ ] **Шаг 4: тесты зелёные**
- [ ] **Шаг 5: коммит** `Уведомления магазинов о продлении`

---

## Этап 5. Переключение

### Задача 16: Витрина и документы

**Файлы:**
- Изменить: `docs/monetization.md`, `bot/catalog.py`, `bot/texts.py`,
  `CHANGELOG.md`, `docs/appstore/`, `docs/play/`

- [ ] Снять разовый товар `34586da0-…` с продажи на lava
- [ ] Убрать Fern Pro из каталога бота, оставив выдачу ключей купившим раньше
- [ ] Переписать `docs/monetization.md` под подписку
- [ ] Обновить тексты магазинов и заметки релиза, сказав вслух про сохранение
      Pro у купивших навсегда
- [ ] **Коммит** `Витрина переехала на подписку`

---

## Ручные шаги владельца

1. **lava.top:** создать товар-подписку с двумя тарифами (299 ₽ в месяц,
   1990 ₽ в год; в валюте не ниже 5 $ и 5 €, это минимум сервиса), записать
   `offerId` обоих в переменные `FERN_OFFER_MONTH` и `FERN_OFFER_YEAR`.
2. **Google Play:** группа подписок, товары `fern_pro_month` и `fern_pro_year`,
   права сервисному аккаунту `play-publisher@` на приложение Fern.
3. **App Store Connect:** группа подписок, те же два товара, тексты и снимок.

Без первого пункта этап 1 доводится до конца, но реальную оплату проверить
нельзя: код возьмёт офферы из окружения, когда они появятся.
