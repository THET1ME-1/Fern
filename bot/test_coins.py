#!/usr/bin/env python3
"""Проверки модуля монет Togetherly: python3 bot/test_coins.py"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

import coins  # noqa: E402


def check(name, got, want):
    ok = got == want
    print(("ок   " if ok else "ПЛОХО") + f"  {name}")
    if not ok:
        print(f"        ждали: {want!r}")
        print(f"        вышло: {got!r}")
    return ok


def main():
    results = []

    # ── товары ──────────────────────────────────────────────────────────────
    results.append(check(
        "600 монет по uuid товара",
        coins.coins_for("4d8ff539-fd74-47ab-85e4-35906be3a5b4"), 600))
    results.append(check(
        "1400 монет",
        coins.coins_for("64e68f3f-7281-4593-aa00-0b438522750b"), 1400))
    results.append(check(
        "4000 монет",
        coins.coins_for("cd2e08ec-e826-495d-bb55-842a3e3742dc"), 4000))
    results.append(check(
        "uuid в верхнем регистре тоже узнаётся",
        coins.coins_for("4D8FF539-FD74-47AB-85E4-35906BE3A5B4"), 600))
    results.append(check(
        "чужой товар — не наш",
        coins.coins_for("00000000-0000-0000-0000-000000000000"), None))
    results.append(check(
        "пустой товар — не наш",
        coins.coins_for(None), None))

    # ── коды ────────────────────────────────────────────────────────────────
    code = coins.make_code()
    results.append(check("код начинается с TG", code[:2], "TG"))
    results.append(check("код длиной 12 с дефисами", len(code), 12))
    results.append(check(
        "в коде нет похожих символов 0 O 1 I",
        any(ch in code for ch in "0O1I"), False))
    results.append(check(
        "нормализация чистит регистр, пробелы и дефисы",
        coins.normalize(" tg-4f2a b19c "), "TG4F2AB19C"))

    codes = {coins.make_code() for _ in range(500)}
    results.append(check("500 кодов не повторяются", len(codes), 500))

    print()
    print(f"{sum(results)} из {len(results)}")
    return 0 if all(results) else 1


if __name__ == "__main__":
    raise SystemExit(main())
