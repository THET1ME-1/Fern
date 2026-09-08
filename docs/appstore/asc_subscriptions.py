#!/usr/bin/env python3
"""Подписки Fern Pro в App Store Connect — через API, а не руками.

    python3 asc_subscriptions.py state    # что уже заведено
    python3 asc_subscriptions.py setup    # завести группу, товары, цены, тексты

Ключ и идентификаторы берутся из `asc.py` (окружение ASC_*). Скрипт
идемпотентный: существующее не пересоздаёт, недостающее добавляет.

ЧТО ОСТАЁТСЯ ЧЕЛОВЕКУ. Apple требует у подписки скриншот для проверки и
соглашения о платных приложениях; загрузка снимка идёт через отдельный
трёхшаговый upload, и делать его вслепую нельзя — экран подписки должен быть
снят на живом iPhone.
"""
from __future__ import annotations

import sys

import asc

ГРУППА = 'Fern Pro'

# Товары. Имена совпадают с Play Console: тариф читается по хвосту `_month`
# и `_year` и в приложении, и на сервере.
ТОВАРЫ = [
    {
        'productId': 'fern_pro_month',
        'name': 'Fern Pro на месяц',
        'period': 'ONE_MONTH',
        # Описание у Apple не длиннее 55 знаков — это их предел, не наш выбор.
        'ru': ('Fern Pro на месяц',
               'Книги, видео и статьи без счёта. Раз в месяц'),
        'en': ('Fern Pro monthly',
               'Books, videos and articles, no limits. Monthly'),
    },
    {
        'productId': 'fern_pro_year',
        'name': 'Fern Pro на год',
        'period': 'ONE_YEAR',
        'ru': ('Fern Pro на год',
               'То же самое, выгоднее вдвое. Списание раз в год'),
        'en': ('Fern Pro yearly',
               'Same, at nearly half the price. Billed yearly'),
    },
]

# Цены задаём по базовой территории США: остальные страны Apple считает сама.
ЦЕНЫ = {'fern_pro_month': '4.99', 'fern_pro_year': '34.99'}
БАЗОВАЯ_СТРАНА = 'USA'


def группы() -> list[dict]:
    return asc.get(f'/v1/apps/{asc.APP_ID}/subscriptionGroups', **{'limit': '20'})['data']


def подписки(group_id: str) -> list[dict]:
    return asc.get(f'/v1/subscriptionGroups/{group_id}/subscriptions',
                   **{'limit': '50'})['data']


def завести_группу() -> str:
    для_группы = [g for g in группы()
                  if g['attributes'].get('referenceName') == ГРУППА]
    if для_группы:
        print(f'   группа уже есть: {для_группы[0]["id"]}')
        return для_группы[0]['id']
    g = asc.call('POST', '/v1/subscriptionGroups', json={'data': {
        'type': 'subscriptionGroups',
        'attributes': {'referenceName': ГРУППА},
        'relationships': {'app': {'data': {'type': 'apps', 'id': asc.APP_ID}}},
    }})['data']
    print(f'   группа заведена: {g["id"]}')
    return g['id']


def назвать_группу(group_id: str) -> None:
    """Имя группы видит покупатель в настройках подписок Apple."""
    было = asc.get(f'/v1/subscriptionGroups/{group_id}/subscriptionGroupLocalizations',
                   **{'limit': '10'})['data']
    языки = {л['attributes'].get('locale') for л in было}
    for локаль, имя in (('ru', 'Fern Pro'), ('en-US', 'Fern Pro')):
        if локаль in языки:
            continue
        asc.call('POST', '/v1/subscriptionGroupLocalizations', json={'data': {
            'type': 'subscriptionGroupLocalizations',
            'attributes': {'name': имя, 'locale': локаль},
            'relationships': {'subscriptionGroup': {
                'data': {'type': 'subscriptionGroups', 'id': group_id}}},
        }})
        print(f'   имя группы для {локаль}')


def завести_товар(group_id: str, товар: dict, готовые: dict) -> str:
    если_есть = готовые.get(товар['productId'])
    if если_есть:
        print(f'   {товар["productId"]}: уже есть ({если_есть})')
        return если_есть
    s = asc.call('POST', '/v1/subscriptions', json={'data': {
        'type': 'subscriptions',
        'attributes': {
            'name': товар['name'],
            'productId': товар['productId'],
            'subscriptionPeriod': товар['period'],
            # Семейный доступ не включаем: подписка и так открывается на всех
            # устройствах человека, а «поделиться с семьёй» это другая история.
            'familySharable': False,
        },
        'relationships': {'group': {
            'data': {'type': 'subscriptionGroups', 'id': group_id}}},
    }})['data']
    print(f'   {товар["productId"]}: заведён ({s["id"]})')
    return s['id']


