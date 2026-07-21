#!/usr/bin/env python3
"""Проверка склейки бота: python3 bot/test_bot.py

Здесь проверяется путь целиком — вебхук lava.top, журнал, ответ покупателю, —
а не отдельные кирпичи (для них есть test_lava, test_store, test_texts).
Ловит то, что не поймает ни один из них: разошедшиеся имена полей между
модулями, невыданный ключ после оплаты, молчание владельцу.

Aiogram и aiohttp подменены заглушками: на машине разработчика их может не
быть, а сети у теста нет по определению. Заглушки покрывают ровно то, чем
пользуется `bot.py`.
"""
import asyncio
import json
import logging
import os
import sys
import tempfile
import types

# Бот пишет в лог о чужом ключе и о повторах вебхука — в тесте это ожидаемо,
# и в выводе прогона такому шуму делать нечего.
logging.disable(logging.CRITICAL)

# --- заглушки телеграма и веб-сервера (до импорта bot.py) ---


class _Any:
    """Магический объект: `F.data == "menu"`, `F.text` и прочее в декораторах."""

    def __getattr__(self, _):
        return _Any()

    def __eq__(self, _):
        return _Any()

    def __hash__(self):
        return 0


def _identity_decorator(*_a, **_kw):
    def wrap(fn):
        return fn
    return wrap


class _Dispatcher:
    message = staticmethod(_identity_decorator)
    callback_query = staticmethod(_identity_decorator)

    async def start_polling(self, *_a, **_kw):
        return None


class _Stub:
    """Тип-пустышка: конструктор принимает что угодно."""

    def __init__(self, *a, **kw):
        self.args, self.kwargs = a, kw


class _Response(_Stub):
    @property
    def text(self):
        return self.kwargs.get("text", "")


def _module(name: str, **attrs) -> None:
    mod = types.ModuleType(name)
    for key, value in attrs.items():
        setattr(mod, key, value)
    sys.modules[name] = mod


_module("aiogram", Bot=_Stub, Dispatcher=_Dispatcher, F=_Any())
_module("aiogram.client.default", DefaultBotProperties=_Stub)
_module("aiogram.client.session.aiohttp", AiohttpSession=_Stub)
_module("aiogram.client.telegram", TelegramAPIServer=types.SimpleNamespace(
    from_base=lambda base: base))
_module("aiogram.enums", ParseMode=_Stub())
_module("aiogram.filters", Command=_Stub, CommandStart=_Stub)
_module("aiogram.types", BotCommand=_Stub, BotCommandScopeChat=_Stub,
        BotCommandScopeDefault=_Stub, CallbackQuery=_Stub,
        InlineKeyboardButton=_Stub, InlineKeyboardMarkup=_Stub, Message=_Stub)
_module("aiohttp", web=types.SimpleNamespace(
    Request=_Stub, Response=_Response, Application=_Stub, AppRunner=_Stub,
    TCPSite=_Stub))

OWNER_ID = 4242
os.environ["SNT_BOT_DB"] = os.path.join(tempfile.mkdtemp(), "test.db")
os.environ["SNT_BOT_OWNER"] = str(OWNER_ID)
os.environ["SNT_WEBHOOK_KEY"] = "секрет"

import bot as B  # noqa: E402  (после заглушек — иначе импорт не пройдёт)

# Подпись не проверяем: приватного ключа на машине с тестами нет, а формат
# ключа уже стережёт license_test.dart в приложении.
B.issue = lambda license_id, sku=1, email=None: f"FERNKEY{license_id}"

checks = 0


def check(label, got, want):
    global checks
    assert got == want, f"{label}: получено {got!r}, ожидалось {want!r}"
    checks += 1


def has(label, text, needle):
    global checks
    assert needle in text, f"{label}: в тексте нет {needle!r}\n{text}"
    checks += 1


# --- поддельный чат ---

sent: list[str] = []          # что бот ответил покупателю
to_owner: list[str] = []      # что ушло владельцу


class FakeBot:
    async def send_message(self, chat_id, text, **_kw):
        to_owner.append(text) if chat_id == OWNER_ID else sent.append(text)


class FakeMessage:
    def __init__(self, text: str, user_id: int):
        self.text = text
        self.from_user = types.SimpleNamespace(id=user_id, username=None)

    async def answer(self, text, **_kw):
        sent.append(text)


class FakeRequest:
    def __init__(self, payload, key="секрет"):
        self._payload = payload
        self.headers = {"X-Api-Key": key}
        self.remote = "127.0.0.1"

    async def json(self):
        return self._payload


B.bot = FakeBot()


def webhook(payload, key="секрет") -> str:
    return asyncio.run(B.lava_webhook(FakeRequest(payload, key))).text


def write(text: str, user_id: int) -> list[str]:
    sent.clear()
    asyncio.run(B.by_email(FakeMessage(text, user_id)))
    return sent


