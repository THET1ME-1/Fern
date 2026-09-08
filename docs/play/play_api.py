#!/usr/bin/env python3
"""Доступ к Android Publisher API приложением Fern.

Ключ СВОЙ: `~/keys/fern-play-service-account.json`
(`fern-releases@fern-releases.iam.gserviceaccount.com`). Ключ Togetherly сюда
не годится — у него прав на Fern нет, и на этом легко ошибиться в диагнозе.
"""
from __future__ import annotations

import json
import os
import pathlib
import time
import urllib.error
import urllib.parse
import urllib.request

import jwt

ПАКЕТ = os.environ.get('PLAY_PACKAGE', 'com.fern.app')
КЛЮЧ = pathlib.Path(os.environ.get(
    'PLAY_KEY', pathlib.Path.home() / 'keys' / 'fern-play-service-account.json'))
БАЗА = 'https://androidpublisher.googleapis.com/androidpublisher/v3'


def токен() -> str:
    ключ = json.loads(КЛЮЧ.read_text())
    now = int(time.time())
    assertion = jwt.encode({
        'iss': ключ['client_email'],
        'scope': 'https://www.googleapis.com/auth/androidpublisher',
        'aud': 'https://oauth2.googleapis.com/token',
        'iat': now, 'exp': now + 3600,
    }, ключ['private_key'], algorithm='RS256')
    тело = urllib.parse.urlencode({
        'grant_type': 'urn:ietf:params:oauth:grant-type:jwt-bearer',
        'assertion': assertion}).encode()
    with urllib.request.urlopen(urllib.request.Request(
            'https://oauth2.googleapis.com/token', data=тело), timeout=30) as r:
        return json.loads(r.read())['access_token']


_кэш: dict[str, str] = {}


def call(метод: str, путь: str, тело=None, params: dict | None = None,
         **kwargs) -> dict:
    """Запрос к API. Пустой ответ — это пустой ответ, а не поломка: Google
    отдаёт голое тело на списках, где ничего нет."""
    if 'token' not in _кэш:
        _кэш['token'] = токен()
    url = БАЗА + путь
    # Часть параметров Google называет с точкой («regionsVersion.version»),
    # и kwarg такое имя не примет — их передают словарём.
    все = {**(params or {}), **kwargs}
    if все:
        url += ('&' if '?' in url else '?') + urllib.parse.urlencode(все)
    данные = json.dumps(тело, ensure_ascii=False).encode() if тело is not None else None
    req = urllib.request.Request(url, data=данные, method=метод)
    req.add_header('Authorization', 'Bearer ' + _кэш['token'])
    req.add_header('Content-Type', 'application/json')
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            сырое = r.read()
    except urllib.error.HTTPError as e:
        текст = e.read().decode(errors='replace')
        raise SystemExit(f'{метод} {путь} → {e.code}\n{текст[:600]}')
    if not сырое.strip():
        return {}
    return json.loads(сырое)
