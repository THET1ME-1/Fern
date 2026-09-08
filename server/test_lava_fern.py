#!/usr/bin/env python3
"""Проверка приёма событий lava для Fern. Запускается НА СЕРВЕРЕ:

    PB_SUPERUSER_EMAIL=... PB_SUPERUSER_PASSWORD=... python3 test_lava_fern.py

Шлёт в роут те самые уведомления, что описаны в документации lava.top, и
смотрит, что стало с аккаунтом. Ни сети наружу, ни настоящих оплат.
"""
from __future__ import annotations

import json
import os
import urllib.error
import urllib.request
from datetime import datetime, timedelta, timezone

PB = os.environ.get("PB_URL", "http://127.0.0.1:8090").rstrip("/")
ПРОБА = "probe-lava-fern@example.com"
ПАРОЛЬ = "пробаproba123"
ОФФЕР_МЕСЯЦ = os.environ.get("FERN_OFFER_MONTH", "").strip() or "11111111-1111-1111-1111-111111111111"
# Годовой тариф на lava подписным быть не может (период задаётся товаром), и
# на витрине остался «год разовой оплатой» — его сервер тоже обязан узнавать.
ОФФЕР_ГОД = (os.environ.get("FERN_OFFER_YEAR", "").strip()
             or os.environ.get("FERN_OFFER_YEAR_ONCE", "").strip()
             or "22222222-2222-2222-2222-222222222222")

checks = 0


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
        with urllib.request.urlopen(req, timeout=25) as r:
            return r.status, json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        сырое = e.read()
        try:
            return e.code, json.loads(сырое or b"{}")
        except json.JSONDecodeError:
            return e.code, {"raw": сырое.decode(errors="replace")[:300]}


def событие(тип, статус, contract, оффер=ОФФЕР_МЕСЯЦ, почта=ПРОБА, **прочее):
    тело = {
        "eventType": тип,
        "product": {"id": оффер, "title": "Fern Pro"},
        "buyer": {"email": почта},
        "contractId": contract,
        "amount": 299,
        "currency": "RUB",
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "status": статус,
        "errorMessage": "",
    }
    тело.update(прочее)
    return тело


