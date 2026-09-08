#!/usr/bin/env python3
"""Работа с карточкой App Store через API: снимки, тексты, подача на проверку.

Ключ и идентификаторы берутся из окружения, значения по умолчанию — Fern:

    ASC_ISSUER, ASC_KEY_ID, ASC_KEY (путь к .p8), ASC_APP_ID, ASC_IAP_ID

Подкоманды:

    python3 asc.py state                     что сейчас с версией, покупкой и заявкой
    python3 asc.py new 1.25.0 41             завести версию в консоли и привязать сборку
    python3 asc.py shots [en-US|ru]          перезалить снимки из screens-en / screens-ru
    python3 asc.py texts                     залить описания и ключевые слова из репозитория
    python3 asc.py submit                    собрать заявку (версия + покупка) и отправить

Подача устроена так: создаётся `reviewSubmission`, в него кладутся позиции —
версия приложения (`appStoreVersion`) и ВЕРСИЯ покупки (`inAppPurchaseVersion`,
именно версия, не сама покупка), затем заявка помечается `submitted`.
"""
from __future__ import annotations

import hashlib
import os
import pathlib
import re
import sys
import time

import jwt
import requests

HERE = pathlib.Path(__file__).parent
ISSUER = os.environ.get('ASC_ISSUER', '2872ead5-19a2-4dcc-b2c0-88e7ed59d743')
KEY_ID = os.environ.get('ASC_KEY_ID', 'XU8YHQFQAX')
KEY = pathlib.Path(os.environ.get('ASC_KEY', pathlib.Path.home() / 'keys' / 'AuthKey_XU8YHQFQAX.p8'))
APP_ID = os.environ.get('ASC_APP_ID', '6798832919')
IAP_ID = os.environ.get('ASC_IAP_ID', '6799091617')
BASE = 'https://api.appstoreconnect.apple.com'

_token = {'value': None, 'exp': 0}


def token() -> str:
    now = int(time.time())
    if _token['value'] and _token['exp'] - now > 60:
        return _token['value']
    exp = now + 15 * 60
    t = jwt.encode({'iss': ISSUER, 'iat': now, 'exp': exp, 'aud': 'appstoreconnect-v1'},
                   KEY.read_text(), algorithm='ES256', headers={'kid': KEY_ID, 'typ': 'JWT'})
    _token.update(value=t, exp=exp)
    return t


def call(method: str, path: str, **kw) -> dict:
    url = path if path.startswith('http') else BASE + path
    headers = {'Authorization': f'Bearer {token()}'}
    headers.update(kw.pop('headers', {}))
    if 'json' in kw:
        headers['Content-Type'] = 'application/json'
    for attempt in range(4):          # сеть Apple рвёт соединение чаще, чем хотелось бы
        try:
            r = requests.request(method, url, headers=headers, timeout=120, **kw)
            break
        except requests.RequestException:
            if attempt == 3:
                raise
            time.sleep(3 * (attempt + 1))
    if r.status_code >= 400:
        raise SystemExit(f'{method} {url} → {r.status_code}\n{r.text[:2000]}')
    return r.json() if r.content and 'json' in r.headers.get('content-type', '') else {}


def get(path: str, **params) -> dict:
    return call('GET', path, params=params)


# ── что где лежит ─────────────────────────────────────────────────────────

def version() -> dict:
    vs = get(f'/v1/apps/{APP_ID}/appStoreVersions', **{'limit': '1'})['data']
    if not vs:
        raise SystemExit('в консоли нет ни одной версии')
    return vs[0]


def create_version(version_string: str) -> str:
    """Новая версия в карточке. Тексты, снимки и возрастной рейтинг Apple
    копирует с предыдущей — руками остаётся только «Что нового» и сборка."""
    v = call('POST', '/v1/appStoreVersions', json={'data': {
        'type': 'appStoreVersions',
        'attributes': {'platform': 'IOS', 'versionString': version_string},
        'relationships': {'app': {'data': {'type': 'apps', 'id': APP_ID}}}}})['data']
    print('   версия заведена:', version_string, v['id'])
    return v['id']


def attach_build(version_id: str, build_version: str) -> None:
    """Сборка ищется по номеру среди обработанных. Номер iOS живёт отдельно от
    versionCode Android: его задаёт job в CI как «последний в TestFlight + 1»."""
    builds = get('/v1/builds', **{'filter[app]': APP_ID, 'limit': '50'})['data']
    found = [b for b in builds if b['attributes']['version'] == build_version]
    if not found:
        have = [b['attributes']['version'] for b in builds[:10]]
        raise SystemExit(f'сборки {build_version} нет в списке, есть: {have}')
    b = found[0]
    processing = b['attributes'].get('processingState')
    if processing != 'VALID':
        raise SystemExit(f'сборка {build_version} ещё в обработке: {processing}')
    call('PATCH', f'/v1/appStoreVersions/{version_id}/relationships/build',
         json={'data': {'type': 'builds', 'id': b['id']}})
    print('   сборка привязана:', build_version)


