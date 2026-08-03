#!/usr/bin/env python3
"""Бот выдачи ключей магазина SnT (@SnTAppsBot).

Деньги принимает lava.top, бот только выдаёт ключ. Схема без единого письма:

    покупка на lava.top  →  вебхук сюда  →  заказ лёг в журнал
    покупатель пишет боту почту  →  бот находит заказ  →  присылает ключ

Почта не отправляется ни разу: SMTP на сервере закрыт, а квоту гугловского
релея занимает другой проект. Телеграм есть у всех, кто платит через lava.top.

Ключ подписан Ed25519 и проверяется приложением офлайн
(`app/lib/services/license_service.dart`). Сервер в проверке не участвует —
бот только подписывает и помнит, кому что выдал.

Один бот обслуживает несколько приложений: номер товара едет внутри ключа
(см. SKU_* в license.py), чужой ключ приложение не примет.

Запуск:
    export SNT_BOT_TOKEN=...          # от @BotFather
    export SNT_BOT_OWNER=...          # ваш telegram id: команда /stats
    export SNT_WEBHOOK_KEY=...        # тот же секрет, что вписан в lava.top
    python3 bot/bot.py
"""
from __future__ import annotations

import asyncio
import hmac
import json
import logging
import os
import sqlite3
from datetime import datetime, timezone
from pathlib import Path

from aiogram import Bot, Dispatcher, F
from aiogram.client.default import DefaultBotProperties
from aiogram.client.session.aiohttp import AiohttpSession
from aiogram.client.telegram import TelegramAPIServer
from aiogram.enums import ParseMode
from aiogram.filters import Command, CommandStart
from aiogram.types import (
    BotCommand,
    BotCommandScopeChat,
    BotCommandScopeDefault,
    CallbackQuery,
    InlineKeyboardButton,
    InlineKeyboardMarkup,
    Message,
)
from aiohttp import web

import texts
import urllib.parse

import catalog
import coins as tg_coins
from lava import EMAIL_RE, parse as parse_webhook
from license import SKU_PRO, issue
from store import Store

TOKEN = os.environ.get("SNT_BOT_TOKEN", "")
OWNER = int(os.environ.get("SNT_BOT_OWNER", "0"))
WEBHOOK_KEY = os.environ.get("SNT_WEBHOOK_KEY", "")
WEBHOOK_PORT = int(os.environ.get("SNT_WEBHOOK_PORT", "8091"))
DB_PATH = Path(os.environ.get("SNT_BOT_DB", Path(__file__).parent / "purchases.db"))

# Адрес api.telegram.org или прокси перед ним. На российском хостинге телеграм
# закрыт (ICMP проходит, TLS не устанавливается вовсе), и бот там молча крутит
# ретраи — поэтому запросы идут через воркер Cloudflare (`bot/tg-proxy`).
# Пусто = ходить в телеграм напрямую.
API_BASE = os.environ.get("SNT_API_BASE", "").rstrip("/")

# Очередь событий lava.top у воркера: снаружи до бота не достучаться, поэтому
# вебхук принимает воркер, а бот приходит за накопленным сам. Пусто = не ходить
# (тогда события ждут только на своём порту).
PULL_URL = os.environ.get("SNT_PULL_URL", "").rstrip("/")
PULL_KEY = os.environ.get("SNT_PULL_KEY", "")
PULL_EVERY = int(os.environ.get("SNT_PULL_EVERY", "15"))

# Товары магазина: идентификатор на lava.top → что выдавать.
# Переопределяется переменной SNT_BOT_PRODUCTS (тот же JSON).
PRODUCTS: dict[str, dict] = json.loads(os.environ.get("SNT_BOT_PRODUCTS", json.dumps({
    "34586da0-fa77-4b5d-a080-e183e7ea8803": {
        "sku": SKU_PRO,
        "name": "Fern Pro",
        "app": "Fern",
    },
})))

