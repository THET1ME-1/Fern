#!/usr/bin/env python3
"""Проверка страховок от потерянного вебхука. Запускается НА СЕРВЕРЕ:

    PB_SUPERUSER_EMAIL=... PB_SUPERUSER_PASSWORD=... python3 test_fern_sync.py

Вместо lava.top отвечает заглушка на loopback: роут синхронизации принимает
её адрес параметром, и только от того, кто знает ключ вебхука.
"""
from __future__ import annotations

import json
import os
import threading
import urllib.error
import urllib.request
from datetime import datetime, timedelta, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PB = os.environ.get("PB_URL", "http://127.0.0.1:8090").rstrip("/")
ПРОБА = "probe-sync-fern@example.com"
ПАРОЛЬ = "пробаproba123"
КЛЮЧ = os.environ.get("LAVA_WEBHOOK_KEY", "").strip()

checks = 0
ОТВЕТЫ = {}   # путь → (код, тело); заполняется тестом перед каждым шагом


def check(label, got, want):
    global checks
    assert got == want, f"{label}: получено {got!r}, ожидалось {want!r}"
    checks += 1


def q(метод, путь, токен="", данные=None, ключ=""):
    тело = json.dumps(данные).encode() if данные is not None else None
    req = urllib.request.Request(PB + путь, data=тело, method=метод)
    req.add_header("Content-Type", "application/json")
    if токен:
        req.add_header("Authorization", токен)
    if ключ:
        req.add_header("X-Api-Key", ключ)
    try:
        with urllib.request.urlopen(req, timeout=40) as r:
            return r.status, json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        сырое = e.read()
        try:
            return e.code, json.loads(сырое or b"{}")
        except json.JSONDecodeError:
            return e.code, {"raw": сырое.decode(errors="replace")[:300]}


class Заглушка(BaseHTTPRequestHandler):
    """Вместо gate.lava.top."""

    def do_GET(self):  # noqa: N802
        путь = self.path.split("?")[0]
        код, тело = ОТВЕТЫ.get(путь, (404, {"error": "not found"}))
        данные = json.dumps(тело).encode()
        self.send_response(код)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(данные)))
        self.end_headers()
        self.wfile.write(данные)

    def log_message(self, *args):
        return


def главное():
    assert КЛЮЧ, "нужен LAVA_WEBHOOK_KEY из окружения PocketBase"
    su = q("POST", "/api/collections/_superusers/auth-with-password",
           данные={"identity": os.environ["PB_SUPERUSER_EMAIL"],
                   "password": os.environ["PB_SUPERUSER_PASSWORD"]})[1]["token"]

    сервер = ThreadingHTTPServer(("127.0.0.1", 0), Заглушка)
    threading.Thread(target=сервер.serve_forever, daemon=True).start()
    база = f"http://127.0.0.1:{сервер.server_address[1]}"

    def чистка():
        for кол in ("fern_users", "fern_orders"):
            к, н = q("GET", f"/api/collections/{кол}/records?filter=(email='{ПРОБА}')&perPage=50", su)
            for з in н.get("items", []):
                q("DELETE", f"/api/collections/{кол}/records/{з['id']}", su)

    def аккаунт():
        к, н = q("GET", f"/api/collections/fern_users/records?filter=(email='{ПРОБА}')", su)
        return (н.get("items") or [None])[0]

    def заказ(ключ_заказа):
        к, н = q("GET", f"/api/collections/fern_orders/records?filter=(order_key='{ключ_заказа}')", su)
        return (н.get("items") or [None])[0]

    def день(строка):
        return datetime.fromisoformat(строка.replace(" ", "T").replace("Z", "+00:00")).date()

    сегодня = datetime.now(timezone.utc).date()
    чистка()
    к, зап = q("POST", "/api/collections/fern_users/records",
               данные={"email": ПРОБА, "password": ПАРОЛЬ, "passwordConfirm": ПАРОЛЬ})
    uid = зап["id"]

    try:
        # --- без ключа синхронизацию не запустить ---
        check("синхронизация закрыта", q("POST", "/api/fern/sync")[0], 401)

        # --- потерянный вебхук об оплате: крон добивает по счёту ---
        q("POST", "/api/collections/fern_orders/records", su, {
            "order_key": "LAVA:lost-1", "uid": uid, "email": ПРОБА,
            "source": "lava", "plan": "month", "status": "pending",
            "invoice_id": "lost-1", "event": "checkout",
        })
        ОТВЕТЫ["/api/v1/invoices/lost-1"] = (200, {
            "id": "lost-1", "status": "COMPLETED",
            "buyer": {"email": ПРОБА},
        })
        код, ответ = q("POST", "/api/fern/sync", данные={"lava_base": база}, ключ=КЛЮЧ)
        check("синхронизация прошла", код, 200)
        check("оплата подобрана", ответ["paid"], 1)
        check("заказ закрыт", заказ("LAVA:lost-1")["status"], "paid")
        зап = аккаунт()
        check("подписка открыта", зап["pro_status"], "active")
        check("срок примерно месяц", 27 <= (день(зап["pro_until"]) - сегодня).days <= 32, True)

        # --- повторный прогон ничего не удваивает ---
        было = аккаунт()["pro_until"]
        код, ответ = q("POST", "/api/fern/sync", данные={"lava_base": база}, ключ=КЛЮЧ)
        check("второй раз оплату не считает", ответ["paid"], 0)
        check("срок не сдвинулся", аккаунт()["pro_until"], было)

        # --- суточная сверка: продление, о котором вебхук не сказал ---
        q("PATCH", f"/api/collections/fern_users/records/{uid}", su,
          {"lava_contract": "sub-1"})
        далеко = (datetime.now(timezone.utc) + timedelta(days=45)).isoformat()
        ОТВЕТЫ["/api/v1/subscriptions/sub-1"] = (200, {
            "id": "sub-1", "subscriptionStatus": "ACTIVE", "expiredAt": далеко,
            "buyer": {"email": ПРОБА},
        })
        код, ответ = q("POST", "/api/fern/sync", данные={"lava_base": база, "full": True},
                       ключ=КЛЮЧ)
        check("сверка прошла", код, 200)
        check("подписка сверена", ответ["synced"], 1)
        check("срок подтянулся к сроку продавца",
              (день(аккаунт()["pro_until"]) - сегодня).days, 45)

        # --- отменённая у продавца подписка помечается, но доступ живёт ---
        конец = (datetime.now(timezone.utc) + timedelta(days=10)).isoformat()
        ОТВЕТЫ["/api/v1/subscriptions/sub-1"] = (200, {
            "id": "sub-1", "subscriptionStatus": "CANCELLED", "expiredAt": конец,
        })
        q("POST", "/api/fern/sync", данные={"lava_base": база, "full": True}, ключ=КЛЮЧ)
        зап = аккаунт()
        check("статус отменён", зап["pro_status"], "cancelled")
        check("доступ до конца оплаченного", (день(зап["pro_until"]) - сегодня).days, 10)

        # --- продавец молчит: доступ не гасим ---
        ОТВЕТЫ.pop("/api/v1/subscriptions/sub-1", None)
        было = аккаунт()["pro_until"]
        код, ответ = q("POST", "/api/fern/sync", данные={"lava_base": база, "full": True},
                       ключ=КЛЮЧ)
        check("молчание продавца не роняет синхронизацию", код, 200)
        check("срок не тронут", аккаунт()["pro_until"], было)
    finally:
        чистка()
        сервер.shutdown()

    print(f"fern_sync: {checks} проверок пройдено")


if __name__ == "__main__":
    главное()
