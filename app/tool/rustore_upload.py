#!/usr/bin/env python3
"""Загрузка APK в RuStore через Public API.

Своими руками, а не чужим GitHub Action: любой сторонний шаг workflow получил бы
доступ к приватному ключу RuStore, а он открывает публикацию приложения.

Зависимостей нет. RSA-подпись считает openssl (в stdlib криптографии нет, а
ставить `cryptography` на раннер ради одной подписи — лишний шаг, который может
сломаться в самый неудобный момент).

Порядок вызовов API:
  1. POST /public/auth/                     — keyId + timestamp + подпись → JWE
  2. POST .../version                       — черновик версии → versionId
  3. POST .../version/{id}/apk              — файл APK
  4. POST .../version/{id}/commit           — отправка на модерацию

Публикация после модерации остаётся ручной (publishType=MANUAL): выкатывать
версию людям должен человек, а не тег.

Использование:
    RUSTORE_KEY_ID=... RUSTORE_PRIVATE_KEY=<base64> \\
        python3 tool/rustore_upload.py --apk dist/Fern-1.18.1-rustore.apk \\
                                       --whats-new CHANGELOG-фрагмент.txt

    python3 tool/rustore_upload.py --selftest   # проверка подписи без сети
"""

from __future__ import annotations

import argparse
import base64
import json
import os
import ssl
import subprocess
import sys
import tempfile
import textwrap
import urllib.error
import urllib.request
import uuid
from datetime import datetime, timezone

API = "https://public-api.rustore.ru"
PACKAGE = "com.fern.app"

# Лимит поля «Что нового» в карточке RuStore.
WHATS_NEW_LIMIT = 5000


class RuStoreError(RuntimeError):
    """Ошибка API или подготовки запроса — печатается человеку как есть."""


# ─────────────────────────────── подпись ──────────────────────────────────


def pem_from_base64(key_b64: str) -> str:
    """Ключ из консоли RuStore (base64 от PKCS#8 DER) в PEM для openssl."""
    body = "".join(key_b64.split())
    try:
        base64.b64decode(body, validate=True)
    except Exception as exc:  # noqa: BLE001 — сообщение важнее типа
        raise RuStoreError(f"Приватный ключ не разбирается как base64: {exc}") from exc
    lines = "\n".join(textwrap.wrap(body, 64))
    return f"-----BEGIN PRIVATE KEY-----\n{lines}\n-----END PRIVATE KEY-----\n"


def sign(message: str, key_b64: str) -> str:
    """RSA-SHA512 подпись сообщения, в base64. Считает openssl."""
    pem = pem_from_base64(key_b64)
    with tempfile.NamedTemporaryFile("w", suffix=".pem", delete=False) as f:
        f.write(pem)
        path = f.name
    try:
        proc = subprocess.run(
            ["openssl", "dgst", "-sha512", "-sign", path],
            input=message.encode(),
            capture_output=True,
        )
        if proc.returncode != 0:
            raise RuStoreError(
                "openssl не смог подписать запрос: "
                + proc.stderr.decode(errors="replace").strip()
            )
        return base64.b64encode(proc.stdout).decode()
    finally:
        os.unlink(path)


def timestamp_now() -> str:
    """ISO 8601 с миллисекундами и смещением зоны, как ждёт API.

    Подпись живёт минуту, поэтому время берём машинное и в UTC: раннер с
    уехавшими часами получит внятную ошибку авторизации, а не загадочную.
    """
    now = datetime.now(timezone.utc).astimezone()
    base = now.strftime("%Y-%m-%dT%H:%M:%S")
    millis = f"{now.microsecond // 1000:03d}"
    offset = now.strftime("%z")
    return f"{base}.{millis}{offset[:3]}:{offset[3:]}"


# ─────────────────────────────── запросы ──────────────────────────────────


def request(
    method: str,
    url: str,
    *,
    token: str | None = None,
    payload: dict | None = None,
    file_path: str | None = None,
) -> dict:
    """Один вызов API. Возвращает разобранное тело ответа."""
    headers = {"Accept": "application/json"}
    if token:
        headers["Public-Token"] = token

    if file_path:
        boundary = uuid.uuid4().hex
        name = os.path.basename(file_path)
        with open(file_path, "rb") as f:
            content = f.read()
        body = b"".join(
            [
                f"--{boundary}\r\n".encode(),
                f'Content-Disposition: form-data; name="file"; filename="{name}"\r\n'.encode(),
                b"Content-Type: application/vnd.android.package-archive\r\n\r\n",
                content,
                f"\r\n--{boundary}--\r\n".encode(),
            ]
        )
        headers["Content-Type"] = f"multipart/form-data; boundary={boundary}"
    elif payload is not None:
        body = json.dumps(payload).encode()
        headers["Content-Type"] = "application/json"
    else:
        body = None

    req = urllib.request.Request(url, data=body, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, context=ssl.create_default_context()) as resp:
            raw = resp.read().decode()
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode(errors="replace")
        raise RuStoreError(f"{method} {url} → HTTP {exc.code}\n{detail}") from exc
    except urllib.error.URLError as exc:
        raise RuStoreError(f"{method} {url} → сеть недоступна: {exc.reason}") from exc

    data = json.loads(raw) if raw else {}
    if data.get("code") not in (None, "OK"):
        raise RuStoreError(f"{method} {url} → {data.get('code')}: {data.get('message')}")
    return data