BUY_URL = os.environ.get(
    "SNT_BUY_URL",
    "https://app.lava.top/products/34586da0-fa77-4b5d-a080-e183e7ea8803",
)

log = logging.getLogger("snt-bot")

# ----------------------------- Журнал -----------------------------

store = Store(DB_PATH)

# Бот нужен и вебхуку — сообщить владельцу о продаже. Ставится в main().
bot: Bot | None = None


async def notify_owner(text: str) -> None:
    """Сообщение владельцу. Молчит, если владелец не задан.

    Ошибка отправки не должна ронять обработку вебхука: заказ уже в журнале,
    а недоставленное уведомление — потеря куда меньшая, чем ответ lava.top
    ошибкой и двадцать повторов следом.
    """
    if not OWNER or bot is None:
        return
    try:
        await bot.send_message(OWNER, text)
    except Exception:
        log.exception("не удалось уведомить владельца")


# ----------------------------- Товары -----------------------------


def resolve_product(product_id: str | None) -> dict:
    """Товар по идентификатору с lava.top.

    Незнакомый идентификатор при единственном настроенном товаре считаем этим
    товаром: первая продажа не должна сорваться из-за того, что в вебхуке
    приезжает идентификатор оффера, а не продукта. След остаётся в логе.
    """
    if product_id and product_id in PRODUCTS:
        return PRODUCTS[product_id]
    if len(PRODUCTS) == 1:
        only = next(iter(PRODUCTS.values()))
        log.warning("товар %s не в списке — считаю его «%s»", product_id, only["name"])
        return only
    log.error("товар %s не опознан, заказ не записан", product_id)
    return {}


def product_of(row: sqlite3.Row) -> dict:
    """Настройки товара для заказа: по идентификатору, иначе по номеру sku."""
    if row["product_id"] and row["product_id"] in PRODUCTS:
        return PRODUCTS[row["product_id"]]
    for item in PRODUCTS.values():
        if item.get("sku") == row["sku"]:
            return item
    return {}


# ----------------------------- HTTP -----------------------------


async def process_event(payload) -> str:
    """Событие lava.top: записать заказ или отметить возврат.

    Один путь на оба входа — вебхук напрямую и очередь воркера, — иначе оплата,
    принятая с одной стороны, разошлась бы с оплатой, принятой с другой.
    """
    raw = json.dumps(payload, ensure_ascii=False)
    log.info("событие: %s", raw)

    order = parse_webhook(payload)
    if order is None:
        # Не оплата, отказ или событие без почты. Повторы делу не помогут,
        # поэтому это не ошибка: событие остаётся в логе.
        return "ignored"

    # Монеты Togetherly: у них свой сервер, ключ офлайн не нужен — код
    # создаётся прямо в PocketBase и ждёт, пока покупатель придёт за ним.
    if tg_coins.coins_for(order["product_id"]) is not None:
        if order["kind"] == "refund":
            log.info("возврат монет %s (%s) — код остаётся, гасить вручную",
                     order["order_id"], order["email"])
            await notify_owner(
                f"↩️ Возврат по монетам Togetherly: {order['email']}")
            return "ok"
        try:
            made = tg_coins.create_code(
                order["product_id"], order["email"], order["order_id"])
        except Exception as err:      # noqa: BLE001 — покупка важнее стектрейса
            log.exception("код монет не создан: %s", err)
            await notify_owner(
                f"⚠️ Оплата пришла, а код НЕ создан: {order['email']}\n{err}")
            return "error"
        code, amount = made
        log.info("монеты %s: код для %s", amount, order["email"])
        await notify_owner(
            f"🪙 Togetherly: {amount} монет, {order['email']}\nКод {code}")
        return "ok"

    product = resolve_product(order["product_id"])
    if not product:
        return "unknown product"

    if order["kind"] == "refund":
        row = store.refund(order["order_id"], order["email"])
        log.info("возврат %s (%s) — %s", order["order_id"], order["email"],
                 "заказ помечен" if row else "нечего помечать")
        if row is not None:
            await notify_owner(texts.refund_notice(
                order["email"], product["name"], row["license_id"]))
        return "ok"

    # Заказ без идентификатора: склеиваем свой из почты и дня, иначе повтор
    # вебхука создал бы вторую запись и второй ключ.
    order_id = order["order_id"] or \
        f"{order['email']}:{datetime.now(timezone.utc).date()}"

    fresh = store.save_order(order_id, order["email"], order["product_id"],
                             product["sku"], order["amount"], raw)
    log.info("заказ %s (%s, %s) — %s", order_id, order["email"], product["name"],
             "новый" if fresh else "повтор")
    if fresh:
        await notify_owner(texts.sale_notice(
            order["email"], product["name"], order["amount"], order_id))
    return "ok"


