#!/usr/bin/env python3
"""Витрина магазина: приложения и их товары.

Данные держим отдельно от `bot.py`: добавить приложение или пак должно быть
правкой одного списка, а не хендлеров. Цены здесь намеренно нет — она живёт
на lava.top, и два места с ценой однажды разойдутся.
"""
from __future__ import annotations

APPS = {
    "fern": {
        "emoji": "🌿",
        "name": "Fern",
        "tagline": "карточки для изучения языков",
        "about": (
            "Карточки, которые берут слова из ваших книг и видео.\n\n"
            "📖 Книги EPUB, FB2 и TXT: тап по слову даёт перевод и карточку\n"
            "🎬 Видео с субтитрами, статьи по ссылке и текст с фотографии\n"
            "📥 Импорт колод из Anki и таблиц CSV\n"
            "♾ Разовая покупка: навсегда и на всех ваших устройствах"
        ),
        "items": [
            {
                "id": "fern_pro",
                "title": "Fern Pro",
                "note": "полная версия навсегда",
                "url": "https://app.lava.top/products/fern-pro",
                "kind": "key",
            },
        ],
    },
    "togetherly": {
        "emoji": "💛",
        "name": "Togetherly",
        "tagline": "приложение для пар",
        "about": (
            "Монеты — внутренняя валюта: на них берут подарки партнёру, темы "
            "и значки профиля.\n\n"
            "🎁 34 подарка: у каждого своя механика\n"
            "🎨 Темы оформления и значки\n"
            "🪙 Монеты приходят кодом сразу после оплаты"
        ),
        "items": [
            {
                "id": "coins_600",
                "title": "600 монет",
                "note": "хватает на десяток подарков",
                "url": "https://app.lava.top/products/"
                       "4d8ff539-fd74-47ab-85e4-35906be3a5b4",
                "kind": "coins",
            },
            {
                "id": "coins_1400",
                "title": "1400 монет",
                "note": "выгоднее, чем два маленьких",
                "url": "https://app.lava.top/products/"
                       "64e68f3f-7281-4593-aa00-0b438522750b",
                "kind": "coins",
            },
            {
                "id": "coins_4000",
                "title": "4000 монет",
                "note": "весь каталог подарков и ещё останется",
                "url": "https://app.lava.top/products/"
                       "cd2e08ec-e826-495d-bb55-842a3e3742dc",
                "kind": "coins",
            },
        ],
    },
}


def app_ids() -> list[str]:
    return list(APPS.keys())


def app(app_id: str) -> dict | None:
    return APPS.get(app_id)


def title(app_id: str) -> str:
    """Подпись кнопки в списке приложений."""
    a = APPS.get(app_id)
    return f"{a['emoji']} {a['name']}" if a else app_id


def card(app_id: str) -> str:
    """Карточка приложения: что это и что продаётся."""
    a = APPS.get(app_id)
    if not a:
        return ""
    lines = [f"{a['emoji']} <b>{a['name']}</b> — {a['tagline']}", "", a["about"], ""]
    lines.append("<b>Что можно купить</b>")
    for item in a["items"]:
        lines.append(f"• {item['title']} — {item['note']}")
    lines.append("")
    lines.append(
        "Оплата проходит на lava.top. После оплаты вернитесь сюда и пришлите "
        "почту, которую указали при покупке."
    )
    return "\n".join(lines)


def items(app_id: str) -> list[dict]:
    a = APPS.get(app_id)
    return list(a["items"]) if a else []
