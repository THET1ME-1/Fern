#!/usr/bin/env python3
"""Монеты Togetherly: товар lava.top → код пополнения в PocketBase.

Отличие от ключей Fern: у Togetherly есть свой сервер, и баланс живёт там.
Поэтому здесь не подписанный офлайн-ключ, а одноразовый код — гасит его
PocketBase (`pb_hooks/redeem.pb.js`), а бот только создаёт и показывает.

Так код нельзя предъявить дважды: погашение помечает запись внутри
транзакции, и второй аккаунт получит отказ.

Переменные окружения:
    TG_PB_URL       https://togetherly.duckdns.org   (по умолчанию)
    TG_PB_EMAIL     суперюзер PocketBase
    TG_PB_PASSWORD  его пароль
"""
from __future__ import annotations

import json
import os
import secrets
import urllib.error
import urllib.request

PB_URL = os.environ.get("TG_PB_URL", "https://togetherly.duckdns.org").rstrip("/")

# Товары на lava.top → сколько монет начислить.
PRODUCTS = {
    "4d8ff539-fd74-47ab-85e4-35906be3a5b4": 600,
    "64e68f3f-7281-4593-aa00-0b438522750b": 1400,
    "cd2e08ec-e826-495d-bb55-842a3e3742dc": 4000,
}

# Без 0/O и 1/I: код диктуют голосом и вводят руками с телефона.
ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"


def coins_for(product_id: str | None) -> int | None:
    """Сколько монет за товар. None — товар не наш (в боте другие приложения)."""
    if not product_id:
        return None
    return PRODUCTS.get(str(product_id).strip().lower())


def make_code() -> str:
    """Код вида TG-XXXX-XXXX: две группы по четыре символа читаются вслух."""
    body = "".join(secrets.choice(ALPHABET) for _ in range(8))
    return f"TG-{body[:4]}-{body[4:]}"


def normalize(code: str) -> str:
    """К виду, в котором код лежит в базе: без пробелов, дефисов и регистра.

    Тот же разбор делает серверный роут, иначе «tg-4f2a b19c» не нашлось бы.
    """
    return "".join(ch for ch in str(code).upper() if ch.isalnum())


# ── PocketBase ──────────────────────────────────────────────────────────────

def _api(method: str, path: str, token: str | None = None, body=None):
    req = urllib.request.Request(
        PB_URL + path,
        data=json.dumps(body).encode() if body is not None else None,
        method=method,
    )
    req.add_header("Content-Type", "application/json")
    if token:
        req.add_header("Authorization", token)
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            raw = r.read().decode()
            return r.status, (json.loads(raw) if raw else {})
    except urllib.error.HTTPError as e:
        raw = e.read().decode()
        try:
            return e.code, json.loads(raw)
        except ValueError:
            return e.code, {"raw": raw}


def auth() -> str:
    """Токен суперюзера. Коды пишет только он — коллекция закрыта правилами."""
    email = os.environ["TG_PB_EMAIL"]
    password = os.environ["TG_PB_PASSWORD"]
    st, data = _api("POST", "/api/collections/_superusers/auth-with-password",
                    body={"identity": email, "password": password})
    if st != 200 or "token" not in data:
        raise RuntimeError(f"PocketBase не пустил: {st} {data}")
    return data["token"]


def create_code(product_id: str, email: str, order_id: str | None = None,
                token: str | None = None) -> tuple[str, int] | None:
    """Заводит код на покупку. Возвращает (код, монеты) либо None, если товар чужой.

    Вызывается в момент оплаты, а не когда покупатель придёт за кодом: если бот
    перезапустится, код уже лежит в базе и не потеряется.
    """
    amount = coins_for(product_id)
    if amount is None:
        return None
    token = token or auth()

    # Коллизия кода почти невозможна, но уникальный индекс её отобьёт — тогда
    # пробуем другой, а не падаем на покупателе.
    for _ in range(5):
        code = make_code()
        st, data = _api("POST", "/api/collections/redeem_codes/records", token, {
            "code": normalize(code),
            "coins": amount,
            "sku": str(product_id).lower(),
            "buyer_email": (email or "").strip().lower(),
        })
        if st in (200, 201):
            return code, amount
        if st != 400:
            raise RuntimeError(f"не удалось создать код: {st} {data}")
    raise RuntimeError("не удалось подобрать свободный код")


def codes_for_email(email: str, token: str | None = None) -> list[dict]:
    """Все коды покупателя — по ним бот отвечает на повторные обращения."""
    token = token or auth()
    q = urllib.parse.quote(f'buyer_email="{(email or "").strip().lower()}"')
    st, data = _api("GET",
                    f"/api/collections/redeem_codes/records?filter={q}&sort=-created",
                    token)
    if st != 200:
        return []
    return data.get("items", [])


import urllib.parse  # noqa: E402  (нужен только в codes_for_email)
