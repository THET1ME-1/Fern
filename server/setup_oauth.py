#!/usr/bin/env python3
"""Вход через Google и Apple для аккаунтов Fern.

Провайдеры уже настроены у Togetherly: тот же сервер, тот же адрес возврата
(`/api/oauth2-redirect`), те же клиенты в консолях Google и Apple. Заводить
вторые незачем — скрипт копирует настройки в `fern_users`.

    PB_SUPERUSER_EMAIL=... PB_SUPERUSER_PASSWORD=... python3 setup_oauth.py
    python3 setup_oauth.py --dry

Аккаунты от этого не смешиваются: общий у приложений только OAuth-клиент,
которым человек доказывает, что почта его. Записи, сессии и подписки лежат в
разных коллекциях.

Секреты в вывод не попадают — печатаются только имена провайдеров.
"""
from __future__ import annotations

import argparse
import json
import os
import sqlite3

from setup_collections import войти, получить, запрос

# API отдаёт настройки провайдера с ПУСТЫМ секретом — PocketBase его прячет.
# Настройки коллекций при этом лежат в базе открытым текстом (шифрование
# `--encryptionEnv` на этом сервере не включено), поэтому секрет берём оттуда.
БАЗА = os.environ.get("PB_DATA", "/opt/pocketbase/pb_data/data.db")


def провайдеры_из_базы(коллекция: str) -> dict:
    """Настройки OAuth2 прямо из SQLite: {имя провайдера: настройки}."""
    try:
        con = sqlite3.connect(f"file:{БАЗА}?mode=ro", uri=True, timeout=10)
    except sqlite3.Error as e:
        raise SystemExit(f"база PocketBase не читается: {e}")
    try:
        строка = con.execute(
            "SELECT options FROM _collections WHERE name = ?", (коллекция,)
        ).fetchone()
    finally:
        con.close()
    if not строка:
        return {}
    настройки = json.loads(строка[0] or "{}")
    провайдеры = (настройки.get("oauth2") or {}).get("providers") or []
    return {p.get("name"): p for p in провайдеры}

# Какие способы входа переносим. Яндекс Togetherly оставляем себе: в Fern о нём
# никто не просил, а лишний провайдер — лишняя поверхность.
ПРОВАЙДЕРЫ = ("google", "apple")


def main() -> None:
    ap = argparse.ArgumentParser(description="Google и Apple для аккаунтов Fern")
    ap.add_argument("--dry", action="store_true", help="только показать план")
    args = ap.parse_args()

    токен = войти()
    источник = получить(токен, "users")
    цель = получить(токен, "fern_users")
    if источник is None or цель is None:
        raise SystemExit("нет коллекции users или fern_users")

    готовые = провайдеры_из_базы("users")
    if not готовые:
        готовые = {p.get("name"): p
                   for p in источник.get("oauth2", {}).get("providers", [])}
    нужные = [готовые[имя] for имя in ПРОВАЙДЕРЫ if имя in готовые]
    если_нет = [имя for имя in ПРОВАЙДЕРЫ if имя not in готовые]
    for имя in если_нет:
        print(f"у Togetherly нет провайдера {имя} — пропускаю")

    уже = {p.get("name") for p in цель.get("oauth2", {}).get("providers", [])}
    добавить = [p for p in нужные if p.get("name") not in уже]
    if not добавить:
        print("вход через Google и Apple уже настроен")
        return
    if args.dry:
        print("добавились бы:", [p.get("name") for p in добавить])
        return

    цель["oauth2"] = {
        "enabled": True,
        "mappedFields": цель.get("oauth2", {}).get("mappedFields", {}),
        "providers": цель.get("oauth2", {}).get("providers", []) + добавить,
    }
    код, ответ = запрос("PATCH", "/api/collections/fern_users", токен, цель)
    if код != 200:
        raise SystemExit(f"не вышло: {код} {ответ}")
    print("добавлены способы входа:", [p.get("name") for p in добавить])

    проверка = получить(токен, "fern_users")
    имена = [p.get("name") for p in проверка.get("oauth2", {}).get("providers", [])]
    print("теперь в fern_users:", имена)


if __name__ == "__main__":
    main()
