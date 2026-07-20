#!/usr/bin/env python3
"""Бот продажи Fern Pro за звёзды Telegram.

Зачем он вообще нужен: Google Play не принимает платежи из России, а звёзды
покупаются там и картой «Мир», и через СБП. Бот берёт оплату, выдаёт
подписанный ключ и записывает покупку в журнал; приложение проверяет ключ
офлайн (`app/lib/services/license_service.dart`).

Звёзды выводятся владельцем через Fragment (минимум 1000 звёзд, выдержка
21 день) — бот в этом не участвует.

Запуск:
    export FERN_BOT_TOKEN=...      # токен от @BotFather
    export FERN_BOT_OWNER=...      # ваш telegram id: журнал и возвраты
    python3 bot/bot.py
"""
from __future__ import annotations

import asyncio
import logging
import os
import sqlite3
from contextlib import closing
from datetime import datetime, timezone
from pathlib import Path

from aiogram import Bot, Dispatcher, F
from aiogram.filters import Command
from aiogram.types import (
    LabeledPrice,
    Message,
    PreCheckoutQuery,
)

from license import issue

TOKEN = os.environ.get("FERN_BOT_TOKEN", "")
OWNER = int(os.environ.get("FERN_BOT_OWNER", "0"))
DB_PATH = Path(os.environ.get("FERN_BOT_DB", Path(__file__).parent / "purchases.db"))

# Цена в звёздах. Ориентир: 1 звезда ≈ 0,013 $, то есть 300 ≈ 4 $ — примерно
# столько же, сколько Pro стоит в Google Play.
PRICE_STARS = int(os.environ.get("FERN_BOT_PRICE", "300"))

WELCOME = (
    "<b>Fern Pro</b>\n\n"
    "Открывает обучение на своём материале:\n"
    "• книги EPUB, FB2, TXT — тап по слову даёт перевод и карточку\n"
    "• видео с субтитрами, статьи по ссылке, текст с фотографии\n"
    "• перенос колод из Anki и таблиц CSV\n\n"
    "Покупка разовая: ключ остаётся у вас навсегда и работает на всех "
    "ваших устройствах.\n\n"
    f"Цена — {PRICE_STARS} ⭐. Нажмите кнопку ниже."
)

HOW_TO_USE = (
    "Скопируйте ключ целиком и вставьте в приложении:\n"
    "<b>Настройки → Fern Pro → У меня есть ключ</b>\n\n"
    "Ключ можно вставить кнопкой «Вставить из буфера» — приложение само "
    "проверит его и откроет Pro."
)

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(message)s")
log = logging.getLogger("fern-bot")


# ── Журнал покупок ──────────────────────────────────────────────────────────

def db() -> sqlite3.Connection:
    conn = sqlite3.connect(DB_PATH)
    conn.execute("""
        CREATE TABLE IF NOT EXISTS purchases (
            license_id  INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id     INTEGER NOT NULL,
            username    TEXT,
            stars       INTEGER NOT NULL,
            charge_id   TEXT,
            created_at  TEXT NOT NULL,
            refunded_at TEXT
        )""")
    conn.execute("CREATE INDEX IF NOT EXISTS purchases_user ON purchases(user_id)")
    return conn


def record_purchase(user_id: int, username: str | None, stars: int,
                    charge_id: str | None) -> int:
    """Записывает покупку и возвращает номер лицензии.

    Номер = первичный ключ журнала. По нему покупку находят в поддержке и им же
    лицензию отзывают, если ключ утёк.
    """
    with closing(db()) as conn, conn:
        cur = conn.execute(
            "INSERT INTO purchases(user_id, username, stars, charge_id, created_at) "
            "VALUES (?, ?, ?, ?, ?)",
            (user_id, username, stars, charge_id,
             datetime.now(timezone.utc).isoformat(timespec="seconds")))
        return int(cur.lastrowid)


def purchases_of(user_id: int) -> list[tuple[int, str]]:
    with closing(db()) as conn:
        return [(row[0], row[1]) for row in conn.execute(
            "SELECT license_id, created_at FROM purchases "
            "WHERE user_id = ? AND refunded_at IS NULL ORDER BY license_id",
            (user_id,))]


# ── Бот ─────────────────────────────────────────────────────────────────────

dp = Dispatcher()


@dp.message(Command("start"))
async def start(message: Message, bot: Bot) -> None:
    await message.answer(WELCOME, parse_mode="HTML")
    await send_invoice(message, bot)


async def send_invoice(message: Message, bot: Bot) -> None:
    await bot.send_invoice(
        chat_id=message.chat.id,
        title="Fern Pro",
        description="Книги, видео и статьи в Fern. Разовая покупка, навсегда.",
        payload=f"fern_pro:{message.from_user.id}",
        currency="XTR",                      # звёзды Telegram
        prices=[LabeledPrice(label="Fern Pro", amount=PRICE_STARS)],
    )