async def lava_webhook(request: web.Request) -> web.Response:
    # Без ключа вебхук закрыт наглухо: «предупредили и пустили» означало бы,
    # что забытая переменная окружения раздаёт ключи Pro любому, кто нашёл
    # эндпоинт и слепил похожий JSON о покупке.
    if not WEBHOOK_KEY:
        log.warning("вебхук отклонён: SNT_WEBHOOK_KEY не задан")
        return web.Response(status=503, text="webhook key not configured")
    got = request.headers.get("X-Api-Key", "")
    # Сравнение постоянное по времени: обычное != позволяет подбирать ключ
    # посимвольно по задержке ответа. Через байты: строковый compare_digest
    # не принимает не-ASCII ключи.
    if not hmac.compare_digest(got.encode(), WEBHOOK_KEY.encode()):
        log.warning("вебхук с чужим ключом от %s", request.remote)
        return web.Response(status=401, text="bad key")

    try:
        payload = await request.json()
    except Exception:
        log.exception("вебхук: тело не разобралось")
        return web.Response(status=400, text="bad json")

    # 200 даже на непонятное событие: lava.top повторяет вебхук до двадцати раз.
    return web.Response(text=await process_event(payload))


async def health(_: web.Request) -> web.Response:
    return web.Response(text="alive")


# ----------------------------- Очередь воркера -----------------------------


async def handle_pulled(events: list[dict]) -> list[str]:
    """Разбирает пачку событий из очереди, возвращает ключи для подтверждения.

    Мусор подтверждается наравне с оплатой: событие, которое не разобралось
    сейчас, не разберётся и на двадцатый раз, а очередь оно забьёт навсегда.
    """
    done: list[str] = []
    for event in events:
        key = event.get("key")
        try:
            await process_event(json.loads(event["payload"]))
        except Exception:
            log.exception("событие %s не разобралось", key)
        if key:
            done.append(key)
    return done


async def pull_loop() -> None:
    """Ходит за событиями к воркеру.

    Достучаться до бота снаружи нельзя — порты хостинга заняты чужим сервисом,
    а телеграм с него и вовсе недоступен. Поэтому вебхук lava.top принимает
    воркер Cloudflare, а бот забирает накопленное сам, своим же исходящим
    соединением.
    """
    import aiohttp

    # Сессия одна на всё время работы. Новое TCP-соединение с этого хостинга
    # изредка упирается в потерянный SYN и встаёт на двенадцать секунд, а
    # keep-alive держит уже установленное и заодно греет путь для ответов
    # покупателям.
    headers = {"X-Pull-Key": PULL_KEY}
    timeout = aiohttp.ClientTimeout(total=30)
    async with aiohttp.ClientSession(headers=headers, timeout=timeout) as session:
        while True:
            try:
                async with session.get(f"{PULL_URL}/pull") as response:
                    events = (await response.json()).get("events", [])
                if events:
                    log.info("из очереди пришло событий: %s", len(events))
                    done = await handle_pulled(events)
                    if done:
                        async with session.post(
                            f"{PULL_URL}/ack", json={"keys": done},
                        ) as ack:
                            await ack.read()
            except Exception:
                # Сеть моргнула или воркер ответил не тем: заказы никуда не
                # делись, они лежат в очереди неделю и дождутся следующего
                # захода.
                log.exception("очередь: заход не удался")
            await asyncio.sleep(PULL_EVERY)


