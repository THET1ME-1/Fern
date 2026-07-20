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


async def lava_webhook(request: web.Request) -> web.Response:
    if WEBHOOK_KEY and request.headers.get("X-Api-Key") != WEBHOOK_KEY:
        log.warning("вебхук с чужим ключом от %s", request.remote)
        return web.Response(status=401, text="bad key")

    try:
        payload = await request.json()
    except Exception:
        log.exception("вебхук: тело не разобралось")
        return web.Response(status=400, text="bad json")

    raw = json.dumps(payload, ensure_ascii=False)
    log.info("вебхук: %s", raw)

    order = parse_webhook(payload)
    if order is None:
        # Не оплата, отказ или событие без почты. Повторы делу не помогут,
        # поэтому 200: пусть lava.top не долбится двадцать раз. Событие в логе.
        return web.Response(text="ignored")

    product = resolve_product(order["product_id"])
    if not product:
        return web.Response(text="unknown product")

    if order["kind"] == "refund":
        row = store.refund(order["order_id"], order["email"])
        log.info("возврат %s (%s) — %s", order["order_id"], order["email"],
                 "заказ помечен" if row else "нечего помечать")
        if row is not None:
            await notify_owner(texts.refund_notice(
                order["email"], product["name"], row["license_id"]))
        return web.Response(text="ok")

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
    return web.Response(text="ok")


async def health(_: web.Request) -> web.Response:
    return web.Response(text="alive")


# ----------------------------- Бот -----------------------------

dp = Dispatcher()


def menu() -> InlineKeyboardMarkup:
    """Витрина магазина."""
    return InlineKeyboardMarkup(inline_keyboard=[
        [InlineKeyboardButton(text="🛒 Купить", url=BUY_URL)],
        [InlineKeyboardButton(text="🔑 Получить ключ", callback_data="claim")],
        [
            InlineKeyboardButton(text="📦 Мои ключи", callback_data="mykeys"),
            InlineKeyboardButton(text="❓ Помощь", callback_data="help"),
        ],
        [InlineKeyboardButton(text="🌿 Что даёт Fern Pro", callback_data="about")],
    ])


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


def key_message(row: sqlite3.Row) -> str:
    return texts.key_message(
        product_of(row).get("name", "Ключ"),
        row["license_id"],
        issue(row["license_id"], sku=row["sku"]),
    )


@dp.message(CommandStart())
async def start(message: Message) -> None:
    await message.answer(texts.WELCOME, reply_markup=menu())


@dp.message(Command("buy"))
async def cmd_buy(message: Message) -> None:
    await message.answer(texts.PRODUCT_CARD, reply_markup=back(buy=True))


@dp.callback_query(F.data == "menu")
async def cb_menu(query: CallbackQuery) -> None:
    await show(query, texts.WELCOME, menu())
    await query.answer()


@dp.callback_query(F.data == "about")
async def cb_about(query: CallbackQuery) -> None:
    await show(query, texts.PRODUCT_CARD, back(buy=True))
    await query.answer()


@dp.callback_query(F.data == "help")
async def cb_help(query: CallbackQuery) -> None:
    await show(query, texts.HELP, back())
    await query.answer()


@dp.callback_query(F.data == "claim")
async def cb_claim(query: CallbackQuery) -> None:
    await show(query, texts.ASK_EMAIL, back())
    await query.answer()


@dp.callback_query(F.data == "mykeys")
async def cb_mykeys(query: CallbackQuery) -> None:
    await send_keys(query.message, query.from_user.id)
    await query.answer()


@dp.message(Command("help"))
async def cmd_help(message: Message) -> None:
    await message.answer(HELP)


@dp.message(Command("key"))
async def cmd_key(message: Message) -> None:
    await send_keys(message, message.from_user.id)


async def send_keys(message: Message, user_id: int) -> None:
    rows = store.orders_of(user_id)
    if not rows:
        await message.answer(texts.NO_KEYS, reply_markup=menu())
        return
    for row in rows:
        await message.answer(key_message(row))


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

    rows = store.claim(found.group(0), user_id)
    if not rows:
        # Промах засчитывается: почта — единственное доказательство покупки,
        # и перебирать чужие адреса, надеясь опередить покупателя, нельзя.
        store.note_miss(user_id)
        await message.answer(texts.NOT_FOUND, reply_markup=menu())
        return

    for row in rows:
        await message.answer(key_message(row))


# ----------------------------- Запуск -----------------------------

# Синяя кнопка «Меню» в телеграме. Владельцу видны ещё три команды: список для
# него ставится отдельной областью, покупателям служебное показывать незачем.
COMMANDS = [
    BotCommand(command="start", description="🌿 Магазин"),
    BotCommand(command="buy", description="🛒 Что даёт Fern Pro"),
    BotCommand(command="key", description="📦 Мои ключи"),
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
        log.warning("SNT_WEBHOOK_KEY пуст — вебхук примет кого угодно")

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

    try:
        await dp.start_polling(bot)
    finally:
        await runner.cleanup()


if __name__ == "__main__":
    asyncio.run(main())
