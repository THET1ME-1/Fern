#!/usr/bin/env python3
"""Выдача лицензий Fern Pro.

Ключ = base32(payload‖подпись), где payload — 8 байт, подпись — Ed25519 над
ними. Приложение проверяет подпись публичным ключом и работает офлайн:
`app/lib/services/license_service.dart`.

Приватный ключ в репозитории НЕ лежит. По умолчанию берётся из
`~/.config/fern/license_ed25519.key` (base64, права 600) или из переменной
окружения `FERN_LICENSE_KEY`.

    python3 bot/license.py --id 42            # выдать ключ №42
    python3 bot/license.py --pubkey           # показать публичный ключ
    python3 bot/license.py --verify FERN...   # проверить чужой ключ
"""
from __future__ import annotations

import argparse
import base64
import os
import struct
from datetime import date, datetime, timezone
from pathlib import Path

from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import (
    Ed25519PrivateKey,
    Ed25519PublicKey,
)

ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
PREFIX = "FERN"
FORMAT_VERSION = 1        # ключ без почты: выпускался до 1.17.3
FORMAT_VERSION_EMAIL = 2  # именной: внутри почта покупателя
# Товары магазина: один выпускающий ключ обслуживает несколько приложений.
# Номер едет внутри ключа, приложение проверяет свой и чужой не примет.
SKU_PRO = 1        # Fern Pro
SKU_KADR = 2       # задел: Kadr
SKU_WICKLY = 3     # задел: Wickly
EPOCH = date(2026, 1, 1)
KEY_PATH = Path(os.environ.get("FERN_LICENSE_KEY_PATH",
                               Path.home() / ".config/fern/license_ed25519.key"))


def b32encode(data: bytes) -> str:
    """RFC 4648 без выравнивания — тот же алфавит, что в приложении."""
    out, buffer, bits = [], 0, 0
    for byte in data:
        buffer = (buffer << 8) | byte
        bits += 8
        while bits >= 5:
            out.append(ALPHABET[(buffer >> (bits - 5)) & 31])
            bits -= 5
    if bits:
        out.append(ALPHABET[(buffer << (5 - bits)) & 31])
    return "".join(out)


def b32decode(text: str) -> bytes:
    out, buffer, bits = bytearray(), 0, 0
    for ch in text:
        value = ALPHABET.find(ch)
        if value < 0:
            raise ValueError(f"лишний символ в ключе: {ch!r}")
        buffer = (buffer << 5) | value
        bits += 5
        if bits >= 8:
            out.append((buffer >> (bits - 8)) & 0xFF)
            bits -= 8
    return bytes(out)


def load_private_key() -> Ed25519PrivateKey:
    raw = os.environ.get("FERN_LICENSE_KEY")
    if raw is None:
        if not KEY_PATH.exists():
            raise SystemExit(
                f"нет приватного ключа: {KEY_PATH}\n"
                "создать: python3 bot/license.py --generate-keypair")
        raw = KEY_PATH.read_text().strip()
    return Ed25519PrivateKey.from_private_bytes(base64.b64decode(raw))


def build_payload(license_id: int, issued: date | None = None,
                  sku: int = SKU_PRO, email: str | None = None) -> bytes:
    """Тело ключа. С почтой — формат 2, без неё — прежний формат 1.

    Почта лежит открытым текстом и видна в настройках приложения. Скопировать
    ключ это не мешает, но выложить его на форум вместе со своим адресом
    желающих куда меньше — а если такой найдётся, сразу видно, чей номер
    отзывать.
    """
    issued = issued or datetime.now(timezone.utc).date()
    days = (issued - EPOCH).days
    if not 0 <= days <= 0xFFFF:
        raise ValueError("дата выдачи вне диапазона формата")
    if not 0 <= license_id <= 0xFFFFFFFF:
        raise ValueError("номер лицензии вне диапазона формата")
    if not 0 <= sku <= 0xFF:
        raise ValueError("номер товара вне диапазона формата")
    if email is None:
        return struct.pack(">BBIH", FORMAT_VERSION, sku, license_id, days)

    raw = email.strip().lower().encode("utf-8")
    if not raw or len(raw) > 255:
        raise ValueError("почта пустая или длиннее 255 байт")
    return (struct.pack(">BBIHB", FORMAT_VERSION_EMAIL, sku, license_id,
                        days, len(raw)) + raw)