# ----------------------------- Бот -----------------------------

dp = Dispatcher()


def menu() -> InlineKeyboardMarkup:
    """Витрина: сперва приложение, товары — внутри него.

    Плоский список товаров рос бы с каждым приложением и превращался в кашу.
    """
    rows = [[InlineKeyboardButton(text=catalog.title(app_id),
                                  callback_data=f"app:{app_id}")]
            for app_id in catalog.app_ids()]
    rows.append([
        InlineKeyboardButton(text="📦 Мои покупки", callback_data="mykeys"),
        InlineKeyboardButton(text="❓ Помощь", callback_data="help"),
    ])
    return InlineKeyboardMarkup(inline_keyboard=rows)


def app_menu(app_id: str) -> InlineKeyboardMarkup:
    """Экран приложения: его товары ссылками на оплату."""
    rows = [[InlineKeyboardButton(text=f"🛒 {item['title']}", url=item["url"])]
            for item in catalog.items(app_id)]
    rows.append([InlineKeyboardButton(text="✅ Уже оплатил", callback_data="claim")])
    rows.append([InlineKeyboardButton(text="⬅️ К приложениям", callback_data="menu")])
    return InlineKeyboardMarkup(inline_keyboard=rows)


def back(buy: bool = False) -> InlineKeyboardMarkup:
    """Клавиатура внутреннего экрана: возврат к витрине, иногда с покупкой."""
    rows = []
    if buy:
        rows.append([InlineKeyboardButton(text="🛒 Купить", url=BUY_URL)])
    rows.append([InlineKeyboardButton(text="⬅️ В меню", callback_data="menu")])
    return InlineKeyboardMarkup(inline_keyboard=rows)


async def show(query: CallbackQuery, text: str,
               keyboard: InlineKeyboardMarkup) -> None:
    """Перерисовывает открытый экран вместо новой простыни в чате.

    Телеграм отвечает ошибкой, когда текст и кнопки не изменились (человек
    нажал ту же кнопку дважды) — на это отвечать нечем, экран уже нужный.
    """
    try:
        await query.message.edit_text(text, reply_markup=keyboard)
    except Exception:
        await query.message.answer(text, reply_markup=keyboard)


def _first_claim(row: sqlite3.Row) -> bool:
    """Ключ забрали только что, а не перевыпустили.

    Перевыпуск — обычное дело: окно активации в приложении три дня, и за
    свежим ключом покупатель приходит сам. Сообщать владельцу о каждом таком
    заходе незачем, а вот о первой выдаче — стоит.
    """
    claimed = row["claimed_at"]
    if not claimed:
        return False
    when = datetime.fromisoformat(claimed)
    if when.tzinfo is None:
        when = when.replace(tzinfo=timezone.utc)
    return (datetime.now(timezone.utc) - when).total_seconds() < 60


def key_message(row: sqlite3.Row) -> str:
    # Ключ именной: почта заказа едет внутри и видна покупателю в настройках
    # приложения. Копированию это не мешает, но выложить ключ в общий доступ
    # значит выложить вместе с ним свой адрес.
    return texts.key_message(
        product_of(row).get("name", "Ключ"),
        row["license_id"],
        issue(row["license_id"], sku=row["sku"], email=row["email"]),
    )


@dp.message(CommandStart())
async def start(message: Message) -> None:
    await message.answer(texts.WELCOME, reply_markup=menu())


@dp.message(Command("buy"))
async def cmd_buy(message: Message) -> None:
    await message.answer(texts.WELCOME, reply_markup=menu())


# Часики на кнопке крутятся, пока бот не ответит на callback, поэтому
# `query.answer()` идёт ПЕРВЫМ во всех обработчиках: связь с телеграмом у бота
# непрямая, и заставлять кнопку «думать» всё время перерисовки незачем.


