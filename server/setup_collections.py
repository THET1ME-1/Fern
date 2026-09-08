#!/usr/bin/env python3
"""Коллекции Fern в PocketBase: аккаунты и заказы.

Запускается на VPS, повторный запуск ничего не ломает: существующие коллекции
дополняются недостающими полями, а не пересоздаются.

    PB_SUPERUSER_EMAIL=... PB_SUPERUSER_PASSWORD=... python3 setup_collections.py
    python3 setup_collections.py --dry     # показать, что было бы сделано

АККАУНТЫ FERN И TOGETHERLY НЕ СМЕШИВАЮТСЯ. `fern_users` — отдельная
коллекция: свои записи, свои сессии, свои токены. Общего с `users` у неё
только сервер, на котором она лежит.

ПОЧЕМУ КЛИЕНТ НЕ МОЖЕТ ПРАВИТЬ СВОЮ ЗАПИСЬ. PocketBase проверяет правила на
уровне записи, а не поля: разрешив человеку менять свою строку, мы разрешаем
ему вписать себе `pro_until` на сто лет вперёд. Поэтому `updateRule` пуст
(только суперюзер из хука), а всё, что человеку правда нужно, — вход,
регистрация и сброс пароля — идёт системными эндпоинтами, которым это правило
не требуется.
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.error
import urllib.request

PB_URL = os.environ.get("PB_URL", "http://127.0.0.1:8090").rstrip("/")

# Поля подписки. Их пишет только сервер.
ПОЛЯ_АККАУНТА = [
    {"type": "date", "name": "pro_until", "required": False},
    {"type": "select", "name": "pro_source", "required": False, "maxSelect": 1,
     "values": ["lava", "play", "apple", "grant"]},
    {"type": "select", "name": "pro_status", "required": False, "maxSelect": 1,
     "values": ["active", "cancelled", "expired", "refunded"]},
    {"type": "select", "name": "pro_plan", "required": False, "maxSelect": 1,
     "values": ["month", "year"]},
    {"type": "text", "name": "lava_contract", "required": False, "max": 0},
    {"type": "bool", "name": "lifetime", "required": False},
    {"type": "autodate", "name": "created", "onCreate": True, "onUpdate": False},
    {"type": "autodate", "name": "updated", "onCreate": True, "onUpdate": True},
]

ПОЛЯ_ЗАКАЗА = [
    {"type": "text", "name": "order_key", "required": True, "max": 0},
    {"type": "text", "name": "uid", "required": False, "max": 0},
    {"type": "select", "name": "source", "required": False, "maxSelect": 1,
     "values": ["lava", "play", "apple", "grant"]},
    {"type": "select", "name": "plan", "required": False, "maxSelect": 1,
     "values": ["month", "year"]},
    {"type": "select", "name": "status", "required": False, "maxSelect": 1,
     "values": ["pending", "paid", "failed", "cancelled", "refunded"]},
    {"type": "text", "name": "invoice_id", "required": False, "max": 0},
    {"type": "text", "name": "event", "required": False, "max": 0},
    {"type": "text", "name": "email", "required": False, "max": 0},
    {"type": "number", "name": "amount", "required": False},
    {"type": "text", "name": "currency", "required": False, "max": 0},
    {"type": "date", "name": "paid_at", "required": False},
    {"type": "date", "name": "until", "required": False},
    {"type": "json", "name": "raw", "required": False, "maxSize": 200000},
    # Даты заводятся явно: с PocketBase 0.23 системных created/updated у новых
    # коллекций нет, а быстрый проход синхронизации отбирает заказы по
    # `created` — без поля фильтр молча не находит ничего.
    {"type": "autodate", "name": "created", "onCreate": True, "onUpdate": False},
    {"type": "autodate", "name": "updated", "onCreate": True, "onUpdate": True},
]

КОЛЛЕКЦИИ = [
    {
        "name": "fern_users",
        "type": "auth",
        "fields": ПОЛЯ_АККАУНТА,
        # Читать человек может только себя; писать — никто, кроме сервера.
        "listRule": "id = @request.auth.id",
        "viewRule": "id = @request.auth.id",
        "createRule": "",       # регистрация открыта
        "updateRule": None,
        "deleteRule": None,
        "passwordAuth": {"enabled": True, "identityFields": ["email"]},
        "indexes": [],
    },
    {
        "name": "fern_orders",
        "type": "base",
        "fields": ПОЛЯ_ЗАКАЗА,
        # Служебная коллекция: наружу не видна вовсе.
        "listRule": None,
        "viewRule": None,
        "createRule": None,
        "updateRule": None,
        "deleteRule": None,
        # Повтор вебхука натыкается на уникальность и не продлевает дважды.
        "indexes": [
            "CREATE UNIQUE INDEX `idx_fern_orders_key` ON `fern_orders` (`order_key`)",
            "CREATE INDEX `idx_fern_orders_uid` ON `fern_orders` (`uid`)",
            "CREATE INDEX `idx_fern_orders_status` ON `fern_orders` (`status`)",
        ],
    },
]


def запрос(метод: str, путь: str, токен: str = "", данные=None):
    тело = json.dumps(данные).encode() if данные is not None else None
    req = urllib.request.Request(PB_URL + путь, data=тело, method=метод)
    req.add_header("Content-Type", "application/json")
    if токен:
        req.add_header("Authorization", токен)
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            return r.status, json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        сырое = e.read()
        try:
            return e.code, json.loads(сырое or b"{}")
        except json.JSONDecodeError:
            return e.code, {"raw": сырое.decode(errors="replace")[:400]}


def войти() -> str:
    почта = os.environ.get("PB_SUPERUSER_EMAIL", "")
    пароль = os.environ.get("PB_SUPERUSER_PASSWORD", "")
    if not почта or not пароль:
        raise SystemExit("нужны PB_SUPERUSER_EMAIL и PB_SUPERUSER_PASSWORD")
    код, ответ = запрос("POST", "/api/collections/_superusers/auth-with-password",
                        данные={"identity": почта, "password": пароль})
    if код != 200:
        raise SystemExit(f"вход суперюзера не удался: {код} {ответ}")
    return ответ["token"]


def получить(токен: str, имя: str):
    код, ответ = запрос("GET", f"/api/collections/{имя}", токен)
    return ответ if код == 200 else None


def применить(токен: str, описание: dict, всухую: bool) -> str:
    имя = описание["name"]
    текущая = получить(токен, имя)
    if текущая is None:
        if всухую:
            return f"{имя}: была бы создана"
        код, ответ = запрос("POST", "/api/collections", токен, описание)
        if код != 200:
            raise SystemExit(f"{имя}: создать не вышло — {код} {ответ}")
        return f"{имя}: создана"

    # Коллекция есть: дополняем недостающие поля, ничего не удаляя. Полная
    # замена схемы снесла бы данные, а этот скрипт обязан быть безопасным на
    # боевом сервере.
    свои = {f["name"] for f in текущая.get("fields", [])}
    добавить = [f for f in описание["fields"] if f["name"] not in свои]
    if not добавить:
        return f"{имя}: уже на месте"
    if всухую:
        return f"{имя}: добавились бы поля {[f['name'] for f in добавить]}"
    текущая["fields"] = текущая.get("fields", []) + добавить
    код, ответ = запрос("PATCH", f"/api/collections/{имя}", токен, текущая)
    if код != 200:
        raise SystemExit(f"{имя}: дополнить не вышло — {код} {ответ}")
    return f"{имя}: добавлены поля {[f['name'] for f in добавить]}"


def main() -> None:
    ap = argparse.ArgumentParser(description="Коллекции Fern в PocketBase")
    ap.add_argument("--dry", action="store_true", help="только показать план")
    args = ap.parse_args()

    токен = войти()
    for описание in КОЛЛЕКЦИИ:
        print(применить(токен, описание, args.dry))

    # Проверка, ради которой всё затевалось: коллекция Togetherly не тронута.
    users = получить(токен, "users")
    if users is None:
        print("ВНИМАНИЕ: коллекция users Togetherly не отвечает", file=sys.stderr)
        raise SystemExit(1)
    print(f"users Togetherly на месте, полей {len(users.get('fields', []))}")


if __name__ == "__main__":
    main()
