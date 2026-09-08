#!/usr/bin/env python3
"""Проверка службы талонов: python3 server/test_fern_ticket.py

Сети не требует: HTTP-сервер поднимается на свободном порту loopback.
"""
import base64
import json
import os
import sys
import threading
import urllib.error
import urllib.request
from datetime import date, timedelta
from pathlib import Path

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

СВОЙ = Path(__file__).resolve().parent
sys.path.insert(0, str(СВОЙ))
sys.path.insert(0, str(СВОЙ.parent / "bot"))

# Ключ подписи заводится ДО импорта службы: она читает его при старте.
ключ = Ed25519PrivateKey.generate()
os.environ["FERN_LICENSE_KEY"] = base64.b64encode(ключ.private_bytes(
    serialization.Encoding.Raw, serialization.PrivateFormat.Raw,
    serialization.NoEncryption())).decode()
ПУБЛИЧНЫЙ = ключ.public_key().public_bytes(
    serialization.Encoding.Raw, serialization.PublicFormat.Raw)

import license as lic          # noqa: E402
import fern_ticket as служба   # noqa: E402

checks = 0


def check(label, got, want):
    global checks
    assert got == want, f"{label}: получено {got!r}, ожидалось {want!r}"
    checks += 1


сегодня = date(2026, 9, 8)

# --- срок талона: оплачено плюс неделя льготы ---
ответ = служба.ticket_for("rec1", "va@mail.ru", "2026-10-08", "month", now=сегодня)
check("талон выдан", ответ["ok"], True)
check("льгота неделя", ответ["until"], "2026-10-15")
разбор = lic.verify(ответ["ticket"], ПУБЛИЧНЫЙ)
check("талон читается", разбор is not None, True)
check("срок внутри совпадает с ответом", разбор["until"], date(2026, 10, 15))
check("почта внутри", разбор["email"], "va@mail.ru")

# --- годовая подписка не даёт талон на год: потолок сорок дней ---
год = служба.ticket_for("rec1", "va@mail.ru", "2027-09-08", "year", now=сегодня)
check("потолок сорок дней", год["until"], "2026-10-18")
check("тариф едет внутри", lic.verify(год["ticket"], ПУБЛИЧНЫЙ)["plan"], "year")

# --- истёкшая подписка талона не получает ---
истёк = служба.ticket_for("rec1", "va@mail.ru", "2026-09-01", "month", now=сегодня)
check("истёкшей подписке отказ", истёк["ok"], False)
check("причина названа", истёк["reason"], "expired")

# --- последний день подписки ещё внутри льготы ---
край = служба.ticket_for("rec1", "va@mail.ru", "2026-09-08", "month", now=сегодня)
check("день окончания ещё оплачен", край["ok"], True)

# --- кривые входные данные не роняют службу ---
check("без почты отказ", служба.ticket_for("rec1", "", "2026-10-08", "month",
                                           now=сегодня)["reason"], "bad_email")
check("без аккаунта отказ", служба.ticket_for("", "a@b.ru", "2026-10-08", "month",
                                              now=сегодня)["reason"], "bad_uid")
check("кривая дата отказ", служба.ticket_for("rec1", "a@b.ru", "вчера", "month",
                                             now=сегодня)["reason"], "bad_until")
check("неизвестный тариф отказ",
      служба.ticket_for("rec1", "a@b.ru", "2026-10-08", "век",
                        now=сегодня)["reason"], "bad_plan")

# --- HTTP: тот же ответ по сети ---
сервер = служба.make_server(("127.0.0.1", 0))
threading.Thread(target=сервер.serve_forever, daemon=True).start()
адрес = f"http://127.0.0.1:{сервер.server_address[1]}"


def запрос(данные, путь="/ticket"):
    тело = json.dumps(данные).encode()
    req = urllib.request.Request(адрес + путь, data=тело,
                                 headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=5) as r:
            return r.status, json.loads(r.read())
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read())


код, тело = запрос({"uid": "rec9", "email": "b@c.ru",
                    "until": (date.today() + timedelta(days=30)).isoformat(),
                    "plan": "month"})
check("HTTP отвечает 200", код, 200)
check("HTTP отдал талон", lic.verify(тело["ticket"], ПУБЛИЧНЫЙ) is not None, True)

код, тело = запрос({"uid": "rec9"})
check("неполный запрос — 400", код, 400)

with urllib.request.urlopen(адрес + "/health", timeout=5) as r:
    check("здоровье службы", r.status, 200)

сервер.shutdown()
print(f"fern_ticket: {checks} проверок пройдено")
