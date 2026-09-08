#!/usr/bin/env python3
"""Приём магазинных чеков. Запускается НА СЕРВЕРЕ:

    PB_SUPERUSER_EMAIL=... PB_SUPERUSER_PASSWORD=... python3 test_fern_store.py

Вместо службы проверки чеков отвечает заглушка на loopback.
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
ПРОБА = "probe-store-fern@example.com"
ПАРОЛЬ = "пробаproba123"
КЛЮЧ = os.environ.get("LAVA_WEBHOOK_KEY", "").strip()

checks = 0
ВЕРДИКТ = {}


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
        with urllib.request.urlopen(req, timeout=30) as r:
            return r.status, json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        сырое = e.read()
        try:
            return e.code, json.loads(сырое or b"{}")
        except json.JSONDecodeError:
            return e.code, {}


class Заглушка(BaseHTTPRequestHandler):
    """Вместо play_verify.py."""

    def do_POST(self):  # noqa: N802
        длина = int(self.headers.get("Content-Length") or 0)
        запрос = json.loads(self.rfile.read(длина) or b"{}")
        ВЕРДИКТ["последний_запрос"] = запрос
        данные = json.dumps(ВЕРДИКТ.get("ответ", {})).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(данные)))
        self.end_headers()
        self.wfile.write(данные)

    def log_message(self, *args):
        return


def главное():
    assert КЛЮЧ, "нужен LAVA_WEBHOOK_KEY"
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

    чистка()
    q("POST", "/api/collections/fern_users/records",
      данные={"email": ПРОБА, "password": ПАРОЛЬ, "passwordConfirm": ПАРОЛЬ})
    токен = q("POST", "/api/collections/fern_users/auth-with-password",
              данные={"identity": ПРОБА, "password": ПАРОЛЬ})[1]["token"]

    срок = (datetime.now(timezone.utc) + timedelta(days=30)).isoformat()
    try:
        check("без сессии не пускают", q("POST", "/api/fern/store",
              данные={"platform": "play", "productId": "fern_pro_month",
                      "token": "t"})[0], 401)

        # --- годный чек Play открывает подписку ---
        ВЕРДИКТ["ответ"] = {"ok": True, "valid": True, "expiry": срок,
                            "productId": "fern_pro_month"}
        код, ответ = q("POST", "/api/fern/store", токен, {
            "platform": "play", "productId": "fern_pro_month",
            "token": "play-token-1", "verify_base": база}, ключ=КЛЮЧ)
        check("чек принят", код, 200)
        зап = аккаунт()
        check("подписка открыта", зап["pro_status"], "active")
        check("источник — магазин", зап["pro_source"], "play")
        check("тариф месячный", зап["pro_plan"], "month")
        запрос = ВЕРДИКТ["последний_запрос"]
        check("спрашивали подписку", запрос["kind"], "subscription")
        check("пакет Fern, а не Togetherly", запрос["package"], "com.fern.app")

        # --- продление тем же токеном двигает срок, а не плодит заказ ---
        дальше = (datetime.now(timezone.utc) + timedelta(days=60)).isoformat()
        ВЕРДИКТ["ответ"] = {"ok": True, "valid": True, "expiry": дальше}
        q("POST", "/api/fern/store", токен, {
            "platform": "play", "productId": "fern_pro_month",
            "token": "play-token-1", "verify_base": база}, ключ=КЛЮЧ)
        к, заказы = q("GET",
                      f"/api/collections/fern_orders/records?filter=(email='{ПРОБА}')", su)
        check("заказ один", заказы["totalItems"], 1)
        зап = аккаунт()
        check("срок вырос", зап["pro_until"][:10], дальше[:10])

        # --- подделанный чек не открывает ничего ---
        ВЕРДИКТ["ответ"] = {"ok": True, "valid": False, "reason": "google_404"}
        код, ответ = q("POST", "/api/fern/store", токен, {
            "platform": "play", "productId": "fern_pro_month",
            "token": "выдумка", "verify_base": база}, ключ=КЛЮЧ)
        check("подделка отбита", код, 400)
        check("причина названа", ответ["error"], "not_valid")

        # --- Google молчит: это не отказ покупателю ---
        ВЕРДИКТ["ответ"] = {"ok": False, "reason": "http_500"}
        код, ответ = q("POST", "/api/fern/store", токен, {
            "platform": "play", "productId": "fern_pro_month",
            "token": "play-token-1", "verify_base": база}, ключ=КЛЮЧ)
        check("сбой проверки отличается от отказа", код, 502)

        # --- срок магазина не отбирает уже оплаченное на lava ---
        далеко = (datetime.now(timezone.utc) + timedelta(days=200)).isoformat()
        q("PATCH", f"/api/collections/fern_users/records/{аккаунт()['id']}", su,
          {"pro_until": далеко})
        ВЕРДИКТ["ответ"] = {"ok": True, "valid": True,
                            "expiry": (datetime.now(timezone.utc) + timedelta(days=5)).isoformat()}
        q("POST", "/api/fern/store", токен, {
            "platform": "play", "productId": "fern_pro_year",
            "token": "play-token-1", "verify_base": база}, ключ=КЛЮЧ)
        check("берётся больший срок", аккаунт()["pro_until"][:10], далеко[:10])
    finally:
        чистка()
        сервер.shutdown()

    print(f"fern_store: {checks} проверок пройдено")


if __name__ == "__main__":
    главное()