@dp.callback_query(F.data == "menu")
async def cb_menu(query: CallbackQuery) -> None:
    await query.answer()
    await show(query, texts.WELCOME, menu())


@dp.callback_query(F.data.startswith("app:"))
async def cb_app(query: CallbackQuery) -> None:
    # Без answer() часики на кнопке крутятся, пока телеграм не устанет ждать.
    await query.answer()
    app_id = query.data.split(":", 1)[1]
    if not catalog.app(app_id):
        await show(query, texts.WELCOME, menu())
        return
    await show(query, catalog.card(app_id), app_menu(app_id))


@dp.callback_query(F.data == "about")
async def cb_about(query: CallbackQuery) -> None:
    await query.answer()
    await show(query, texts.PRODUCT_CARD, back(buy=True))


@dp.callback_query(F.data == "help")
async def cb_help(query: CallbackQuery) -> None:
    await query.answer()
    await show(query, texts.HELP, back())


@dp.callback_query(F.data == "claim")
async def cb_claim(query: CallbackQuery) -> None:
    await query.answer()
    await show(query, texts.ASK_EMAIL, back())


@dp.callback_query(F.data == "mykeys")
async def cb_mykeys(query: CallbackQuery) -> None:
    await query.answer()
    await send_keys(query.message, query.from_user.id)


@dp.message(Command("help"))
async def cmd_help(message: Message) -> None:
    await message.answer(HELP)


@dp.message(Command("my"))
async def cmd_my(message: Message) -> None:
    """Покупки телеграм-аккаунта: ключи Fern и коды монет Togetherly."""
    await send_keys(message, message.from_user.id)


@dp.message(Command("key"))
async def cmd_key(message: Message) -> None:
    await send_keys(message, message.from_user.id)


async def send_keys(message: Message, user_id: int) -> None:
    """Всё, что человек уже забрал: ключи Fern и коды монет Togetherly."""
    rows = store.orders_of(user_id)
    for row in rows:
        await message.answer(key_message(row))

    # Коды монет живут не в журнале бота, а в PocketBase Togetherly.
    tg_rows = []
    try:
        token = tg_coins.auth()
        # Фильтр собираем заранее: кавычки внутри f-строки роняли парсер.
        flt = urllib.parse.quote('given_to="%s"' % user_id)
        st, data = tg_coins._api(
            "GET",
            f"/api/collections/redeem_codes/records?filter={flt}"
            "&sort=-given_at&perPage=20",
            token,
        )
        tg_rows = data.get("items", []) if st == 200 else []
    except Exception:                              # noqa: BLE001
        log.exception("не смог прочитать коды монет")

    for row in tg_rows:
        code = row.get("code", "")
        pretty = f"{code[:2]}-{code[2:6]}-{code[6:]}" if len(code) == 10 else code
        used = " · уже применён" if row.get("used_by") else ""
        await message.answer(
            f"🪙 <b>{row.get('coins')} монет в Togetherly</b>{used}\n\n"
            f"Код: <code>{pretty}</code>"
        )

    if not rows and not tg_rows:
        await message.answer(texts.NO_KEYS, reply_markup=menu())


@dp.message(Command("stats"))
async def cmd_stats(message: Message) -> None:
    if message.from_user.id != OWNER:
        return
    st = store.stats()
    tail = "\n".join(f"• {texts.escape(r['email'])} — {r['created'][:16]}"
                     for r in st["last"])
    await message.answer(
        f"<b>Заказов:</b> {st['total']}\n"
        f"<b>Ключей выдано:</b> {st['given']}\n"
        f"<b>Ждут получения:</b> {st['waiting']}\n"
        f"<b>Возвратов:</b> {st['refunded']}\n\n{tail or '—'}"
    )