def главное():
    почта_su = os.environ["PB_SUPERUSER_EMAIL"]
    пароль_su = os.environ["PB_SUPERUSER_PASSWORD"]
    su = q("POST", "/api/collections/_superusers/auth-with-password",
           данные={"identity": почта_su, "password": пароль_su})[1]["token"]
    ключ = os.environ.get("LAVA_WEBHOOK_KEY", "").strip()
    assert ключ, "нужен LAVA_WEBHOOK_KEY из окружения PocketBase"

    def чистка():
        for коллекция, фильтр in (("fern_users", f"(email='{ПРОБА}')"),
                                  ("fern_orders", f"(email='{ПРОБА}')")):
            код, найдено = q("GET", f"/api/collections/{коллекция}/records?filter={фильтр}", su)
            for запись in найдено.get("items", []):
                q("DELETE", f"/api/collections/{коллекция}/records/{запись['id']}", su)

    def аккаунт():
        код, найдено = q("GET",
                         f"/api/collections/fern_users/records?filter=(email='{ПРОБА}')", su)
        return (найдено.get("items") or [None])[0]

    чистка()
    q("POST", "/api/collections/fern_users/records",
      данные={"email": ПРОБА, "password": ПАРОЛЬ, "passwordConfirm": ПАРОЛЬ})

    try:
        # --- без ключа вебхук не пускают ---
        код, _ = q("POST", "/api/fern/lava", данные=событие(
            "payment.success", "subscription-active", "c-401"))
        check("без ключа отказ", код, 401)

        # --- первый платёж открывает подписку ---
        код, ответ = q("POST", "/api/fern/lava", данные=событие(
            "payment.success", "subscription-active", "c-1"), ключ=ключ)
        check("первый платёж принят", код, 200)
        check("подписка выдана", ответ.get("granted"), True)
        зап = аккаунт()
        сегодня = datetime.now(timezone.utc).date()
        срок = datetime.fromisoformat(зап["pro_until"].replace(" ", "T").replace("Z", "+00:00")).date()
        check("срок примерно месяц", 27 <= (срок - сегодня).days <= 32, True)
        check("статус активен", зап["pro_status"], "active")
        check("источник — lava", зап["pro_source"], "lava")
        check("тариф месячный", зап["pro_plan"], "month")
        check("контракт запомнен", зап["lava_contract"], "c-1")

        # --- повтор того же уведомления ничего не двигает ---
        было = зап["pro_until"]
        код, ответ = q("POST", "/api/fern/lava", данные=событие(
            "payment.success", "subscription-active", "c-1"), ключ=ключ)
        check("повтор опознан", ответ.get("repeated"), True)
        check("срок не сдвинулся", аккаунт()["pro_until"], было)

        # --- продление добавляет месяц к СТАРОМУ сроку, а не к сегодняшнему ---
        код, ответ = q("POST", "/api/fern/lava", данные=событие(
            "subscription.recurring.payment.success", "subscription-active",
            "c-2", parentContractId="c-1"), ключ=ключ)
        check("продление принято", код, 200)
        срок2 = datetime.fromisoformat(
            аккаунт()["pro_until"].replace(" ", "T").replace("Z", "+00:00")).date()
        check("срок вырос примерно на месяц", 55 <= (срок2 - сегодня).days <= 63, True)

        # --- неудачное продление ничего не гасит ---
        q("POST", "/api/fern/lava", данные=событие(
            "subscription.recurring.payment.failed", "subscription-failed",
            "c-3", parentContractId="c-1"), ключ=ключ)
        check("после неудачи срок цел", аккаунт()["pro_status"], "active")

        # --- отмена оставляет доступ до конца оплаченного ---
        конец = (datetime.now(timezone.utc) + timedelta(days=20)).isoformat()
        код, ответ = q("POST", "/api/fern/lava", данные=событие(
            "subscription.cancelled", "", "c-1", cancelledAt=datetime.now(timezone.utc).isoformat(),
            willExpireAt=конец), ключ=ключ)
        check("отмена принята", код, 200)
        зап = аккаунт()
        check("статус отменён", зап["pro_status"], "cancelled")
        срок3 = datetime.fromisoformat(
            зап["pro_until"].replace(" ", "T").replace("Z", "+00:00")).date()
        check("срок стал датой из уведомления", (срок3 - сегодня).days, 20)

        # --- возврат гасит доступ сразу ---
        код, ответ = q("POST", "/api/fern/lava", ключ=ключ, данные={
            "event_type": "refund.success",
            "data": {"customer_email": ПРОБА, "refund_id": "r-1",
                     "product": {"product_id": ОФФЕР_МЕСЯЦ}},
        })
        check("возврат принят", код, 200)
        зап = аккаунт()
        check("статус — возврат", зап["pro_status"], "refunded")
        срок4 = datetime.fromisoformat(
            зап["pro_until"].replace(" ", "T").replace("Z", "+00:00")).date()
        check("доступ погашен", срок4 <= сегодня, True)

        # --- годовой тариф даёт год ---
        чистка()
        q("POST", "/api/collections/fern_users/records",
          данные={"email": ПРОБА, "password": ПАРОЛЬ, "passwordConfirm": ПАРОЛЬ})
        q("POST", "/api/fern/lava", данные=событие(
            "payment.success", "subscription-active", "c-year", оффер=ОФФЕР_ГОД),
          ключ=ключ)
        зап = аккаунт()
        срок5 = datetime.fromisoformat(
            зап["pro_until"].replace(" ", "T").replace("Z", "+00:00")).date()
        check("год — это год", 360 <= (срок5 - сегодня).days <= 370, True)
        check("тариф годовой", зап["pro_plan"], "year")

        # --- оплата до регистрации: заказ ждёт хозяина ---
        чистка()
        код, ответ = q("POST", "/api/fern/lava", данные=событие(
            "payment.success", "subscription-active", "c-orphan"), ключ=ключ)
        check("оплата без аккаунта принята", код, 200)
        check("заказ отложен", ответ.get("pending_account"), True)
        код, аккаунт_новый = q("POST", "/api/collections/fern_users/records",
                               данные={"email": ПРОБА, "password": ПАРОЛЬ,
                                       "passwordConfirm": ПАРОЛЬ})
        токен = q("POST", "/api/collections/fern_users/auth-with-password",
                  данные={"identity": ПРОБА, "password": ПАРОЛЬ})[1]["token"]
        код, статус = q("GET", "/api/fern/me", токен)
        check("подписка нашлась после регистрации", статус["status"], "active")
        check("талон выдан", статус["ticket"].startswith("FERN"), True)
    finally:
        чистка()

    print(f"lava_fern: {checks} проверок пройдено")


if __name__ == "__main__":
    главное()
