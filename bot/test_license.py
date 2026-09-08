#!/usr/bin/env python3
"""Проверка ключей и талонов подписки: python3 bot/test_license.py"""
from datetime import date

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

import license as lic

checks = 0


def check(label, got, want):
    global checks
    assert got == want, f"{label}: получено {got!r}, ожидалось {want!r}"
    checks += 1


key = Ed25519PrivateKey.generate()
pub = key.public_key().public_bytes(
    serialization.Encoding.Raw, serialization.PublicFormat.Raw)
чужой = Ed25519PrivateKey.generate()
чужой_pub = чужой.public_key().public_bytes(
    serialization.Encoding.Raw, serialization.PublicFormat.Raw)

# --- талон подписки несёт срок ---
талон = lic.issue_ticket("rec0000000000001", "va@mail.ru", date(2026, 10, 8),
                         issued=date(2026, 9, 8), key=key)
info = lic.verify(талон, pub)
check("талон годен", info is not None, True)
check("срок внутри талона", info["until"], date(2026, 10, 8))
check("почта внутри талона", info["email"], "va@mail.ru")
check("дата выдачи", info["issued"], date(2026, 9, 8))
check("товар — Fern Pro", info["sku"], lic.SKU_PRO)
check("тариф", info["plan"], "month")

# --- годовой тариф отличается от месячного ---
год = lic.issue_ticket("rec0000000000001", "va@mail.ru", date(2027, 9, 8),
                       issued=date(2026, 9, 8), plan="year", key=key)
check("годовой тариф читается", lic.verify(год, pub)["plan"], "year")

# --- номер лицензии выводится из аккаунта: один человек — один номер ---
второй = lic.issue_ticket("rec0000000000001", "va@mail.ru", date(2026, 11, 8),
                          issued=date(2026, 10, 8), key=key)
check("номер лицензии стабилен у одного аккаунта",
      lic.verify(второй, pub)["id"], info["id"])
другой = lic.issue_ticket("rec0000000000002", "vb@mail.ru", date(2026, 10, 8),
                          issued=date(2026, 9, 8), key=key)
check("у другого аккаунта номер свой",
      lic.verify(другой, pub)["id"] != info["id"], True)

# --- чужая подпись не проходит ---
check("талон с чужим ключом отвергнут", lic.verify(талон, чужой_pub), None)

# --- подделка тела ломает подпись ---
испорчен = талон[:-4] + ("AAAA" if талон[-4:] != "AAAA" else "BBBB")
check("подделанный талон отвергнут", lic.verify(испорчен, pub), None)

# --- старые форматы работают как прежде ---
ключ1 = lic.issue(42, issued=date(2026, 7, 1), key=key)
разбор1 = lic.verify(ключ1, pub)
check("формат 1 годен", разбор1["id"], 42)
check("у формата 1 почты нет", разбор1["email"], None)
check("у формата 1 срока нет", разбор1.get("until"), None)

ключ2 = lic.issue(43, issued=date(2026, 7, 1), key=key, email="a@b.ru")
разбор2 = lic.verify(ключ2, pub)
check("формат 2 годен", разбор2["id"], 43)
check("у формата 2 почта на месте", разбор2["email"], "a@b.ru")
check("у формата 2 срока нет", разбор2.get("until"), None)

# --- срок за границей формата не выпускается (два байта дней кончаются
# около 2205 года) ---
try:
    lic.issue_ticket("rec1", "a@b.ru", date(2300, 1, 1), key=key)
    сорвалось = False
except ValueError:
    сорвалось = True
check("срок вне диапазона отвергнут при выпуске", сорвалось, True)

print(f"license: {checks} проверок пройдено")