def тексты(sub_id: str, товар: dict) -> None:
    было = asc.get(f'/v1/subscriptions/{sub_id}/subscriptionLocalizations',
                   **{'limit': '10'})['data']
    языки = {л['attributes'].get('locale') for л in было}
    for локаль, ключ in (('ru', 'ru'), ('en-US', 'en')):
        if локаль in языки:
            continue
        имя, описание = товар[ключ]
        asc.call('POST', '/v1/subscriptionLocalizations', json={'data': {
            'type': 'subscriptionLocalizations',
            'attributes': {'name': имя, 'description': описание, 'locale': локаль},
            'relationships': {'subscription': {
                'data': {'type': 'subscriptions', 'id': sub_id}}},
        }})
        print(f'      текст {локаль}')


def цена(sub_id: str, товар_id: str) -> None:
    """Цена задаётся точкой прайса Apple: своих чисел у них нет, есть сетка."""
    уже = asc.get(f'/v1/subscriptions/{sub_id}/prices', **{'limit': '5'})['data']
    if уже:
        print('      цена уже задана')
        return
    нужно = ЦЕНЫ[товар_id]
    # Точек прайса у Apple больше двух сотен, и годовые цены лежат в хвосте:
    # без разбора страниц 34.99 просто не попадала в выборку.
    точки = []
    путь = (f'/v1/subscriptions/{sub_id}/pricePoints'
            f'?filter[territory]={БАЗОВАЯ_СТРАНА}&limit=200')
    while путь:
        ответ = asc.call('GET', путь)
        точки += ответ['data']
        следующая = (ответ.get('links') or {}).get('next')
        путь = следующая.replace(asc.BASE, '') if следующая else None
    подходящие = [т for т in точки
                  if т['attributes'].get('customerPrice') == нужно]
    if not подходящие:
        доступные = sorted({т['attributes'].get('customerPrice') for т in точки})
        print(f'      точки {нужно} нет; рядом: {доступные[:12]}')
        return
    # Цена через API у Apple не встаёт: на POST /v1/subscriptionPrices сервер
    # отвечает 409 «An error occurred while processing the pricing
    # information», а с датой старта — 500 «unexpected error on the server
    # side». Формат перебран (с территорией и без, с preserveCurrentPrice и
    # без, с датой и без), товар и точка прайса свои. Оставляем попытку и НЕ
    # роняем проход: остальное заводится, цену ставят в консоли одним полем.
    try:
        asc.call('POST', '/v1/subscriptionPrices', json={'data': {
            'type': 'subscriptionPrices',
            'attributes': {'preserveCurrentPrice': False},
            'relationships': {
                'subscription': {'data': {'type': 'subscriptions', 'id': sub_id}},
                'subscriptionPricePoint': {'data': {
                    'type': 'subscriptionPricePoints', 'id': подходящие[0]['id']}},
            },
        }})
        print(f'      цена {нужно} $ по территории {БАЗОВАЯ_СТРАНА}')
    except SystemExit:
        print(f'      цену {нужно} $ Apple через API не принял — ставить в консоли')


def state() -> None:
    гр = группы()
    if not гр:
        print('групп подписок нет')
        return
    for g in гр:
        print(f'группа {g["attributes"].get("referenceName")} ({g["id"]})')
        for s in подписки(g['id']):
            a = s['attributes']
            цены = asc.get(f'/v1/subscriptions/{s["id"]}/prices', **{'limit': '5'})['data']
            локали = asc.get(f'/v1/subscriptions/{s["id"]}/subscriptionLocalizations',
                             **{'limit': '10'})['data']
            print(f'   {a.get("productId")}: {a.get("subscriptionPeriod")}, '
                  f'состояние {a.get("state")}, цен {len(цены)}, '
                  f'языков {len(локали)}')


def setup() -> None:
    print('→ группа подписок')
    group_id = завести_группу()
    назвать_группу(group_id)

    готовые = {s['attributes'].get('productId'): s['id']
               for s in подписки(group_id)}
    print('→ товары')
    for товар in ТОВАРЫ:
        sub_id = завести_товар(group_id, товар, готовые)
        тексты(sub_id, товар)
        цена(sub_id, товар['productId'])
    print('готово')


if __name__ == '__main__':
    команда = sys.argv[1] if len(sys.argv) > 1 else 'state'
    {'state': state, 'setup': setup}.get(команда, state)()
