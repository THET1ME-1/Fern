#!/usr/bin/env python3
"""Проверка описания коллекций: python3 server/test_setup_collections.py

Сети не требует: проверяется само описание, до похода в PocketBase.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import setup_collections as sc  # noqa: E402

checks = 0


def check(label, got, want):
    global checks
    assert got == want, f"{label}: получено {got!r}, ожидалось {want!r}"
    checks += 1


коллекции = {c["name"]: c for c in sc.КОЛЛЕКЦИИ}

# --- аккаунты Fern отдельны от Togetherly ---
check("коллекция аккаунтов названа своим именем", "fern_users" in коллекции, True)
check("коллекция users Togetherly не описывается здесь", "users" in коллекции, False)

акк = коллекции["fern_users"]
check("тип auth", акк["type"], "auth")
check("регистрация открыта", акк["createRule"], "")
check("читать можно только себя", акк["viewRule"], "id = @request.auth.id")

# Главная защита: человек не может вписать себе срок подписки.
check("править запись клиенту нельзя", акк["updateRule"], None)
check("удалять запись клиенту нельзя", акк["deleteRule"], None)

поля = {f["name"]: f for f in акк["fields"]}
for имя in ("pro_until", "pro_source", "pro_status", "pro_plan",
            "lava_contract", "lifetime"):
    check(f"поле {имя} описано", имя in поля, True)
check("срок — дата", поля["pro_until"]["type"], "date")
check("источник ограничен списком", sorted(поля["pro_source"]["values"]),
      ["apple", "grant", "lava", "play"])
check("тарифа ровно два", sorted(поля["pro_plan"]["values"]), ["month", "year"])

# --- заказы: служебная коллекция, наружу закрыта целиком ---
зак = коллекции["fern_orders"]
check("заказы наружу не видны", zak_rules := [зак["listRule"], зак["viewRule"],
                                              зак["createRule"], зак["updateRule"],
                                              зак["deleteRule"]],
      [None, None, None, None, None])

поля_з = {f["name"]: f for f in зак["fields"]}
for имя in ("order_key", "uid", "source", "plan", "status", "invoice_id",
            "event", "email", "amount", "currency", "paid_at", "until", "raw"):
    check(f"поле заказа {имя} описано", имя in поля_з, True)

# Идемпотентность вебхука держится на этом индексе.
индексы = " ".join(зак["indexes"])
check("ключ заказа уникален",
      "UNIQUE INDEX" in индексы and "order_key" in индексы, True)

print(f"setup_collections: {checks} проверок пройдено")
