#!/usr/bin/env python3
"""Удаление аккаунта Fern. Запускается НА СЕРВЕРЕ, суперюзер не нужен:

    python3 test_fern_account_delete.py

Регистрация в `fern_users` открыта, поэтому пробный аккаунт заводится тем же
путём, что и у человека в приложении, и тем же роутом удаляется. Если прогон
упал посередине, пробный аккаунт остаётся — следующий прогон его подберёт
входом и удалит.
"""
from __future__ import annotations

import json
import os
import sqlite3
import urllib.error
import urllib.request
from datetime import datetime, timedelta, timezone

PB = os.environ.get("PB_URL", "http://127.0.0.1:8090").rstrip("/")
БАЗА = os.environ.get("PB_DB", "/opt/pocketbase/pb_data/data.db")
ПРОБА = "probe-delete-fern@example.com"
ПАРОЛЬ = "пробаproba123"

checks = 0


def check(label, got, want):
    global checks
    assert got == want, f"{label}: получено {got!r}, ожидалось {want!r}"
    checks += 1


def q(метод, путь, токен="", данные=None):
    тело = json.dumps(данные).encode() if данные is not None else None
    req = urllib.request.Request(PB + путь, data=тело, method=метод)
    req.add_header("Content-Type", "application/json")
    if токен:
        req.add_header("Authorization", токен)
    try:
        with urllib.request.urlopen(req, timeout=25) as r:
            return r.status, json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        сырое = e.read()
        try:
            return e.code, json.loads(сырое or b"{}")
        except json.JSONDecodeError:
            return e.code, {"raw": сырое.decode(errors="replace")[:300]}


def войти():
    код, ответ = q("POST", "/api/collections/fern_users/auth-with-password",
                   данные={"identity": ПРОБА, "password": ПАРОЛЬ})
    return код, ответ.get("token", "")


def главное():
    # Остаток прошлого упавшего прогона: входим и удаляем тем же роутом.
    код, токен = войти()
    if код == 200:
        q("POST", "/api/fern/account/delete", токен)

    код, _ = q("POST", "/api/collections/fern_users/records",
               данные={"email": ПРОБА, "password": ПАРОЛЬ,
                       "passwordConfirm": ПАРОЛЬ})
    check("пробный аккаунт заведён", код, 200)
    код, токен = войти()
    check("вход пробным аккаунтом", код, 200)

    try:
        check("без сессии не удалить", q("POST", "/api/fern/account/delete")[0], 401)

        # Живая подписка lava: суперюзера нет, поэтому срок пишем прямо в
        # базу. Роут обязан отказать, иначе списания пойдут на пустоту.
        завтра = (datetime.now(timezone.utc) + timedelta(days=1)).strftime(
            "%Y-%m-%d 00:00:00.000Z")
        база = sqlite3.connect(БАЗА)
        база.execute("UPDATE fern_users SET lava_contract='probe-contract', "
                     "pro_status='active', pro_until=? WHERE email=?",
                     (завтра, ПРОБА))
        база.commit()
        код, ответ = q("POST", "/api/fern/account/delete", токен)
        check("живую подписку lava удалить нельзя", код, 409)
        check("причина названа", ответ.get("error"), "active_subscription")
        база.execute("UPDATE fern_users SET lava_contract='', pro_status='', "
                     "pro_until='' WHERE email=?", (ПРОБА,))
        база.commit()
        база.close()

        код, ответ = q("POST", "/api/fern/account/delete", токен)
        check("удаление прошло", код, 200)
        check("ответ подтверждает", ответ.get("ok"), True)

        код, _ = войти()
        check("войти удалённым аккаунтом нельзя", код, 400)

        # Та же почта регистрируется заново: удаление не оставляет хвостов,
        # которые держали бы адрес занятым.
        код, _ = q("POST", "/api/collections/fern_users/records",
                   данные={"email": ПРОБА, "password": ПАРОЛЬ,
                           "passwordConfirm": ПАРОЛЬ})
        check("почта свободна после удаления", код, 200)
    finally:
        код, токен = войти()
        if код == 200:
            q("POST", "/api/fern/account/delete", токен)

    print(f"fern_account_delete: {checks} проверок пройдено")


if __name__ == "__main__":
    главное()