def localizations(version_id: str) -> dict:
    return {l['attributes']['locale']: l
            for l in get(f'/v1/appStoreVersions/{version_id}/appStoreVersionLocalizations')['data']}


def screenshot_set(loc_id: str) -> str:
    sets = get(f'/v1/appStoreVersionLocalizations/{loc_id}/appScreenshotSets', **{'limit': '20'})['data']
    for s in sets:
        if s['attributes']['screenshotDisplayType'] == 'APP_IPHONE_65':
            return s['id']
    raise SystemExit(f'нет набора APP_IPHONE_65 у локализации {loc_id}')


# ── снимки ────────────────────────────────────────────────────────────────

def upload_shots(locale: str, loc_id: str, folder: str) -> None:
    """Старые снимки удаляются: в набор влезает десять, а нас восемь плюс восемь."""
    set_id = screenshot_set(loc_id)
    for old in get(f'/v1/appScreenshotSets/{set_id}/appScreenshots', **{'limit': '20'})['data']:
        call('DELETE', f"/v1/appScreenshots/{old['id']}")
    ids = []
    for path in sorted((HERE / folder).glob('0*.png')):
        blob = path.read_bytes()
        shot = call('POST', '/v1/appScreenshots', json={'data': {
            'type': 'appScreenshots',
            'attributes': {'fileName': path.name, 'fileSize': len(blob)},
            'relationships': {'appScreenshotSet': {'data': {'type': 'appScreenshotSets', 'id': set_id}}},
        }})['data']
        for op in shot['attributes']['uploadOperations']:
            chunk = blob[op['offset']:op['offset'] + op['length']]
            head = {h['name']: h['value'] for h in op['requestHeaders']}
            r = requests.request(op['method'], op['url'], data=chunk, headers=head, timeout=180)
            if r.status_code >= 400:
                raise SystemExit(f'кусок не залился: {r.status_code} {r.text[:300]}')
        call('PATCH', f"/v1/appScreenshots/{shot['id']}", json={'data': {
            'type': 'appScreenshots', 'id': shot['id'],
            'attributes': {'uploaded': True, 'sourceFileChecksum': hashlib.md5(blob).hexdigest()}}})
        ids.append(shot['id'])
        print('   залит', path.name)
    call('PATCH', f'/v1/appScreenshotSets/{set_id}/relationships/appScreenshots',
         json={'data': [{'type': 'appScreenshots', 'id': i} for i in ids]})
    for _ in range(30):
        states = [(get(f'/v1/appScreenshots/{i}')['data']['attributes'].get('assetDeliveryState') or {}).get('state')
                  for i in ids]
        if all(s == 'COMPLETE' for s in states):
            print(f'   {locale}: все снимки приняты')
            return
        time.sleep(6)
    raise SystemExit(f'{locale}: снимки не дошли до COMPLETE — {states}')


# ── тексты ────────────────────────────────────────────────────────────────

def wanted_texts() -> dict:
    """Описание — из файлов, ключевые слова и промо — из блоков metadata.md."""
    meta = (HERE / 'metadata.md').read_text()

    def block(after: str, n: int) -> str:
        return re.findall(r'```\n(.*?)\n```', meta[meta.index(after):], re.S)[n - 1].strip()

    texts = {
        'ru': {'description': (HERE / 'description-ru.txt').read_text().strip(),
               'keywords': block('## Русская локализация', 3),
               'promotionalText': block('## Русская локализация', 4)},
        'en-US': {'description': (HERE / 'description-en.txt').read_text().strip(),
                  'keywords': block('## Английская локализация', 3),
                  'promotionalText': block('## Английская локализация', 4)},
    }
    # «Что нового» есть только у обновления: у первой версии поле не принимается.
    for locale, name in (('ru', 'whatsnew-ru.txt'), ('en-US', 'whatsnew-en.txt')):
        f = HERE / name
        if f.exists():
            texts[locale]['whatsNew'] = f.read_text().strip()
    return texts


