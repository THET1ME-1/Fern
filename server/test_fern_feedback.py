#!/usr/bin/env python3
"""Обращение из Fern: `POST /api/fern/feedback`. Запускается НА СЕРВЕРЕ:

    python3 test_fern_feedback.py

Отказы проверяются без следов. Принятое обращение одно: от пробного аккаунта,
чтобы увидеть, что почта для ответа берётся из него. Его запись удаляется в
конце, а письмо с пометкой «можно удалить» дойдёт до ящика поддержки — это и
есть проверка доставки.
"""
from __future__ import annotations

import json
import os
import sqlite3
import urllib.error
import urllib.request

PB = os.environ.get("PB_URL", "http://127.0.0.1:8090").rstrip("/")
БАЗА = os.environ.get("PB_DB", "/opt/pocketbase/pb_data/data.db")
ПРОБА = "probe-feedback-fern@example.com"
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
        with urllib.request.urlopen(req, timeout=40) as r:
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
    хорошее = {"kind": "bug", "text": "Проверка приёма обращений Fern, можно удалить.",
               "app": "1.27.0", "platform": "android", "lang": "ru"}
    путь = "/api/fern/feedback"

    check("чужой вид отбит", q("POST", путь, данные={**хорошее, "kind": "spam"}),
          (400, {"ok": False, "error": "bad_kind"}))
    check("короткий текст отбит", q("POST", путь, данные={**хорошее, "text": "коротко"})[0], 400)
    check("кривая почта отбита", q("POST", путь, данные={**хорошее, "email": "не почта"}),
          (400, {"ok": False, "error": "bad_email"}))

    код, токен = войти()
    if код != 200:
        q("POST", "/api/collections/fern_users/records",
          данные={"email": ПРОБА, "password": ПАРОЛЬ, "passwordConfirm": ПАРОЛЬ})
        код, токен = войти()
    check("пробный аккаунт вошёл", код, 200)

    номер = ""
    try:
        код, ответ = q("POST", путь, токен, хорошее)
        check("обращение принято", код, 200)
        check("ответ уйдёт на почту аккаунта", ответ.get("email"), ПРОБА)
        номер = ответ.get("id", "")

        база = sqlite3.connect(БАЗА)
        строка = база.execute(
            "SELECT kind, email, uid != '' FROM fern_feedback WHERE id = ?", (номер,)).fetchone()
        база.close()
        check("обращение записано с аккаунтом", строка, ("bug", ПРОБА, 1))
    finally:
        if номер:
            база = sqlite3.connect(БАЗА)
            база.execute("DELETE FROM fern_feedback WHERE id = ?", (номер,))
            база.commit()
            база.close()
        q("POST", "/api/fern/account/delete", токен)

    print(f"fern_feedback: {checks} проверок пройдено")


if __name__ == "__main__":
    главное()
