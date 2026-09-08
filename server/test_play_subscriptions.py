#!/usr/bin/env python3
"""Проверка подписок Google Play: python3 server/test_play_subscriptions.py

Сети нет: ответы Google подменяются. Проверяется то, из-за чего подписка
отличается от разовой покупки — состояние и срок вместо `purchaseState`.
"""
from __future__ import annotations

import io
import json
import sys
import urllib.error
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
# На сервере служба живёт в /opt, а тесты — в /opt/fern.
sys.path.insert(0, "/opt")

import play_verify as pv  # noqa: E402

checks = 0


def check(label, got, want):
    global checks
    assert got == want, f"{label}: получено {got!r}, ожидалось {want!r}"
    checks += 1


pv.access_token = lambda: "токен"
последний_url = {"value": ""}


def ответ(данные: dict, код: int = 200):
    def открыть(req, timeout=0):
        последний_url["value"] = req.full_url
        if код != 200:
            raise urllib.error.HTTPError(req.full_url, код, "нет", {}, None)

        class Ответ(io.BytesIO):
            def __enter__(self):
                return self

            def __exit__(self, *args):
                return False

        return Ответ(json.dumps(данные).encode())

    return открыть


# --- активная подписка годна, срок читается ---
pv.urllib.request.urlopen = ответ({
    "subscriptionState": "SUBSCRIPTION_STATE_ACTIVE",
    "lineItems": [{"productId": "fern_pro_month",
                   "expiryTime": "2026-10-08T12:00:00Z"}],
})
итог = pv.verify_subscription("токен-1", "com.fern.app")
check("активная годна", итог["valid"], True)
check("срок прочитан", итог["expiry"], "2026-10-08T12:00:00Z")
check("товар прочитан", итог["productId"], "fern_pro_month")
check("пакет ушёл в запрос", "com.fern.app" in последний_url["value"], True)
check("спрашивали именно подписку",
      "subscriptionsv2" in последний_url["value"], True)

# --- отменённая: доступ до конца оплаченного ---
pv.urllib.request.urlopen = ответ({
    "subscriptionState": "SUBSCRIPTION_STATE_CANCELED",
    "lineItems": [{"productId": "fern_pro_month",
                   "expiryTime": "2026-10-08T12:00:00Z"}],
})
итог = pv.verify_subscription("токен-1")
check("отменённая ещё годна", итог["valid"], True)
check("отмена отмечена", итог["cancelled"], True)

# --- просроченная не годна ---
pv.urllib.request.urlopen = ответ({
    "subscriptionState": "SUBSCRIPTION_STATE_EXPIRED",
    "lineItems": [{"productId": "fern_pro_month",
                   "expiryTime": "2026-08-08T12:00:00Z"}],
})
check("просроченная закрыта", pv.verify_subscription("токен-1")["valid"], False)

# --- приостановленная не годна ---
pv.urllib.request.urlopen = ответ({
    "subscriptionState": "SUBSCRIPTION_STATE_ON_HOLD",
    "lineItems": [{"expiryTime": "2026-10-08T12:00:00Z"}],
})
check("приостановленная закрыта", pv.verify_subscription("токен-1")["valid"], False)

# --- Google не знает токена: это отказ, а не наша беда ---
pv.urllib.request.urlopen = ответ({}, код=404)
итог = pv.verify_subscription("выдуманный")
check("чужой токен отбит", (итог["ok"], итог["valid"]), (True, False))

# --- Google молчит: наша беда, доступ по ней не гасят ---
pv.urllib.request.urlopen = ответ({}, код=500)
check("сбой Google отличается от отказа", pv.verify_subscription("т")["ok"], False)

# --- разовая покупка ходит по своему адресу и со своим пакетом ---
pv.urllib.request.urlopen = ответ({"purchaseState": 0, "orderId": "GPA.1"})
итог = pv.verify("fern_pro", "токен-2", "com.fern.app")
check("разовая покупка цела", итог["valid"], True)
check("адрес разовой покупки прежний",
      "purchases/products" in последний_url["value"], True)

# --- срок Apple из миллисекунд ---
check("дата Apple разбирается",
      pv._срок_из_мс(1791547200000).startswith("2026-"), True)
check("пустое поле — не ошибка", pv._срок_из_мс(None), "")

print(f"play_subscriptions: {checks} проверок пройдено")