def push_texts(version_id: str) -> None:
    locs = localizations(version_id)
    for locale, attrs in wanted_texts().items():
        call('PATCH', f"/v1/appStoreVersionLocalizations/{locs[locale]['id']}",
             json={'data': {'type': 'appStoreVersionLocalizations', 'id': locs[locale]['id'],
                            'attributes': attrs}})
        print('   тексты залиты:', locale)
    bad = re.compile(r'android|google|material you|rustore', re.I)
    for locale, l in localizations(version_id).items():
        a = l['attributes']
        found = bad.findall(f"{a['description']} {a['keywords']} {a['promotionalText']}")
        print(f'   {locale}: упоминания чужих платформ —', found or 'нет')


# ── подача ────────────────────────────────────────────────────────────────

def submit(version_id: str) -> None:
    for s in get('/v1/reviewSubmissions', **{'filter[app]': APP_ID, 'limit': '10'})['data']:
        if s['attributes']['state'] in ('UNRESOLVED_ISSUES', 'READY_FOR_REVIEW') and s['attributes']['submittedDate']:
            call('PATCH', f"/v1/reviewSubmissions/{s['id']}",
                 json={'data': {'type': 'reviewSubmissions', 'id': s['id'], 'attributes': {'canceled': True}}})
            print('   старая заявка отменена:', s['id'])
            while get(f"/v1/reviewSubmissions/{s['id']}")['data']['attributes']['state'] == 'CANCELING':
                time.sleep(10)

    sub = call('POST', '/v1/reviewSubmissions', json={'data': {
        'type': 'reviewSubmissions', 'attributes': {'platform': 'IOS'},
        'relationships': {'app': {'data': {'type': 'apps', 'id': APP_ID}}}}})['data']['id']

    def item(rel: str, typ: str, ident: str) -> None:
        call('POST', '/v1/reviewSubmissionItems', json={'data': {
            'type': 'reviewSubmissionItems', 'relationships': {
                'reviewSubmission': {'data': {'type': 'reviewSubmissions', 'id': sub}},
                rel: {'data': {'type': typ, 'id': ident}}}}})

    item('appStoreVersion', 'appStoreVersions', version_id)
    iap_versions = get(f'/v2/inAppPurchases/{IAP_ID}/versions')['data']
    # Одобренную покупку в заявку класть нельзя: у неё нет ожидающей версии, и
    # API отвечает отказом. Она уже продаётся и подачи не требует.
    pending = [v for v in iap_versions if v['attributes']['state'] != 'APPROVED']
    if pending:
        item('inAppPurchaseVersion', 'inAppPurchaseVersions', pending[0]['id'])
        print('   покупка добавлена в заявку')
    else:
        print('   покупка уже одобрена, в заявку не кладётся')
    call('PATCH', f'/v1/reviewSubmissions/{sub}', json={'data': {
        'type': 'reviewSubmissions', 'id': sub, 'attributes': {'submitted': True}}})
    print('   заявка отправлена:', sub)


def state() -> None:
    v = version()
    a = v['attributes']
    print('версия', a['versionString'], '|', a.get('appVersionState'))
    b = get(f"/v1/appStoreVersions/{v['id']}/build").get('data')
    print('сборка', b['attributes']['version'] if b else 'не привязана')
    print('покупка', get(f'/v2/inAppPurchases/{IAP_ID}')['data']['attributes']['state'],
          '| версии:', [x['attributes'] for x in get(f'/v2/inAppPurchases/{IAP_ID}/versions')['data']])
    for s in get('/v1/reviewSubmissions', **{'filter[app]': APP_ID, 'limit': '5'})['data']:
        print('заявка', s['id'], s['attributes']['state'], s['attributes'].get('submittedDate') or '')
    for locale, l in localizations(v['id']).items():
        shots = get(f"/v1/appScreenshotSets/{screenshot_set(l['id'])}/appScreenshots", **{'limit': '20'})['data']
        print(locale, '| снимков', len(shots), '|', [s['attributes']['fileName'] for s in shots])


if __name__ == '__main__':
    cmd = sys.argv[1] if len(sys.argv) > 1 else 'state'
    if cmd == 'new':
        if len(sys.argv) < 4:
            raise SystemExit('нужны версия и номер сборки: asc.py new 1.25.0 41')
        nv = create_version(sys.argv[2])
        attach_build(nv, sys.argv[3])
        sys.exit(0)
    v = version()['id']
    if cmd == 'state':
        state()
    elif cmd == 'shots':
        folders = {'en-US': 'screens-en', 'ru': 'screens-ru'}
        locs = localizations(v)
        for locale in (sys.argv[2:] or folders):
            upload_shots(locale, locs[locale]['id'], folders[locale])
    elif cmd == 'texts':
        push_texts(v)
    elif cmd == 'submit':
        submit(v)
    else:
        raise SystemExit(__doc__)