def issue(license_id: int, issued: date | None = None,
          key: Ed25519PrivateKey | None = None, sku: int = SKU_PRO,
          email: str | None = None) -> str:
    """Ключ для покупателя. `license_id` — сквозной номер из журнала бота,
    `sku` — какой товар куплен (см. константы SKU_*), `email` — адрес, на
    который оформлена покупка: он едет внутри ключа и виден в приложении."""
    key = key or load_private_key()
    payload = build_payload(license_id, issued, sku=sku, email=email)
    return PREFIX + b32encode(payload + key.sign(payload))


def verify(text: str, public_key: bytes | None = None) -> dict | None:
    """Разбирает ключ; None — не годен. Ровно та же логика, что в приложении."""
    text = "".join(ch for ch in text.upper() if ch not in " -\n\t")
    if not text.startswith(PREFIX):
        return None
    try:
        blob = b32decode(text[len(PREFIX):])
    except ValueError:
        return None
    if len(blob) < 72:
        return None
    email = None
    version = blob[0]
    if version == FORMAT_VERSION:
        if len(blob) != 72:
            return None
        payload, signature = blob[:8], blob[8:]
        _, sku, license_id, days = struct.unpack(">BBIH", payload)
    elif version == FORMAT_VERSION_EMAIL:
        length = blob[8]
        head = 9 + length
        if len(blob) != head + 64:
            return None
        payload, signature = blob[:head], blob[head:]
        _, sku, license_id, days, _ = struct.unpack(">BBIHB", payload[:9])
        try:
            email = payload[9:].decode("utf-8")
        except UnicodeDecodeError:
            return None
    else:
        return None
    if public_key is None:
        public_key = load_private_key().public_key().public_bytes(
            serialization.Encoding.Raw, serialization.PublicFormat.Raw)
    try:
        Ed25519PublicKey.from_public_bytes(public_key).verify(signature, payload)
    except InvalidSignature:
        return None
    return {"id": license_id, "sku": sku, "email": email,
            "issued": EPOCH.fromordinal(EPOCH.toordinal() + days)}


def main() -> None:
    ap = argparse.ArgumentParser(description="Лицензии Fern Pro")
    ap.add_argument("--id", type=int, help="номер лицензии")
    ap.add_argument("--date", help="дата выдачи ГГГГ-ММ-ДД (по умолчанию сегодня)")
    ap.add_argument("--pubkey", action="store_true", help="показать публичный ключ")
    ap.add_argument("--verify", metavar="KEY", help="проверить ключ")
    ap.add_argument("--generate-keypair", action="store_true",
                    help="создать пару ключей (один раз на проект)")
    args = ap.parse_args()

    if args.generate_keypair:
        if KEY_PATH.exists():
            raise SystemExit(f"ключ уже есть: {KEY_PATH} — перезапись запрещена")
        key = Ed25519PrivateKey.generate()
        KEY_PATH.parent.mkdir(parents=True, exist_ok=True)
        KEY_PATH.write_text(base64.b64encode(key.private_bytes(
            serialization.Encoding.Raw, serialization.PrivateFormat.Raw,
            serialization.NoEncryption())).decode() + "\n")
        KEY_PATH.chmod(0o600)
        pub = key.public_key().public_bytes(
            serialization.Encoding.Raw, serialization.PublicFormat.Raw)
        print(f"приватный ключ: {KEY_PATH}")
        print(f"публичный (в license_service.dart): {base64.b64encode(pub).decode()}")
        return

    if args.pubkey:
        pub = load_private_key().public_key().public_bytes(
            serialization.Encoding.Raw, serialization.PublicFormat.Raw)
        print(base64.b64encode(pub).decode())
        return

    if args.verify:
        info = verify(args.verify)
        print(f"годен: №{info['id']}, выдан {info['issued']}" if info else "не годен")
        return

    if args.id is None:
        ap.error("нужен --id (или --pubkey / --verify / --generate-keypair)")
    issued = date.fromisoformat(args.date) if args.date else None
    print(issue(args.id, issued))


if __name__ == "__main__":
    main()
