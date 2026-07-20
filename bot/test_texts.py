#!/usr/bin/env python3
"""Проверка сообщений бота: python3 bot/test_texts.py

Тексты вынесены из `bot.py`, чтобы проверять их без aiogram и без сети. Ошибка
здесь стоит дорого: сообщение о возврате без номера лицензии владельцу
бесполезно, а незакрытый угловой скобкой адрес почты роняет отправку целиком —
телеграм разбирает эти сообщения как HTML.
"""
from texts import (
    HELP,
    PRODUCT_CARD,
    WELCOME,
    escape,
    key_message,
    order_line,
    refund_notice,
    sale_notice,
)

checks = 0


def check(label, got, want):
    global checks
    assert got == want, f"{label}: получено {got!r}, ожидалось {want!r}"
    checks += 1


def has(label, text, needle):
    global checks
    assert needle in text, f"{label}: в тексте нет {needle!r}\n{text}"
    checks += 1


# --- разметка ---
check("угловые скобки обезврежены", escape("a<b>c"), "a&lt;b&gt;c")
check("амперсанд обезврежен", escape("a&b"), "a&amp;b")
check("пустое место", escape(None), "")

# --- продажа ---
sale = sale_notice(email="Buyer@example.com", product="Fern Pro", amount="5.0",
                   order_id="ORD-1")
has("в продаже видна почта", sale, "Buyer@example.com")
has("в продаже виден товар", sale, "Fern Pro")
has("в продаже видна сумма", sale, "5.0")

broken = sale_notice(email="a<b>@example.com", product="Fern Pro", amount=None,
                     order_id=None)
has("почта со скобками не ломает разметку", broken, "a&lt;b&gt;@example.com")
check("сырых скобок в сообщении нет", "<b>@example.com" in broken, False)

# --- возврат ---
back = refund_notice(email="buyer@example.com", product="Fern Pro", license_id=42)
has("в возврате виден номер лицензии", back, "42")
has("в возврате сказано, что делать", back, "revoked")

never = refund_notice(email="buyer@example.com", product="Fern Pro",
                      license_id=None)
has("возврат до выдачи ключа отмечен отдельно", never, "не выдавался")
check("несуществующего номера в тексте нет", "revoked" in never, False)

# --- ключ покупателю ---
msg = key_message(product="Fern Pro", license_id=7, key="FERNAAAA")
has("покупателю виден товар", msg, "Fern Pro")
has("покупателю виден номер", msg, "7")
has("ключ отдан моноширинным блоком", msg, "<code>FERNAAAA</code>")

# --- витрина ---
has("приветствие зовёт прислать почту", WELCOME, "почт")
has("помощь объясняет активацию", HELP, "У меня есть ключ")
has("карточка обещает книги", PRODUCT_CARD, "EPUB")
has("карточка обещает видео", PRODUCT_CARD, "убтитр")
has("карточка обещает импорт из Anki", PRODUCT_CARD, "Anki")
has("карточка обещает покупку навсегда", PRODUCT_CARD, "навсегда")
# Цена живёт на lava.top: две цены в двух местах однажды разойдутся.
check("цены в карточке нет", "₽" in PRODUCT_CARD or "$" in PRODUCT_CARD, False)

# --- строка заказа для владельца ---
# Четыре состояния, в которых заказ вообще бывает. Владелец разбирает жалобу
# «оплатил, ключа нет» по этой строке, поэтому она обязана их различать.
row = {"order_id": "ORD-1", "created": "2026-07-20T10:00:00+00:00",
       "amount": "5.0", "license_id": None, "claimed_by": None,
       "refunded_at": None}
has("заказ без ключа", order_line(row), "ключ не выдан")
has("выданный, но не забранный", order_line({**row, "license_id": 7}),
    "не забран")
has("забранный виден с получателем",
    order_line({**row, "license_id": 7, "claimed_by": 4242}), "4242")
has("возврат виден сразу",
    order_line({**row, "license_id": 7, "refunded_at": "2026-07-21T10:00:00"}),
    "возврат")
has("в строке есть дата", order_line(row), "2026-07-20")
has("почта со скобками не ломает строку",
    order_line({**row, "order_id": "<b>"}), "&lt;b&gt;")

print(f"все проверки пройдены: {checks}")