@dp.message(Command("id"))
async def cmd_id(message: Message) -> None:
    """Свой номер в телеграме. Нужен при развёртывании: этот номер кладут в
    `SNT_BOT_OWNER`, иначе уведомления о продажах слать некому."""
    await message.answer(
        f"Ваш telegram id: <code>{message.from_user.id}</code>")


@dp.message(Command("find"))
async def cmd_find(message: Message) -> None:
    """Владельцу: что числится за почтой. Ничего не меняет."""
    if message.from_user.id != OWNER:
        return
    found = EMAIL_RE.search(message.text or "")
    if not found:
        await message.answer("Как пользоваться: <code>/find почта@пример.ру</code>")
        return
    rows = store.find(found.group(0))
    if not rows:
        await message.answer("Заказов по этой почте нет.")
        return
    await message.answer("\n\n".join(texts.order_line(row) for row in rows))


@dp.message(Command("grant"))
async def cmd_grant(message: Message) -> None:
    """Владельцу: выдать ключ вручную, когда покупатель написал лично.

    Получателя не проставляет: покупатель придёт к боту сам и заберёт тот же
    ключ, а не второй.
    """
    if message.from_user.id != OWNER:
        return
    found = EMAIL_RE.search(message.text or "")
    if not found:
        await message.answer("Как пользоваться: <code>/grant почта@пример.ру</code>")
        return
    rows = store.grant(found.group(0))
    if not rows:
        await message.answer("Оплаты по этой почте нет — выдавать нечего.")
        return
    for row in rows:
        await message.answer(key_message(row))


@dp.message(F.text)
async def by_email(message: Message) -> None:
    """Любое сообщение с почтой — попытка забрать покупку."""
    user_id = message.from_user.id
    if store.blocked(user_id):
        await message.answer(texts.TOO_MANY)
        return

    found = EMAIL_RE.search(message.text or "")
    if not found:
        await message.answer(texts.ASK_EMAIL, reply_markup=menu())
        return

    email = found.group(0)

    # Сначала монеты Togetherly: их коды живут в PocketBase, а не в журнале.
    tg_sent = await send_coin_codes(message, email, user_id)

    rows = store.claim(email, user_id)
    if not rows and tg_sent:
        return
    if not rows:
        # Промах засчитывается: почта — единственное доказательство покупки,
        # и перебирать чужие адреса, надеясь опередить покупателя, нельзя.
        store.note_miss(user_id)
        await message.answer(texts.NOT_FOUND, reply_markup=menu())
        return

    for row in rows:
        # Первая выдача — владельцу видно, кому ушёл ключ. Почта у покупки
        # одна, и если её кто-то узнал, лучше заметить это сразу, а не по
        # жалобе «оплатил, а ключ уже забрали».
        if row["claimed_by"] == user_id and _first_claim(row):
            await notify_owner(texts.claim_notice(
                row["email"], row["license_id"], user_id,
                message.from_user.username))
        await message.answer(key_message(row))


async def send_coin_codes(message: Message, email: str, user_id: int) -> bool:
    """Отдаёт коды монет Togetherly по почте покупателя.

    Код выдаётся один раз: запись помечается `given_to`. Повторное обращение
    честно говорит, что код уже забрали и когда — если это сделал не покупатель,
    он придёт с этим к владельцу, а не будет гадать.
    """
    try:
        token = tg_coins.auth()
        rows = tg_coins.codes_for_email(email, token)
    except Exception as err:                      # noqa: BLE001
        log.exception("PocketBase недоступен: %s", err)
        return False
    if not rows:
        return False

    fresh = [r for r in rows if not (r.get("given_to") or "")]
    if not fresh:
        last = rows[0]
        when = last.get("created", "")[:16].replace("T", " ")
        await message.answer(
            f"По вашим покупкам коды уже выданы: {len(rows)}. "
            f"Последний — {when}.\n\n"
            "Если это были не вы, напишите сюда же — разберёмся."
        )
        return True

    import time
    for row in fresh:
        pretty = row["code"]
        if len(pretty) == 10:                     # TGXXXXXXXX → TG-XXXX-XXXX
            pretty = f"{pretty[:2]}-{pretty[2:6]}-{pretty[6:]}"
        try:
            tg_coins._api(
                "PATCH",
                f"/api/collections/redeem_codes/records/{row['id']}",
                token,
                {"given_to": str(user_id), "given_at": int(time.time() * 1000)},
            )
        except Exception as err:                  # noqa: BLE001
            log.exception("не пометил выдачу: %s", err)
        await message.answer(
            f"🪙 <b>{row['coins']} монет в Togetherly</b>\n\n"
            f"Код: <code>{pretty}</code>\n\n"
            "Введите его в приложении: Профиль → Монеты → «У меня есть код»."
        )
        await notify_owner(
            f"🪙 Код на {row['coins']} монет выдан: {email} → tg {user_id}")
    return True