@dp.message(Command("buy"))
async def buy(message: Message, bot: Bot) -> None:
    await send_invoice(message, bot)


@dp.pre_checkout_query()
async def pre_checkout(query: PreCheckoutQuery) -> None:
    # Проверять нечего: товар один и всегда в наличии. Отвечать обязательно —
    # без ответа за 10 секунд Telegram отменит платёж.
    await query.answer(ok=True)


@dp.message(F.successful_payment)
async def paid(message: Message) -> None:
    payment = message.successful_payment
    user = message.from_user
    license_id = record_purchase(
        user.id, user.username, payment.total_amount,
        payment.telegram_payment_charge_id)
    key = issue(license_id)
    log.info("покупка №%s от %s (%s звёзд)", license_id, user.id, payment.total_amount)

    await message.answer(
        f"Спасибо! Ваш ключ №{license_id}:\n\n<code>{key}</code>",
        parse_mode="HTML")
    await message.answer(HOW_TO_USE, parse_mode="HTML")
    if OWNER:
        await message.bot.send_message(
            OWNER, f"Покупка №{license_id}: @{user.username or user.id}, "
                   f"{payment.total_amount} ⭐")


@dp.message(Command("key"))
async def my_key(message: Message) -> None:
    """Повторная выдача: люди теряют переписку, а ключ у них уже оплачен."""
    rows = purchases_of(message.from_user.id)
    if not rows:
        await message.answer("Покупок не нашлось. Купить: /buy")
        return
    for license_id, created in rows:
        await message.answer(
            f"Ключ №{license_id} (куплен {created[:10]}):\n\n"
            f"<code>{issue(license_id)}</code>",
            parse_mode="HTML")


@dp.message(Command("help"))
async def help_cmd(message: Message) -> None:
    await message.answer(
        "/buy — купить Fern Pro\n"
        "/key — прислать купленный ключ ещё раз\n"
        "/help — эта справка\n\n" + HOW_TO_USE, parse_mode="HTML")


@dp.message(Command("stats"))
async def stats(message: Message) -> None:
    if message.from_user.id != OWNER:
        return
    with closing(db()) as conn:
        total, stars = conn.execute(
            "SELECT COUNT(*), COALESCE(SUM(stars), 0) FROM purchases "
            "WHERE refunded_at IS NULL").fetchone()
        last = conn.execute(
            "SELECT license_id, username, created_at FROM purchases "
            "ORDER BY license_id DESC LIMIT 5").fetchall()
    lines = [f"Покупок: {total}, звёзд: {stars}"]
    lines += [f"№{i} @{u or '—'} {c[:10]}" for i, u, c in last]
    await message.answer("\n".join(lines))


@dp.message(Command("refund"))
async def refund(message: Message, bot: Bot) -> None:
    """Возврат звёзд: `/refund <номер лицензии>`. Только владельцу.

    После возврата номер лицензии надо внести в `revoked` в
    `license_service.dart` и выпустить обновление — иначе выданный ключ
    продолжит работать.
    """
    if message.from_user.id != OWNER:
        return
    parts = (message.text or "").split()
    if len(parts) != 2 or not parts[1].isdigit():
        await message.answer("Формат: /refund <номер лицензии>")
        return
    license_id = int(parts[1])
    with closing(db()) as conn:
        row = conn.execute(
            "SELECT user_id, charge_id FROM purchases WHERE license_id = ?",
            (license_id,)).fetchone()
    if row is None:
        await message.answer(f"Лицензии №{license_id} нет в журнале")
        return
    user_id, charge_id = row
    try:
        await bot.refund_star_payment(user_id=user_id,
                                      telegram_payment_charge_id=charge_id)
    except Exception as e:  # noqa: BLE001 — показываем причину владельцу
        await message.answer(f"Возврат не прошёл: {e}")
        return
    with closing(db()) as conn, conn:
        conn.execute("UPDATE purchases SET refunded_at = ? WHERE license_id = ?",
                     (datetime.now(timezone.utc).isoformat(timespec="seconds"),
                      license_id))
    await message.answer(
        f"Звёзды за №{license_id} возвращены.\n"
        f"Не забудьте добавить {license_id} в `revoked` в license_service.dart")


async def main() -> None:
    if not TOKEN:
        raise SystemExit("нет FERN_BOT_TOKEN")
    bot = Bot(TOKEN)
    log.info("бот запущен, цена %s звёзд, журнал %s", PRICE_STARS, DB_PATH)
    await dp.start_polling(bot)


if __name__ == "__main__":
    asyncio.run(main())
