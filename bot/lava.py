#!/usr/bin/env python3
"""Разбор вебхука lava.top.

Вынесено из `bot.py` отдельным модулем по двум причинам: это самое хрупкое
место всей схемы, и проверять его надо без телеграма и без сети.

Имена полей в документации lava.top описаны словами, а не схемой, и вполне
могут разойтись с тем, что приходит на самом деле. Поэтому значения ищутся по
всей структуре, а не по фиксированному пути, а сырой payload бот кладёт в
журнал и в лог — сверить по первой же продаже и, если надо, ужесточить.
"""
from __future__ import annotations

import re

EMAIL_RE = re.compile(r"[^@\s]+@[^@\s]+\.[a-zA-Z]{2,}")

# Ключи, под которыми может приехать идентификатор заказа, товара и суммы.
# Порядок задаёт приоритет. Запись «a.b» ищет путь целиком, «^a» — только на
# верхнем уровне.
#
# Безликий `id` берём ТОЛЬКО с верхнего уровня. Вложенный `product.id` у всех
# покупателей одинаков, и приняв его за номер заказа, бот счёл бы вторую
# продажу повтором первой и не выдал бы ключ.
ORDER_KEYS = ("contractid", "invoiceid", "orderid", "paymentid", "^id")
PRODUCT_KEYS = ("productid", "offerid", "product.id", "offer.id", "parentid", "uuid")
AMOUNT_KEYS = ("amount", "total", "sum")

# По этим полям судим, оплата ли это и удачная ли.
STATUS_KEYS = ("eventtype", "event", "status", "state", "type")
GOOD = ("success", "completed", "complete", "paid", "active", "subscription-active")
BAD = ("fail", "cancel", "error", "declin", "refund", "reject", "chargeback")
# Возврат стоит особняком среди неудач: за отказом ключа никто не получал, а за
# возвратом — получал, и владельцу пора вносить номер в `revoked`.
REFUND = ("refund", "chargeback", "returned")


def walk(node, path: str = ""):
    """Обходит вложенные словари и списки, отдавая пары (путь, значение)."""
    if isinstance(node, dict):
        for k, v in node.items():
            yield from walk(v, f"{path}.{k}" if path else str(k))
    elif isinstance(node, list):
        for i, v in enumerate(node):
            yield from walk(v, f"{path}[{i}]")
    else:
        yield path, node


def find_email(payload) -> str | None:
    """Первое значение, похожее на адрес почты."""
    for _, value in walk(payload):
        if isinstance(value, str) and EMAIL_RE.fullmatch(value.strip()):
            return value.strip().lower()
    return None


def _matches(path: str, name: str) -> bool:
    """Подходит ли путь под образец имени."""
    low = path.lower()
    if name.startswith("^"):            # только верхний уровень
        return low == name[1:]
    if "." in name:                     # хвост пути целиком
        return low.endswith("." + name) or low == name
    return low.split(".")[-1] == name   # лист с таким именем где угодно


def find_by_keys(payload, names: tuple[str, ...]) -> str | None:
    """Значение по первому подошедшему образцу из [names].

    Порядок образцов задаёт приоритет: `contractId` важнее безликого `id`,
    который может оказаться идентификатором чего угодно.
    """
    found: dict[str, str] = {}
    for path, value in walk(payload):
        if not isinstance(value, (str, int, float)):
            continue
        text = str(value).strip()
        if not text:
            continue
        for name in names:
            if name not in found and _matches(path, name):
                found[name] = text
    for name in names:
        if name in found:
            return found[name]
    return None


def status_marker(payload) -> str:
    """Все статусные поля payload одной строкой в нижнем регистре."""
    return " ".join(
        str(v).lower()
        for path, v in walk(payload)
        if path.split(".")[-1].lower() in STATUS_KEYS and isinstance(v, (str, int))
    )


def is_success(payload) -> bool:
    """Успешная оплата. Отказ, отмена и возврат сюда не проходят."""
    marker = status_marker(payload)
    if not marker:
        return False
    if any(w in marker for w in BAD):
        return False
    return any(w in marker for w in GOOD)


def is_refund(payload) -> bool:
    """Возврат денег или спор по карте."""
    return any(w in status_marker(payload) for w in REFUND)


def parse(payload) -> dict | None:
    """Событие из вебхука либо None, если оно бота не касается.

    Поле `kind`: `paid` — выдать ключ, `refund` — ключ пора отзывать.

    Без почты событие бесполезно: она единственная связывает платёж с человеком,
    который придёт за ключом.
    """
    if is_refund(payload):
        kind = "refund"
    elif is_success(payload):
        kind = "paid"
    else:
        return None
    email = find_email(payload)
    if not email:
        return None
    return {
        "kind": kind,
        "email": email,
        "order_id": find_by_keys(payload, ORDER_KEYS),
        "product_id": find_by_keys(payload, PRODUCT_KEYS),
        "amount": find_by_keys(payload, AMOUNT_KEYS),
    }
