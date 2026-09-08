#!/usr/bin/env python3
"""Подписки Fern Pro в Google Play — через API, а не руками.

    python3 play_subscriptions.py state    # что заведено
    python3 play_subscriptions.py setup    # завести товары, цены, активировать

Цены по миру считает сам Google (`pricing:convertRegionPrices`), а Россию
задаём явно: конвертация от доллара даёт около 460 ₽, и цена разошлась бы с
витриной lava.top, где стоит 299 ₽.

Ключ — СВОЙ у Fern (`~/keys/fern-play-service-account.json`). Ключ Togetherly
на это приложение прав не имеет, и его отказ легко принять за отсутствие
доступа вообще.
"""
from __future__ import annotations

import sys

import play_api as p

# Тарифы. Идентификаторы совпадают с App Store Connect: приложение и сервер
# читают тариф по хвосту имени.
ТАРИФЫ = [
    {
        'productId': 'fern_pro_month',
        'basePlanId': 'monthly',
        'period': 'P1M',
        'usd': ('4', 990000000),
        'rub': ('299', 0),
        'ru': ('Fern Pro на месяц',
               'Книги, видео, статьи и текст с фотографии без счёта, перенос '
               'колод из Anki. Списание раз в месяц, отмена в любой день.'),
        'en': ('Fern Pro monthly',
               'Books, videos, articles and text from photos without limits, '
               'plus Anki deck import. Billed monthly, cancel any day.'),
    },
    {
        'productId': 'fern_pro_year',
        'basePlanId': 'yearly',
        'period': 'P1Y',
        'usd': ('34', 990000000),
        'rub': ('1990', 0),
        'ru': ('Fern Pro на год',
               'То же, что в месячной подписке, но выгоднее почти вдвое. '
               'Списание раз в год.'),
        'en': ('Fern Pro yearly',
               'Everything in the monthly plan at nearly half the price. '
               'Billed once a year.'),
    },
]

# Льгота и удержание: у человека, у которого не списалась оплата, есть неделя
# на замену карты. Те же семь дней носит офлайн-талон подписки.
ЛЬГОТА = 'P7D'
УДЕРЖАНИЕ = 'P30D'

# Версия справочника стран Google. Без неё запрос отвечает «Regions Version
# must be specified», а параметр зовётся с точкой и обычным kwarg не задаётся.
# Значение берём из ответа конвертации: на устаревшей версии Google требует
# у Болгарии левы, хотя сам же присылает евро.
ВЕРСИЯ_РЕГИОНОВ = '2022/02'


def версия_регионов() -> str:
    global ВЕРСИЯ_РЕГИОНОВ
    ответ = p.call('POST', f'/applications/{p.ПАКЕТ}/pricing:convertRegionPrices',
                   {'price': {'currencyCode': 'USD', 'units': '5'}})
    версия = (ответ.get('regionVersion') or {}).get('version')
    if версия:
        ВЕРСИЯ_РЕГИОНОВ = версия
    return ВЕРСИЯ_РЕГИОНОВ


def цены(usd: tuple[str, int], rub: tuple[str, int]) -> tuple[list[dict], dict]:
    """Региональные цены: мир — конвертацией Google, Россия — своей ценой."""
    ответ = p.call('POST', f'/applications/{p.ПАКЕТ}/pricing:convertRegionPrices',
                   {'price': {'currencyCode': 'USD',
                              'units': usd[0], 'nanos': usd[1]}})
    регионы = ответ.get('convertedRegionPrices', {})
    конфиги = []
    for код, значение in регионы.items():
        цена = значение.get('price') or {}
        if код == 'RU':
            цена = {'currencyCode': 'RUB', 'units': rub[0], 'nanos': rub[1]}
        конфиги.append({'regionCode': код, 'price': цена,
                        'newSubscriberAvailability': True})
    if 'RU' not in регионы:
        конфиги.append({
            'regionCode': 'RU',
            'price': {'currencyCode': 'RUB', 'units': rub[0], 'nanos': rub[1]},
            'newSubscriberAvailability': True})
    прочие = ответ.get('convertedOtherRegionsPrice') or {}
    остальные = {}
    if прочие.get('usdPrice') and прочие.get('eurPrice'):
        остальные = {'usdPrice': прочие['usdPrice'], 'eurPrice': прочие['eurPrice'],
                     'newSubscriberAvailability': True}
    return конфиги, остальные


