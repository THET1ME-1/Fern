#!/usr/bin/env python3
"""Уведомления магазинов о продлении. Запускается НА СЕРВЕРЕ:

    PB_SUPERUSER_EMAIL=... PB_SUPERUSER_PASSWORD=... python3 test_store_notifications.py

Проверку чеков подменяет заглушка на loopback: настоящие подписи Google и
Apple в тесте не воспроизвести, а вот поведение хука — вполне.
"""
from __future__ import annotations

import base64
import json
import os
import threading
import urllib.error
import urllib.request
from datetime import datetime, timedelta, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PB = os.environ.get("PB_URL", "http://127.0.0.1:8090").rstrip("/")
ПРОБА = "probe-rtdn-fern@example.com"
ПАРОЛЬ = "пробаproba123"
КЛЮЧ = os.environ.get("LAVA_WEBHOOK_KEY", "").strip()
ТОКЕН_ПОКУПКИ = "play-token-rtdn-1"

checks = 0
ОТВЕТ = {}


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
        ОТВЕТ["запрос"] = json.loads(self.rfile.read(длина) or b"{}")
        ключ = "notification" if self.path.endswith("/apple/notification") else "verify"
        данные = json.dumps(ОТВЕТ.get(ключ, {})).encode()
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
    # Роуты берут адрес проверки из окружения PocketBase, поэтому заглушку
    # подставляем тем же способом, что и в других тестах, — ключом вебхука.
    база = f"http://127.0.0.1:{сервер.server_address[1]}"

    def чистка():
        for кол in ("fern_users", "fern_orders"):
            к, н = q("GET", f"/api/collections/{кол}/records?filter=(email='{ПРОБА}')&perPage=50", su)
            for з in н.get("items", []):
                q("DELETE", f"/api/collections/{кол}/records/{з['id']}", su)

    def аккаунт():
        к, н = q("GET", f"/api/collections/fern_users/records?filter=(email='{ПРОБА}')", su)
        return (н.get("items") or [None])[0]

    def день(строка):
        return datetime.fromisoformat(строка.replace(" ", "T").replace("Z", "+00:00")).date()

    сегодня = datetime.now(timezone.utc).date()
    чистка()
    к, зап = q("POST", "/api/collections/fern_users/records",
               данные={"email": ПРОБА, "password": ПАРОЛЬ, "passwordConfirm": ПАРОЛЬ})
    uid = зап["id"]
    токен = q("POST", "/api/collections/fern_users/auth-with-password",
              данные={"identity": ПРОБА, "password": ПАРОЛЬ})[1]["token"]

    try:
        # Заводим магазинную подписку через приём чека — как в жизни.
        месяц = (datetime.now(timezone.utc) + timedelta(days=30)).isoformat()
        ОТВЕТ["verify"] = {"ok": True, "valid": True, "expiry": месяц}
        к, _ = q("POST", "/api/fern/store", токен, {
            "platform": "play", "productId": "fern_pro_month",
            "token": ТОКЕН_ПОКУПКИ, "verify_base": база}, ключ=КЛЮЧ)
        check("подписка магазина заведена", к, 200)

        # --- продление: уведомление Google двигает срок ---
        год = (datetime.now(timezone.utc) + timedelta(days=60)).isoformat()
        ОТВЕТ["verify"] = {"ok": True, "valid": True, "expiry": год}
        сообщение = base64.b64encode(json.dumps({
            "version": "1.0", "packageName": "com.fern.app",
            "subscriptionNotification": {
                "version": "1.0", "notificationType": 2,
                "purchaseToken": ТОКЕН_ПОКУПКИ,
                "subscriptionId": "fern_pro_month"},
        }).encode()).decode()
        к, ответ = q("POST", "/api/fern/play-rtdn", данные={
            "message": {"data": сообщение}, "verify_base": база}, ключ=КЛЮЧ)
        check("уведомление принято", к, 200)
        check("срок продлён", (день(аккаунт()["pro_until"]) - сегодня).days, 60)

        # --- чужой токен не роняет и не меняет ничего ---
        было = аккаунт()["pro_until"]
        чужое = base64.b64encode(json.dumps({
            "subscriptionNotification": {"purchaseToken": "чужой",
                                         "subscriptionId": "fern_pro_month"}}).encode()).decode()
        к, ответ = q("POST", "/api/fern/play-rtdn",
                     данные={"message": {"data": чужое}, "verify_base": база}, ключ=КЛЮЧ)
        check("чужой токен пропущен", ответ.get("skipped"), "unknown_token")
        check("срок не тронут", аккаунт()["pro_until"], было)

        # --- тестовое уведомление Google принимается молча ---
        тест = base64.b64encode(json.dumps({"testNotification": {"version": "1.0"}}).encode()).decode()
        к, ответ = q("POST", "/api/fern/play-rtdn",
                     данные={"message": {"data": тест}, "verify_base": база}, ключ=КЛЮЧ)
        check("тестовое уведомление принято", (к, ответ.get("skipped")), (200, "test"))

        # --- без ключа Google-роут закрыт ---
        к, _ = q("POST", "/api/fern/play-rtdn", данные={"message": {"data": тест}})
        check("без ключа закрыто", к, 401)

        # --- Apple: продление по уведомлению ---
        q("PATCH", f"/api/collections/fern_orders/records/"
          f"{q('GET', f'/api/collections/fern_orders/records?filter=(uid=%27{uid}%27)', su)[1]['items'][0]['id']}",
          su, {"source": "apple", "invoice_id": "orig-1"})
        далеко = (datetime.now(timezone.utc) + timedelta(days=90)).isoformat()
        ОТВЕТ["notification"] = {
            "ok": True, "valid": True, "notificationType": "DID_RENEW",
            "subtype": "", "transaction": {"originalTransactionId": "orig-1",
                                           "expiry": далеко}}
        к, ответ = q("POST", "/api/fern/apple-notify",
                     данные={"signedPayload": "конверт", "verify_base": база},
                     ключ=КЛЮЧ)
        check("уведомление Apple принято", к, 200)
        check("срок от Apple записан", (день(аккаунт()["pro_until"]) - сегодня).days, 90)

        # --- отмена автопродления: доступ остаётся до конца оплаченного ---
        ОТВЕТ["notification"] = {
            "ok": True, "valid": True, "notificationType": "DID_CHANGE_RENEWAL_STATUS",
            "subtype": "AUTO_RENEW_DISABLED",
            "transaction": {"originalTransactionId": "orig-1", "expiry": далеко}}
        q("POST", "/api/fern/apple-notify",
          данные={"signedPayload": "конверт", "verify_base": база}, ключ=КЛЮЧ)
        зап = аккаунт()
        check("статус отменён", зап["pro_status"], "cancelled")
        check("срок цел", (день(зап["pro_until"]) - сегодня).days, 90)

        # --- возврат гасит доступ ---
        ОТВЕТ["notification"] = {
            "ok": True, "valid": True, "notificationType": "REFUND", "subtype": "",
            "transaction": {"originalTransactionId": "orig-1",
                            "revocationDate": 1757000000000}}
        q("POST", "/api/fern/apple-notify",
          данные={"signedPayload": "конверт", "verify_base": база}, ключ=КЛЮЧ)
        зап = аккаунт()
        check("возврат погасил доступ", зап["pro_status"], "refunded")
        check("срок обнулён", день(зап["pro_until"]) <= сегодня, True)

        # --- суточная сверка сама забирает продление у Google ---
        # Уведомления требуют Pub/Sub из консоли, поэтому продление обязано
        # доезжать и без них.
        к, найдено = q("GET",
                       f"/api/collections/fern_orders/records?filter=(uid='{uid}')", su)
        заказ = найдено["items"][0]
        q("PATCH", f"/api/collections/fern_orders/records/{заказ['id']}", su,
          {"source": "play", "order_key": f"PLAY:{ТОКЕН_ПОКУПКИ}", "status": "paid"})
        далеко = (datetime.now(timezone.utc) + timedelta(days=150)).isoformat()
        ОТВЕТ["verify"] = {"ok": True, "valid": True, "expiry": далеко}
        к, ответ = q("POST", "/api/fern/sync",
                     данные={"lava_base": база, "verify_base": база, "full": True},
                     ключ=КЛЮЧ)
        check("сверка прошла", к, 200)
        check("магазинная подписка обновлена", ответ.get("stores"), 1)
        check("срок взят у магазина",
              (день(аккаунт()["pro_until"]) - сегодня).days, 150)

        # --- подделка не проходит ---
        ОТВЕТ["notification"] = {"ok": True, "valid": False, "reason": "bad_signature"}
        к, ответ = q("POST", "/api/fern/apple-notify",
                     данные={"signedPayload": "подделка", "verify_base": база},
                     ключ=КЛЮЧ)
        check("подделка отброшена", (к, ответ.get("skipped")), (200, "bad_signature"))
    finally:
        чистка()
        сервер.shutdown()

    print(f"store_notifications: {checks} проверок пройдено")


if __name__ == "__main__":
    главное()