PAID = {
    "eventType": "payment.success",
    "contractId": "ORD-777",
    "status": "completed",
    "amount": 5.0,
    "buyer": {"email": "Buyer@Example.com"},
    "product": {"id": "34586da0-fa77-4b5d-a080-e183e7ea8803"},
}

REFUNDED = {
    "eventType": "payment.refund",
    "contractId": "ORD-777",
    "status": "refunded",
    "buyer": {"email": "buyer@example.com"},
    "product": {"id": "34586da0-fa77-4b5d-a080-e183e7ea8803"},
}

# --- чужой ключ в вебхук не пускают ---
check("вебхук с чужим ключом отбит", webhook(PAID, key="чужой"), "bad key")
check("чужая оплата в журнал не легла", B.store.find("buyer@example.com"), [])

# --- оплата ---
check("оплата принята", webhook(PAID), "ok")
check("заказ в журнале", len(B.store.find("buyer@example.com")), 1)
# Почта в журнале и в уведомлении — нижним регистром: покупатель напишет её
# как придётся, а искать заказ надо одинаково.
has("владелец узнал о продаже", to_owner[-1], "buyer@example.com")

to_owner.clear()
check("повтор вебхука принят", webhook(PAID), "ok")
check("повтор не создал второй заказ", len(B.store.find("buyer@example.com")), 1)
check("повтор не разбудил владельца второй раз", to_owner, [])

# --- покупатель забирает ключ ---
answer = write("моя почта buyer@example.com", 1001)
has("ключ выдан", answer[0], "FERNKEY1")
has("в ответе есть номер", answer[0], "№1")

# --- чужой по той же почте не унесёт ---
check("чужой ключа не получил",
      "FERNKEY" in write("buyer@example.com", 2002)[0], False)

# --- перебор чужих почт ---
for i in range(5):
    write(f"random{i}@example.com", 3003)
blocked = write("buyer@example.com", 3003)
has("перебор остановлен", blocked[0], "Слишком много попыток")

# --- возврат ---
to_owner.clear()
check("возврат принят", webhook(REFUNDED), "ok")
has("владельцу сказали, какой ключ отзывать", to_owner[-1], "№1")
has("владельцу напомнили про revoked", to_owner[-1], "revoked")

check("после возврата ключ не выдаётся снова",
      "FERNKEY" in write("buyer@example.com", 1001)[0], False)

to_owner.clear()
check("повтор возврата принят", webhook(REFUNDED), "ok")
check("повтор возврата владельца не будит", to_owner, [])

# --- события из очереди воркера ---
# Снаружи до бота не достучаться, поэтому вебхук lava.top принимает воркер, а
# бот приходит за событиями сам. Путь обработки обязан быть тем же самым, иначе
# оплата, принятая воркером, разойдётся с оплатой, принятой напрямую.
PULLED = {
    "eventType": "payment.success",
    "contractId": "ORD-888",
    "status": "completed",
    "amount": 5.0,
    "buyer": {"email": "queue@example.com"},
    "product": {"id": "34586da0-fa77-4b5d-a080-e183e7ea8803"},
}

to_owner.clear()
done = asyncio.run(B.handle_pulled([
    {"key": "order:1:aaa", "payload": json.dumps(PULLED)},
    {"key": "order:2:bbb", "payload": "не json"},
    {"key": "order:3:ccc", "payload": json.dumps({"status": "hello"})},
]))
check("заказ из очереди в журнале", len(B.store.find("queue@example.com")), 1)
has("владелец узнал о продаже из очереди", to_owner[-1], "queue@example.com")
check("подтверждены все три события, включая мусор", sorted(done),
      ["order:1:aaa", "order:2:bbb", "order:3:ccc"])
has("ключ по очередному заказу выдаётся",
    write("queue@example.com", 6006)[0], "FERNKEY")

# --- часики на кнопке снимаются первыми ---
# Телеграм крутит часики на кнопке, пока бот не ответит на callback. Если
# сначала перерисовывать экран, кнопка «думает» всё время запроса — а он идёт
# через воркер и изредка упирается в потерянный SYN на минуту.
steps: list[str] = []


class FakeQueryMessage:
    async def edit_text(self, _text, **_kw):
        steps.append("экран")

    async def answer(self, _text, **_kw):
        steps.append("экран")


class FakeQuery:
    def __init__(self):
        self.message = FakeQueryMessage()
        self.from_user = types.SimpleNamespace(id=1001, username=None)

    async def answer(self, *_a, **_kw):
        steps.append("часики")


for handler in (B.cb_help, B.cb_about, B.cb_menu, B.cb_claim):
    steps.clear()
    asyncio.run(handler(FakeQuery()))
    check(f"{handler.__name__}: часики сняты до перерисовки",
          steps[0], "часики")

# --- свой номер в телеграме ---
# Нужен при развёртывании: без него бот не знает, кому слать уведомления о
# продажах, а команды владельца не работают ни у кого.
sent.clear()
asyncio.run(B.cmd_id(FakeMessage("/id", 5555)))
has("бот показывает telegram id", sent[0], "5555")

print(f"все проверки пройдены: {checks}")