def тело_товара(тариф: dict) -> dict:
    конфиги, остальные = цены(тариф['usd'], тариф['rub'])
    базовый = {
        'basePlanId': тариф['basePlanId'],
        'state': 'DRAFT',
        'autoRenewingBasePlanType': {
            'billingPeriodDuration': тариф['period'],
            'gracePeriodDuration': ЛЬГОТА,
            'accountHoldDuration': УДЕРЖАНИЕ,
            'resubscribeState': 'RESUBSCRIBE_STATE_ACTIVE',
            'prorationMode':
                'SUBSCRIPTION_PRORATION_MODE_CHARGE_ON_NEXT_BILLING_DATE',
            'legacyCompatible': False,
        },
        'regionalConfigs': конфиги,
    }
    if остальные:
        базовый['otherRegionsConfig'] = остальные
    return {
        'packageName': p.ПАКЕТ,
        'productId': тариф['productId'],
        'listings': [
            {'languageCode': 'ru-RU', 'title': тариф['ru'][0],
             'description': тариф['ru'][1]},
            {'languageCode': 'en-US', 'title': тариф['en'][0],
             'description': тариф['en'][1]},
        ],
        'basePlans': [базовый],
        'taxAndComplianceSettings': {
            'isTokenizedDigitalAsset': False,
        },
    }


def список() -> dict:
    ответ = p.call('GET', f'/applications/{p.ПАКЕТ}/subscriptions', pageSize=50)
    return {s['productId']: s for s in ответ.get('subscriptions', [])}


def state() -> None:
    товары = список()
    if not товары:
        print('подписок нет')
        return
    for имя, s in товары.items():
        for b in s.get('basePlans', []):
            регионы = b.get('regionalConfigs') or []
            ru = [r for r in регионы if r.get('regionCode') == 'RU']
            цена_ru = ru[0]['price'] if ru else {}
            print(f'{имя}: план {b.get("basePlanId")} '
                  f'({b.get("autoRenewingBasePlanType", {}).get("billingPeriodDuration")}), '
                  f'состояние {b.get("state")}, регионов {len(регионы)}, '
                  f'Россия {цена_ru.get("units", "—")} {цена_ru.get("currencyCode", "")}')


def setup() -> None:
    print('   справочник стран:', версия_регионов())
    готовые = список()
    for тариф in ТАРИФЫ:
        имя = тариф['productId']
        тело = тело_товара(тариф)
        if имя in готовые:
            print(f'   {имя}: уже есть, обновляю цены и тексты')
            p.call('PATCH', f'/applications/{p.ПАКЕТ}/subscriptions/{имя}', тело,
                   params={'updateMask':
                           'listings,basePlans,taxAndComplianceSettings',
                           'regionsVersion.version': ВЕРСИЯ_РЕГИОНОВ})
        else:
            p.call('POST', f'/applications/{p.ПАКЕТ}/subscriptions', тело,
                   params={'productId': имя,
                           'regionsVersion.version': ВЕРСИЯ_РЕГИОНОВ})
            print(f'   {имя}: заведён, регионов '
                  f'{len(тело["basePlans"][0]["regionalConfigs"])}')

        # Черновик не продаётся: базовый план надо включить отдельно.
        план = тариф['basePlanId']
        try:
            p.call('POST', f'/applications/{p.ПАКЕТ}/subscriptions/{имя}'
                           f'/basePlans/{план}:activate', {})
            print(f'      план {план} включён')
        except SystemExit as e:
            print(f'      план {план}: {str(e).splitlines()[0]}')
    print('готово')


if __name__ == '__main__':
    команда = sys.argv[1] if len(sys.argv) > 1 else 'state'
    {'state': state, 'setup': setup}.get(команда, state)()
