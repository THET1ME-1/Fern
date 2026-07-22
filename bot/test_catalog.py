#!/usr/bin/env python3
"""Проверки витрины: python3 bot/test_catalog.py"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

import catalog  # noqa: E402
import coins  # noqa: E402


def check(name, got, want):
    ok = got == want
    print(("ок   " if ok else "ПЛОХО") + f"  {name}")
    if not ok:
        print(f"        ждали: {want!r}\n        вышло: {got!r}")
    return ok


def main():
    r = []
    r.append(check("в магазине два приложения", catalog.app_ids(),
                   ["fern", "togetherly"]))
    r.append(check("у Togetherly три пака", len(catalog.items("togetherly")), 3))
    r.append(check("у Fern один товар", len(catalog.items("fern")), 1))
    r.append(check("неизвестное приложение — None", catalog.app("нет"), None))

    # ссылки на монеты обязаны совпадать с товарами, которые знает бот:
    # иначе человек заплатит, а код не создастся
    ids_in_links = []
    for item in catalog.items("togetherly"):
        r.append(check(f"ссылка {item['id']} ведёт на lava.top",
                       item["url"].startswith("https://app.lava.top/products/"),
                       True))
        ids_in_links.append(item["url"].rsplit("/", 1)[-1])
    for uuid in ids_in_links:
        r.append(check(f"товар {uuid[:8]}… известен модулю монет",
                       coins.coins_for(uuid) is not None, True))

    card = catalog.card("togetherly")
    r.append(check("в карточке есть все три пака",
                   all(i["title"] in card for i in catalog.items("togetherly")),
                   True))
    r.append(check("подпись кнопки со значком", catalog.title("fern"), "🌿 Fern"))

    print(f"\n{sum(r)} из {len(r)}")
    return 0 if all(r) else 1


if __name__ == "__main__":
    raise SystemExit(main())
