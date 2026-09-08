#!/usr/bin/env python3
"""Проверка роутов подписки Fern. Запускается НА СЕРВЕРЕ:

    PB_SUPERUSER_EMAIL=... PB_SUPERUSER_PASSWORD=... python3 test_fern_routes.py

Ходит по живому PocketBase на loopback, заводит пробный аккаунт и убирает его
за собой. Настоящую оплату не делает: счёт lava создаётся только там, где для
этого есть офферы, и проверяется отдельным ключом `--lava`.
"""
from __future__ import annotations

import argparse
import json
import os
import urllib.error
import urllib.request
from datetime import datetime, timedelta, timezone

PB = os.environ.get("PB_URL", "http://127.0.0.1:8090").rstrip("/")
ПРОБА = "probe-routes-fern@example.com"
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


def главное():
    ap = argparse.ArgumentParser()
    ap.add_argument("--lava", action="store_true",
                    help="создать настоящий счёт (нужны офферы в окружении)")
    args = ap.parse_args()

    почта = os.environ["PB_SUPERUSER_EMAIL"]
    пароль = os.environ["PB_SUPERUSER_PASSWORD"]
    su = q("POST", "/api/collections/_superusers/auth-with-password",
           данные={"identity": почта, "password": пароль})[1]["token"]

    # Пробный аккаунт заводим заново каждый раз: прошлый прогон мог упасть.
    код, найден = q("GET", f"/api/collections/fern_users/records?filter=(email='{ПРОБА}')", su)
    for запись in найден.get("items", []):
        q("DELETE", f"/api/collections/fern_users/records/{запись['id']}", su)
    код, аккаунт = q("POST", "/api/collections/fern_users/records",
                     данные={"email": ПРОБА, "password": ПАРОЛЬ,
                             "passwordConfirm": ПАРОЛЬ})
    check("пробный аккаунт заведён", код, 200)
    uid = аккаунт["id"]
    токен = q("POST", "/api/collections/fern_users/auth-with-password",
              данные={"identity": ПРОБА, "password": ПАРОЛЬ})[1]["token"]

    try:
        # --- без сессии внутрь не пускают ---
        check("статус без сессии", q("GET", "/api/fern/me")[0], 401)
        check("счёт без сессии", q("POST", "/api/fern/checkout",
                                   данные={"plan": "month"})[0], 401)
        check("отмена без сессии", q("POST", "/api/fern/cancel")[0], 401)

        # --- сессия Togetherly сюда не годится: аккаунты не смешиваются ---
        # (проверяется чужим токеном суперюзера — он тоже не из fern_users)
        код, ответ = q("GET", "/api/fern/me", su)
        check("суперюзер не считается аккаунтом Fern", код, 401)

        # --- новый аккаунт: подписки нет ---
        код, статус = q("GET", "/api/fern/me", токен)
        check("статус читается", код, 200)
        check("подписки нет", статус["until"], None)
        check("талона нет", статус["ticket"], None)
        check("состояние названо", статус["status"], "none")

        # --- отменять нечего ---
        код, ответ = q("POST", "/api/fern/cancel", токен)
        check("отмена без подписки отбита", код, 400)
        check("причина названа", ответ["error"], "no_subscription")

        # --- негодный тариф не создаёт счёт ---
        код, ответ = q("POST", "/api/fern/checkout", токен, {"plan": "век"})
        check("неизвестный тариф отбит", код, 400)
        check("причина названа", ответ["error"], "bad_plan")

        # --- сервер выдал подписку: талон появляется ---
        до = (datetime.now(timezone.utc) + timedelta(days=30)).strftime("%Y-%m-%d %H:%M:%SZ")
        q("PATCH", f"/api/collections/fern_users/records/{uid}", su,
          {"pro_until": до, "pro_status": "active", "pro_source": "grant",
           "pro_plan": "month"})
        код, статус = q("GET", "/api/fern/me", токен)
        check("подписка видна", код, 200)
        check("состояние активно", статус["status"], "active")
        check("талон выдан", isinstance(статус["ticket"], str)
              and статус["ticket"].startswith("FERN"), True)
        check("срок талона больше срока подписки (льгота)",
              статус["ticket_until"] > статус["until"][:10], True)

        # --- истёкшая подписка талона не даёт ---
        вчера = (datetime.now(timezone.utc) - timedelta(days=1)).strftime("%Y-%m-%d %H:%M:%SZ")
        q("PATCH", f"/api/collections/fern_users/records/{uid}", su,
          {"pro_until": вчера, "pro_status": "active"})
        код, статус = q("GET", "/api/fern/me", токен)
        check("истёкшая подписка без талона", статус["ticket"], None)
        check("состояние истекло", статус["status"], "expired")

        if args.lava:
            код, счёт = q("POST", "/api/fern/checkout", токен,
                          {"plan": "month", "currency": "RUB", "lang": "RU"})
            check("счёт создан", код, 200)
            check("ссылка на оплату есть", счёт["url"].startswith("http"), True)
            print("счёт:", счёт["url"])
    finally:
        q("DELETE", f"/api/collections/fern_users/records/{uid}", su)
        for ключ in ("LAVA:probe", ):
            код, найдены = q("GET",
                             f"/api/collections/fern_orders/records?filter=(uid='{uid}')", su)
            for запись in найдены.get("items", []):
                q("DELETE", f"/api/collections/fern_orders/records/{запись['id']}", su)

    print(f"fern_routes: {checks} проверок пройдено")


if __name__ == "__main__":
    главное()
