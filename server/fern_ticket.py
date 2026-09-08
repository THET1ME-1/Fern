#!/usr/bin/env python3
"""Подпись талонов подписки Fern. Локальная служба на 127.0.0.1:8160.

ЗАЧЕМ ОТДЕЛЬНОЙ СЛУЖБОЙ. Талон подписывается Ed25519, а JSVM PocketBase такой
подписи не умеет — ровно та же причина, по которой рядом живёт `play_verify.py`
с RS256. Хук зовёт localhost и получает готовую строку.

Протокол:
    POST /ticket {"uid": "...", "email": "...", "until": "2026-10-08",
                  "plan": "month"}
      → 200 {"ok": true,  "ticket": "FERN…", "until": "2026-10-15"}
      → 400 {"ok": false, "reason": "bad_email"}   негодный запрос
      → 200 {"ok": false, "reason": "expired"}     подписка кончилась
    GET  /health → 200 {"ok": true}

СРОК ТАЛОНА — не срок подписки. К оплаченному дню добавляется неделя льготы
(продление прошло, а человек неделю не открывал приложение в сети), но талон
не живёт дольше сорока дней от выдачи: годовая подписка не должна превращаться
в годовой офлайн-пропуск, который не отозвать.

Ключ подписи — `FERN_LICENSE_KEY` в окружении (base64, 32 байта), тот же, что
у бота. Разбор и сборка живут в `license.py` бота; путь к нему задаёт
`FERN_BOT_DIR` (по умолчанию /opt/snt-bot).
"""
from __future__ import annotations

import json
import logging
import os
import sys
from datetime import date, datetime, timedelta, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

БОТ = Path(os.environ.get("FERN_BOT_DIR", "/opt/snt-bot"))
if БОТ.exists():
    sys.path.insert(0, str(БОТ))
else:  # локальный прогон из репозитория
    sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "bot"))

import license as lic  # noqa: E402

# Сколько дней доступа остаётся после последнего оплаченного дня.
GRACE_DAYS = 7
# Дольше этого срока талон не живёт, сколько бы ни было оплачено.
MAX_DAYS = 40

ПОРТ = int(os.environ.get("FERN_TICKET_PORT", "8160"))

log = logging.getLogger("fern_ticket")


def _день(текст: str) -> date | None:
    """Дата из строки. Принимает и `2026-10-08`, и полную метку времени:
    lava отдаёт `expiredAt` со временем, и обрезать его на стороне хука значит
    завести второе место, где формат даты имеет значение."""
    текст = (текст or "").strip()
    if not текст:
        return None
    try:
        return date.fromisoformat(текст[:10])
    except ValueError:
        pass
    try:
        return datetime.fromisoformat(текст.replace("Z", "+00:00")).date()
    except ValueError:
        return None


def ticket_for(uid: str, email: str, until: str, plan: str = "month",
               now: date | None = None) -> dict:
    """Талон для аккаунта. Ошибки возвращает словарём, а не исключением:
    хук на той стороне обязан отличать «негодный запрос» от «сервис упал»."""
    now = now or datetime.now(timezone.utc).date()
    uid = (uid or "").strip()
    email = (email or "").strip().lower()
    if not uid:
        return {"ok": False, "reason": "bad_uid"}
    if "@" not in email or len(email) > 255:
        return {"ok": False, "reason": "bad_email"}
    if plan not in lic.PLANS:
        return {"ok": False, "reason": "bad_plan"}
    оплачено = _день(until)
    if оплачено is None:
        return {"ok": False, "reason": "bad_until"}
    if оплачено < now:
        return {"ok": False, "reason": "expired"}

    срок = min(оплачено + timedelta(days=GRACE_DAYS), now + timedelta(days=MAX_DAYS))
    try:
        талон = lic.issue_ticket(uid, email, срок, issued=now, plan=plan)
    except ValueError as e:
        log.warning("талон не выпущен: %s", e)
        return {"ok": False, "reason": "bad_range"}
    return {"ok": True, "ticket": талон, "until": срок.isoformat()}


class Handler(BaseHTTPRequestHandler):
    server_version = "FernTicket/1"

    def _send(self, код: int, payload: dict) -> None:
        тело = json.dumps(payload, ensure_ascii=False).encode()
        self.send_response(код)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(тело)))
        self.end_headers()
        self.wfile.write(тело)

    def do_GET(self) -> None:  # noqa: N802 — имя задано базовым классом
        if self.path.startswith("/health"):
            self._send(200, {"ok": True})
        else:
            self._send(404, {"ok": False, "reason": "no_route"})

    def do_POST(self) -> None:  # noqa: N802
        if not self.path.startswith("/ticket"):
            self._send(404, {"ok": False, "reason": "no_route"})
            return
        try:
            длина = int(self.headers.get("Content-Length") or 0)
            данные = json.loads(self.rfile.read(длина) or b"{}")
        except (ValueError, json.JSONDecodeError):
            self._send(400, {"ok": False, "reason": "bad_json"})
            return
        if not isinstance(данные, dict):
            self._send(400, {"ok": False, "reason": "bad_json"})
            return

        ответ = ticket_for(str(данные.get("uid") or ""),
                           str(данные.get("email") or ""),
                           str(данные.get("until") or ""),
                           str(данные.get("plan") or "month"))
        # Негодный запрос — 400, кончившаяся подписка — 200: это не ошибка
        # вызывающего, а обычное состояние аккаунта.
        код = 200 if ответ["ok"] or ответ.get("reason") == "expired" else 400
        self._send(код, ответ)

    def log_message(self, *args) -> None:
        return


def make_server(адрес=("127.0.0.1", ПОРТ)) -> ThreadingHTTPServer:
    return ThreadingHTTPServer(адрес, Handler)


def main() -> None:
    logging.basicConfig(level=logging.INFO,
                        format="%(asctime)s %(levelname)s %(message)s")
    # Ключ читаем на старте: без него служба бесполезна, и узнать об этом надо
    # сразу, а не на первой покупке.
    lic.load_private_key()
    сервер = make_server()
    log.info("талоны Fern слушают %s:%s", *сервер.server_address)
    сервер.serve_forever()


if __name__ == "__main__":
    main()