def authenticate(key_id: str, key_b64: str) -> str:
    """JWE-токен на 15 минут."""
    ts = timestamp_now()
    data = request(
        "POST",
        f"{API}/public/auth/",
        payload={
            "keyId": key_id,
            "timestamp": ts,
            "signature": sign(key_id + ts, key_b64),
        },
    )
    token = (data.get("body") or {}).get("jwe")
    if not token:
        raise RuStoreError(f"Ответ авторизации без токена: {data}")
    return token


def create_draft(token: str, whats_new: str, contacts: str) -> int:
    """Черновик версии. На приложение он может быть только один."""
    payload = {
        "publishType": "MANUAL",
        "whatsNew": whats_new[:WHATS_NEW_LIMIT],
        "developerContacts": contacts,
    }
    try:
        data = request(
            "POST", f"{API}/public/v1/application/{PACKAGE}/version",
            token=token, payload=payload,
        )
    except RuStoreError as exc:
        raise RuStoreError(
            f"{exc}\n\nЕсли черновик уже существует — удали или опубликуй его в "
            "RuStore Консоли: второй черновик API создать не даст."
        ) from exc
    version_id = data.get("body")
    if not isinstance(version_id, int):
        raise RuStoreError(f"Ответ без versionId: {data}")
    return version_id


def upload_apk(token: str, version_id: int, apk: str) -> None:
    url = (
        f"{API}/public/v1/application/{PACKAGE}/version/{version_id}/apk"
        "?servicesType=Unknown&isMainApk=true"
    )
    request("POST", url, token=token, file_path=apk)


def commit(token: str, version_id: int) -> None:
    request(
        "POST",
        f"{API}/public/v1/application/{PACKAGE}/version/{version_id}/commit",
        token=token,
    )


# ────────────────────────────── самопроверка ──────────────────────────────


def selftest() -> int:
    """Подпись без сети: свой ключ, своя проверка тем же openssl."""
    with tempfile.TemporaryDirectory() as tmp:
        key = os.path.join(tmp, "key.pem")
        pub = os.path.join(tmp, "pub.pem")
        subprocess.run(
            ["openssl", "genpkey", "-algorithm", "RSA", "-out", key,
             "-pkeyopt", "rsa_keygen_bits:2048"],
            check=True, capture_output=True,
        )
        subprocess.run(
            ["openssl", "rsa", "-in", key, "-pubout", "-out", pub],
            check=True, capture_output=True,
        )
        with open(key) as f:
            key_b64 = "".join(
                line.strip() for line in f if "-----" not in line
            )

        message = "12345" + timestamp_now()
        signature = sign(message, key_b64)

        sig_path = os.path.join(tmp, "sig.bin")
        with open(sig_path, "wb") as f:
            f.write(base64.b64decode(signature))
        proc = subprocess.run(
            ["openssl", "dgst", "-sha512", "-verify", pub, "-signature", sig_path],
            input=message.encode(), capture_output=True,
        )
        ok = proc.returncode == 0
        print("подпись RSA-SHA512:", "✓ проверена" if ok else "✖ не сошлась")
        print("timestamp:", timestamp_now())
        return 0 if ok else 1


# ──────────────────────────────── запуск ──────────────────────────────────


def main() -> int:
    parser = argparse.ArgumentParser(description="Загрузка APK в RuStore")
    parser.add_argument("--apk", help="путь к APK")
    parser.add_argument("--whats-new", help="файл с текстом «Что нового»")
    parser.add_argument(
        "--contacts",
        default="https://t.me/SnTAppsBot",
        help="контакт разработчика для карточки",
    )
    parser.add_argument("--selftest", action="store_true", help="проверка подписи без сети")
    args = parser.parse_args()

    if args.selftest:
        return selftest()

    if not args.apk:
        parser.error("нужен --apk или --selftest")

    key_id = os.environ.get("RUSTORE_KEY_ID", "").strip()
    key_b64 = os.environ.get("RUSTORE_PRIVATE_KEY", "").strip()
    if not key_id or not key_b64:
        raise RuStoreError("Нет RUSTORE_KEY_ID или RUSTORE_PRIVATE_KEY в окружении")
    if not os.path.isfile(args.apk):
        raise RuStoreError(f"APK не найден: {args.apk}")

    whats_new = ""
    if args.whats_new and os.path.isfile(args.whats_new):
        with open(args.whats_new, encoding="utf-8") as f:
            whats_new = f.read().strip()

    size_mb = os.path.getsize(args.apk) / 1024 / 1024
    print(f"▶ {os.path.basename(args.apk)} ({size_mb:.0f} МБ) → RuStore")

    token = authenticate(key_id, key_b64)
    print("  ✓ авторизация")

    version_id = create_draft(token, whats_new, args.contacts)
    print(f"  ✓ черновик версии {version_id}")

    upload_apk(token, version_id, args.apk)
    print("  ✓ APK загружен")

    commit(token, version_id)
    print("  ✓ отправлено на модерацию")
    print("\nПосле проверки версию нужно опубликовать вручную в RuStore Консоли.")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except RuStoreError as error:
        print(f"✖ {error}", file=sys.stderr)
        sys.exit(1)
