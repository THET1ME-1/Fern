#!/usr/bin/env python3
"""Проверка журнала заказов: python3 bot/test_store.py"""
import os
import tempfile

from store import Store

checks = 0


def check(label, got, want):
    global checks
    assert got == want, f"{label}: получено {got!r}, ожидалось {want!r}"
    checks += 1


path = os.path.join(tempfile.mkdtemp(), "test.db")
s = Store(path)

# --- повтор вебхука не плодит заказы ---
check("первый вебхук записан",
      s.save_order("ORD-1", "Buyer@Example.com", "prod", 1, "5.0", "{}"), True)
check("повтор того же заказа отброшен",
      s.save_order("ORD-1", "buyer@example.com", "prod", 1, "5.0", "{}"), False)

# --- выдача по почте ---
rows = s.claim("BUYER@example.com", 1001)
check("заказ найден по почте в любом регистре", len(rows), 1)
check("номер лицензии проставлен", rows[0]["license_id"], 1)
check("владелец записан", rows[0]["claimed_by"], 1001)

# --- повторный запрос тем же человеком отдаёт ТОТ ЖЕ номер ---
again = s.claim("buyer@example.com", 1001)
check("повторный запрос не плодит лицензии", again[0]["license_id"], 1)

# --- чужой по той же почте ничего не получает ---
stranger = s.claim("buyer@example.com", 2002)
check("чужой не уносит купленный ключ", stranger, [])

# --- второй покупатель получает свой номер ---
s.save_order("ORD-2", "second@example.com", "prod", 1, "5.0", "{}")
second = s.claim("second@example.com", 3003)
check("у второго покупателя свой номер", second[0]["license_id"], 2)

# --- две покупки одного человека ---
s.save_order("ORD-3", "buyer@example.com", "prod", 2, "5.0", "{}")
both = s.claim("buyer@example.com", 1001)
check("обе покупки отданы", len(both), 2)
check("вторая получила следующий номер",
      sorted(r["license_id"] for r in both), [1, 3])
check("номер товара сохранён", sorted(r["sku"] for r in both), [1, 2])

# --- список своих ключей ---
mine = s.orders_of(1001)
check("свои ключи находятся", len(mine), 2)
check("чужие в список не попадают", len(s.orders_of(9999)), 0)

st = s.stats()
check("статистика: заказов", st["total"], 3)
check("статистика: выдано", st["given"], 3)
check("статистика: ждут", st["waiting"], 0)

# --- неоплаченной почты нет в журнале ---
check("по чужой почте пусто", s.claim("nobody@example.com", 1), [])

# --- ручная выдача владельцем ---
# Владелец выдаёт ключ из чата, когда покупатель написал ему лично. Получатель
# при этом не проставляется: покупатель придёт к боту сам и заберёт свой же.
s.save_order("ORD-4", "manual@example.com", "prod", 1, "5.0", "{}")
granted = s.grant("manual@example.com")
check("ручная выдача даёт номер", granted[0]["license_id"], 4)
check("ручная выдача не присваивает получателя", granted[0]["claimed_by"], None)
check("покупатель получает тот же номер",
      s.claim("manual@example.com", 4004)[0]["license_id"], 4)
check("выдавать нечего", s.grant("nobody@example.com"), [])

# --- возврат денег ---
s.save_order("ORD-5", "back@example.com", "prod", 1, "5.0", "{}")
issued = s.claim("back@example.com", 5005)[0]
returned = s.refund("ORD-5", "back@example.com")
check("возврат нашёл заказ", returned["license_id"], issued["license_id"])
check("повторный вебхук возврата молчит", s.refund("ORD-5", "back@example.com"), None)
check("возврат по одной почте, без номера заказа",
      s.refund(None, "nobody@example.com"), None)
check("после возврата ключ не выдаётся", s.claim("back@example.com", 5005), [])
check("возвращённого нет в «моих ключах»", s.orders_of(5005), [])
check("статистика помнит возврат", s.stats()["refunded"], 1)

# --- защита от перебора чужих почт ---
check("новичок не заблокирован", s.blocked(7007), False)
for _ in range(6):
    s.note_miss(7007)
check("перебор остановлен", s.blocked(7007), True)
check("соседа это не задело", s.blocked(8008), False)

# --- владелец смотрит заказы по почте ---
found = s.find("BUYER@example.com")
check("заказы владельцу видны", len(found), 2)
check("чужая почта — пусто", s.find("nobody@example.com"), [])

print(f"все проверки пройдены: {checks}")
