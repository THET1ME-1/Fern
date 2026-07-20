#!/usr/bin/env python3
"""Проверка разбора вебхука lava.top: python3 bot/test_lava.py

Без pytest намеренно — на сервере, где живёт бот, лишних пакетов быть не должно.
"""
from lava import find_by_keys, find_email, is_refund, is_success, parse

# Форма из документации: событие, покупатель, контракт, товар.
SUCCESS = {
    "eventType": "payment.success",
    "contractId": "8a1b6d0e-1111-2222-3333-444455556666",
    "amount": 5.0,
    "currency": "USD",
    "status": "completed",
    "buyer": {"email": "Buyer@Example.COM"},
    "product": {
        "id": "34586da0-fa77-4b5d-a080-e183e7ea8803",
        "title": "Fern Pro — ключ активации",
    },
}

FAILED = {
    "eventType": "payment.failed",
    "contractId": "dead",
    "buyer": {"email": "buyer@example.com"},
    "status": "failed",
}

CANCELLED = {
    "eventType": "subscription.cancelled",
    "buyer": {"email": "buyer@example.com"},
}

# Возврат: деньги ушли обратно, выданный ключ надо отзывать.
REFUND = {
    "eventType": "payment.refund",
    "contractId": "8a1b6d0e-1111-2222-3333-444455556666",
    "status": "refunded",
    "buyer": {"email": "Buyer@Example.COM"},
    "product": {"id": "34586da0-fa77-4b5d-a080-e183e7ea8803"},
}

# Форма, которой в документации нет: плоская, другие имена, почта в глубине.
FLAT = {
    "event": "PAID",
    "invoiceId": "INV-42",
    "productId": "34586da0-fa77-4b5d-a080-e183e7ea8803",
    "client": [{"contacts": {"mail": "  ANOTHER@mail.ru "}}],
    "total": "450",
}

checks = 0


def check(label, got, want):
    global checks
    assert got == want, f"{label}: получено {got!r}, ожидалось {want!r}"
    checks += 1


check("успешная оплата опознана", is_success(SUCCESS), True)
check("отказ отсеян", is_success(FAILED), False)
check("отмена подписки отсеяна", is_success(CANCELLED), False)
check("пустой payload отсеян", is_success({}), False)

check("почта найдена и приведена к нижнему регистру",
      find_email(SUCCESS), "buyer@example.com")
check("почта найдена в глубине и обрезана", find_email(FLAT), "another@mail.ru")
check("почты нет", find_email({"a": {"b": 1}}), None)

# contractId должен побеждать безликий product.id — иначе заказы разных людей
# слипнутся в один, потому что товар у всех одинаковый.
check("идентификатор заказа важнее идентификатора товара",
      find_by_keys(SUCCESS, ("contractid", "invoiceid", "orderid", "id")),
      "8a1b6d0e-1111-2222-3333-444455556666")

order = parse(SUCCESS)
check("разбор: почта", order["email"], "buyer@example.com")
check("разбор: заказ", order["order_id"], "8a1b6d0e-1111-2222-3333-444455556666")
check("разбор: товар", order["product_id"], "34586da0-fa77-4b5d-a080-e183e7ea8803")
check("разбор: сумма", order["amount"], "5.0")

flat = parse(FLAT)
check("другая форма: почта", flat["email"], "another@mail.ru")
check("другая форма: заказ", flat["order_id"], "INV-42")
check("другая форма: сумма", flat["amount"], "450")

check("отказ разбору не подлежит", parse(FAILED), None)
check("оплата без почты бесполезна", parse({"status": "paid"}), None)

# --- возврат ---
# Отличать возврат от простого отказа обязательно: за отказом ключа никто не
# получал, а за возвратом — получал, и его пора отзывать.
check("возврат опознан", is_refund(REFUND), True)
check("оплата возвратом не считается", is_refund(SUCCESS), False)
check("отказ возвратом не считается", is_refund(FAILED), False)

back = parse(REFUND)
check("возврат разбирается", back["kind"], "refund")
check("возврат помнит заказ", back["order_id"],
      "8a1b6d0e-1111-2222-3333-444455556666")
check("возврат помнит почту", back["email"], "buyer@example.com")
check("оплата помечена оплатой", parse(SUCCESS)["kind"], "paid")

print(f"все проверки пройдены: {checks}")
