#!/usr/bin/env python3
"""Журнал заказов и выдачи ключей.

Отдельно от `bot.py` по той же причине, что и `lava.py`: ошибка здесь означает
либо невыданный ключ честному покупателю, либо выданный чужой. Такое проверяют
тестом, а не глазами.
"""
from __future__ import annotations

import sqlite3
from contextlib import closing
from datetime import datetime, timedelta, timezone
from pathlib import Path

# Сколько промахов по почте за час прощается одному телеграм-аккаунту.
# Почта — единственное доказательство покупки, и перебирать её словарём чужих
# адресов, надеясь опередить покупателя, никто не должен.
MISS_LIMIT = 5
MISS_WINDOW = timedelta(hours=1)


def _now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


class Store:
    def __init__(self, path: str | Path):
        self.path = str(path)
        self.init()

    def _db(self) -> sqlite3.Connection:
        conn = sqlite3.connect(self.path)
        conn.row_factory = sqlite3.Row
        return conn

    def init(self) -> None:
        with closing(self._db()) as conn, conn:
            conn.execute("""
                CREATE TABLE IF NOT EXISTS orders (
                    order_id   TEXT PRIMARY KEY,  -- идентификатор заказа с lava.top
                    email      TEXT NOT NULL,     -- почта покупателя, нижним регистром
                    product_id TEXT,              -- идентификатор товара с lava.top
                    sku        INTEGER NOT NULL,
                    amount     TEXT,
                    created    TEXT NOT NULL,
                    license_id INTEGER,           -- номер выданной лицензии
                    claimed_by INTEGER,           -- telegram id забравшего
                    claimed_at TEXT,
                    raw        TEXT,              -- payload целиком: сверить формат
                    refunded_at TEXT              -- деньги вернули, ключ пора отзывать
                )
            """)
            conn.execute("CREATE INDEX IF NOT EXISTS idx_orders_email ON orders(email)")
            conn.execute(
                "CREATE INDEX IF NOT EXISTS idx_orders_claimed ON orders(claimed_by)")
            # Журнал уже мог появиться до колонки возврата — дописываем на месте.
            columns = {r["name"] for r in conn.execute("PRAGMA table_info(orders)")}
            if "refunded_at" not in columns:
                conn.execute("ALTER TABLE orders ADD COLUMN refunded_at TEXT")
            conn.execute("""
                CREATE TABLE IF NOT EXISTS misses (
                    user_id INTEGER NOT NULL,   -- кто не угадал почту
                    at      TEXT NOT NULL
                )
            """)
            conn.execute("CREATE INDEX IF NOT EXISTS idx_misses_user ON misses(user_id)")

    def save_order(self, order_id: str, email: str, product_id: str | None,
                   sku: int, amount: str | None, raw: str) -> bool:
        """Кладёт заказ. False — такой уже был.

        lava.top повторяет вебхук до двадцати раз, поэтому запись обязана быть
        идемпотентной: ключ таблицы — идентификатор заказа.
        """
        with closing(self._db()) as conn, conn:
            cur = conn.execute(
                "INSERT OR IGNORE INTO orders"
                "(order_id,email,product_id,sku,amount,created,raw) "
                "VALUES(?,?,?,?,?,?,?)",
                (order_id, email.strip().lower(), product_id, sku, amount,
                 _now(), raw),
            )
            return cur.rowcount > 0

    def claim(self, email: str, user_id: int) -> list[sqlite3.Row]:
        """Заказы по почте; неполученным проставляет номер лицензии.

        Забранное кем-то другим не отдаёт: почта — единственное доказательство
        покупки, и знающий чужой адрес не должен унести чужой ключ.
        """
        email = email.strip().lower()
        out: list[sqlite3.Row] = []
        with closing(self._db()) as conn, conn:
            rows = conn.execute(
                "SELECT * FROM orders WHERE email=? AND refunded_at IS NULL "
                "ORDER BY created", (email,)
            ).fetchall()
            for row in rows:
                if row["claimed_by"] not in (None, user_id):
                    continue
                if row["license_id"] is None:
                    row = self._issue(conn, row["order_id"], user_id)
                out.append(row)
        return out

    def grant(self, email: str) -> list[sqlite3.Row]:
        """Ручная выдача владельцем: номер ставится, получатель — нет.

        Владелец выдаёт ключ, когда покупатель написал ему лично. Покупатель
        потом придёт к боту сам, и `claim` отдаст ему тот же номер, а не второй.
        """
        email = email.strip().lower()
        out: list[sqlite3.Row] = []
        with closing(self._db()) as conn, conn:
            rows = conn.execute(
                "SELECT * FROM orders WHERE email=? AND refunded_at IS NULL "
                "ORDER BY created", (email,)
            ).fetchall()
            for row in rows:
                if row["license_id"] is None:
                    row = self._issue(conn, row["order_id"], None)
                out.append(row)
        return out

    def _issue(self, conn: sqlite3.Connection, order_id: str,
               user_id: int | None) -> sqlite3.Row:
        """Проставляет заказу номер лицензии в текущей транзакции.

        Номер берётся здесь же: дубль означал бы двух человек с одним ключом и
        общий отзыв на обоих.
        """
        nxt = conn.execute(
            "SELECT COALESCE(MAX(license_id),0)+1 AS n FROM orders"
        ).fetchone()["n"]
        conn.execute(
            "UPDATE orders SET license_id=?, claimed_by=?, claimed_at=? "
            "WHERE order_id=?",
            (nxt, user_id, _now() if user_id else None, order_id),
        )
        return conn.execute(
            "SELECT * FROM orders WHERE order_id=?", (order_id,)
        ).fetchone()

    def refund(self, order_id: str | None, email: str) -> sqlite3.Row | None:
        """Помечает заказ возвращённым. None — помечать нечего.

        Возврат приходит тем же вебхуком и повторяется так же, поэтому второй
        раз метка не ставится: владелец не должен получать одно и то же
        напоминание двадцать раз.
        """
        email = email.strip().lower()
        with closing(self._db()) as conn, conn:
            row = None
            if order_id:
                row = conn.execute(
                    "SELECT * FROM orders WHERE order_id=? AND refunded_at IS NULL",
                    (order_id,),
                ).fetchone()
            if row is None:
                # Номер заказа в вебхуке возврата может оказаться своим,
                # отличным от номера оплаты. Тогда ищем по почте.
                row = conn.execute(
                    "SELECT * FROM orders WHERE email=? AND refunded_at IS NULL "
                    "ORDER BY created DESC LIMIT 1", (email,),
                ).fetchone()
            if row is None:
                return None
            conn.execute("UPDATE orders SET refunded_at=? WHERE order_id=?",
                         (_now(), row["order_id"]))
            return conn.execute(
                "SELECT * FROM orders WHERE order_id=?", (row["order_id"],)
            ).fetchone()

    def note_miss(self, user_id: int) -> None:
        """Запоминает промах по почте."""
        with closing(self._db()) as conn, conn:
            conn.execute("INSERT INTO misses(user_id, at) VALUES(?,?)",
                         (user_id, _now()))

    def blocked(self, user_id: int) -> bool:
        """Пора ли отказывать: слишком много промахов за последний час."""
        since = (datetime.now(timezone.utc) - MISS_WINDOW).isoformat(timespec="seconds")
        with closing(self._db()) as conn:
            recent = conn.execute(
                "SELECT COUNT(*) c FROM misses WHERE user_id=? AND at>=?",
                (user_id, since),
            ).fetchone()["c"]
        return recent >= MISS_LIMIT

    def find(self, email: str) -> list[sqlite3.Row]:
        """Заказы по почте как есть — для разбора вручную, ничего не меняет."""
        with closing(self._db()) as conn:
            return conn.execute(
                "SELECT * FROM orders WHERE email=? ORDER BY created",
                (email.strip().lower(),),
            ).fetchall()

    def orders_of(self, user_id: int) -> list[sqlite3.Row]:
        with closing(self._db()) as conn:
            return conn.execute(
                "SELECT * FROM orders WHERE claimed_by=? AND refunded_at IS NULL "
                "ORDER BY created", (user_id,)
            ).fetchall()

    def stats(self) -> dict:
        with closing(self._db()) as conn:
            total = conn.execute("SELECT COUNT(*) c FROM orders").fetchone()["c"]
            given = conn.execute(
                "SELECT COUNT(*) c FROM orders WHERE license_id IS NOT NULL"
            ).fetchone()["c"]
            refunded = conn.execute(
                "SELECT COUNT(*) c FROM orders WHERE refunded_at IS NOT NULL"
            ).fetchone()["c"]
            last = conn.execute(
                "SELECT email, created FROM orders ORDER BY created DESC LIMIT 5"
            ).fetchall()
        return {"total": total, "given": given, "waiting": total - given,
                "refunded": refunded, "last": last}