# ----------------------------- Запуск -----------------------------

# Синяя кнопка «Меню» в телеграме. Владельцу видны ещё три команды: список для
# него ставится отдельной областью, покупателям служебное показывать незачем.
COMMANDS = [
    BotCommand(command="start", description="🛍 Магазин"),
    BotCommand(command="buy", description="🛒 Что продаётся"),
    BotCommand(command="my", description="📦 Мои покупки"),
    BotCommand(command="help", description="❓ Помощь"),
]

OWNER_COMMANDS = COMMANDS + [
    BotCommand(command="stats", description="📊 Продажи"),
    BotCommand(command="find", description="🔍 Заказы по почте"),
    BotCommand(command="grant", description="🎁 Выдать ключ вручную"),
]


async def setup_commands(bot: Bot) -> None:
    """Меню команд и описание бота.

    Ошибка тут бота не останавливает: список команд — украшение, а выдача
    ключей работает и без него.
    """
    try:
        await bot.set_my_commands(COMMANDS, scope=BotCommandScopeDefault())
        if OWNER:
            await bot.set_my_commands(
                OWNER_COMMANDS, scope=BotCommandScopeChat(chat_id=OWNER))
        await bot.set_my_short_description(
            "Ключи к полным версиям приложений SnT")
        await bot.set_my_description(
            "Здесь выдаются ключи к полным версиям наших приложений.\n\n"
            "Оплатите покупку на lava.top, пришлите боту почту, которую "
            "указали при оплате, — и получите ключ. Покупка разовая, ключ "
            "работает на всех ваших устройствах."
        )
    except Exception:
        log.exception("меню команд не установилось")


async def main() -> None:
    global bot
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(message)s",
    )
    if not TOKEN:
        raise SystemExit("SNT_BOT_TOKEN не задан")
    if not WEBHOOK_KEY:
        log.warning("SNT_WEBHOOK_KEY пуст — вебхук будет отвечать 503")

    # Бот поднимается первым: вебхук с первой же секунды умеет писать владельцу.
    session = None
    if API_BASE:
        log.info("телеграм через %s", API_BASE)
        session = AiohttpSession(api=TelegramAPIServer.from_base(API_BASE))
    bot = Bot(TOKEN, session=session,
              default=DefaultBotProperties(parse_mode=ParseMode.HTML))
    await setup_commands(bot)

    app = web.Application()
    app.router.add_post("/lava", lava_webhook)
    app.router.add_get("/health", health)
    runner = web.AppRunner(app)
    await runner.setup()
    await web.TCPSite(runner, "127.0.0.1", WEBHOOK_PORT).start()
    log.info("вебхук слушает 127.0.0.1:%s/lava", WEBHOOK_PORT)

    if PULL_URL and PULL_KEY:
        log.info("очередь заказов: %s каждые %s с", PULL_URL, PULL_EVERY)
        asyncio.create_task(pull_loop())
    else:
        log.warning("SNT_PULL_URL/SNT_PULL_KEY пусты — очередь не опрашивается")

    try:
        await dp.start_polling(bot)
    finally:
        await runner.cleanup()


if __name__ == "__main__":
    asyncio.run(main())
