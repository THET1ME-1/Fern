#!/usr/bin/env python3
"""Меняет строку состояния Android на строку состояния iOS в скриншотах App Store.

Снимки сделаны на Android-телефоне и вставлены в наклонённую рамку. Apple
отклоняет такую карточку по правилу 2.3.10: чужая строка состояния читается как
упоминание посторонней платформы (отказ по Fern, август 2026).

Строка не рисуется заново: время, антенна, LTE и батарея вырезаны с настоящего
снимка iPhone и лежат в `ios-status/` картинками с альфой. Скрипт находит рамку,
распрямляет её по углу наклона, заливает полосу состояния фоном экрана и кладёт
поверх эти элементы, перекрашенные в цвет текста приложения.

Выреза — «острова» или чёлки — здесь нет намеренно: система их в снимок не
пишет, на настоящем скриншоте iPhone видна только пустая полоса.

Рисованный слой собирается в распрямлённых координатах, потом поворачивается
обратно и накладывается по маске. Сам снимок не пересэмплируется: наклон и
резкость исходника остаются нетронутыми.

    python3 ios_statusbar.py screens-en/*.png screens-ru/*.png

Файлы правятся на месте, оригиналы складываются рядом в `_android/`.

Скрипт — история: второй отказ 2.3.10 (26.08.2026) показал, что подмены строки
состояния мало, читается устройство целиком. Постеры собирает `shots-build.py`
из настоящих снимков iPhone, к ним этот скрипт не применяется.
"""
from __future__ import annotations

import math
import pathlib
import shutil
import sys

import numpy as np
from PIL import Image, ImageDraw

HERE = pathlib.Path(__file__).parent
PARTS = HERE / 'ios-status'

BAND = 78            # высота заливаемой полосы в пикселях снимка
SHOT_W = 922         # ширина снимка iPhone, из которого вырезаны элементы
INK = (26, 28, 25)   # цвет цифр и значков — тот же, что у текста приложения
LEVEL = 0.8          # сколько закрасить в батарее: на исходнике был режим сбережения

# что и куда класть — координаты на том же снимке iPhone
LAYOUT = (('time', 104, 45), ('signal', 650, 45), ('lte', 714, 45), ('battery', 779, 45))


# ── геометрия рамки ───────────────────────────────────────────────────────

def tilt(im: Image.Image) -> float:
    """Угол наклона рамки в градусах по её верхней кромке."""
    dark = np.asarray(im.convert('RGB')).astype(int).sum(axis=2) < 200
    h, w = dark.shape
    xs, tops = [], []
    for x in range(int(w * 0.55), int(w * 0.9), 10):
        col = np.nonzero(dark[int(h * 0.3):int(h * 0.5), x])[0]
        if len(col):
            xs.append(x)
            tops.append(col.min())
    if len(xs) < 5:
        raise SystemExit('верхняя кромка рамки не найдена')
    return math.degrees(math.atan(np.polyfit(xs, tops, 1)[0]))


def frame_box(rot: np.ndarray) -> tuple[int, int, int]:
    """Внутренние границы экрана в распрямлённой картинке: левая, правая, верх."""
    dark = rot.sum(axis=2) < 200
    h, w = dark.shape
    band = dark[int(h * 0.45):int(h * 0.85), int(w * 0.35):]
    cols = np.nonzero(band.sum(axis=0) > band.shape[0] * 0.9)[0] + int(w * 0.35)
    left, right = cols.min(), cols.max()
    mid = (left + right) // 2
    top = np.nonzero(dark[int(h * 0.3):int(h * 0.5), mid])[0].min() + int(h * 0.3)
    thick = 11
    return left + thick, right - thick, top + thick


def edge(dark_row: np.ndarray, frm: int, to: int) -> int | None:
    """Внутренний край рамки на отрезке. Идём от края картинки внутрь: светлый
    фон страницы, потом сплошная тёмная рамка, потом экран. Возвращаем первый
    пиксель экрана. Просто «крайний тёмный» здесь не годится — в отрезок
    попадают значки старой строки состояния, и граница уезжает на них."""
    step = 1 if to > frm else -1
    idx = range(frm, to, step)
    it = iter(idx)
    for i in it:
        if dark_row[i]:
            break
    else:
        return None
    last = i
    for i in it:
        if not dark_row[i]:
            return last + 2 * step
        last = i
    return None


def screen_rows(rot: np.ndarray, x0: int, x1: int, y0: int) -> list[tuple[int, int]]:
    """Границы экрана построчно — повторяют скругление верхних углов."""
    dark = rot.sum(axis=2) < 300
    rows = []
    for y in range(y0, y0 + BAND):
        a0 = edge(dark[y], x0 - 40, x0 + 70)
        a1 = edge(dark[y], x1 + 40, x1 - 70)
        rows.append((a0, a1) if a0 is not None and a1 is not None and a1 - a0 > 40 else (0, 0))
    return rows


# ── строка состояния ──────────────────────────────────────────────────────

def part(name: str) -> Image.Image:
    path = PARTS / f'{name}.png'
    if not path.exists():
        raise SystemExit(f'нет заготовки {path} — элементы строки лежат в ios-status/')
    return Image.open(path)


def fill_battery(big: Image.Image, piece: Image.Image, x: int, y: int) -> None:
    """Заряд внутри контура. На исходном снимке телефон сидел на режиме
    сбережения — жёлтый огрызок вырезан, вместо него обычная тёмная полоса."""
    alpha = np.asarray(piece)[:, :, 3] > 40
    ys, xs = np.nonzero(alpha)
    body = xs[xs < xs.max() - 6]          # без «носика» справа
    left, right = int(body.min()), int(body.max())
    top, bottom = int(ys.min()), int(ys.max())
    pad = 5
    ImageDraw.Draw(big).rounded_rectangle(
        [x + left + pad, y + top + pad,
         x + left + pad + (right - left - 2 * pad) * LEVEL, y + bottom - pad],
        radius=4, fill=INK)


def draw_bar(width: int, height: int, bg: tuple[int, int, int]) -> Image.Image:
    """Полоса состояния в ширину экрана, собранная из элементов снимка iPhone."""
    scale = SHOT_W / width
    big = Image.new('RGB', (SHOT_W, round(height * scale)), bg)
    ink = Image.new('RGB', big.size, INK)

    for name, x, y in LAYOUT:
        piece = part(name)
        big.paste(ink.crop((0, 0, piece.width, piece.height)), (x, y), piece)
        if name == 'battery':
            fill_battery(big, piece, x, y)

    return big.resize((width, height), Image.LANCZOS)


# ── сборка ────────────────────────────────────────────────────────────────

def convert(path: pathlib.Path) -> None:
    im = Image.open(path).convert('RGB')
    theta = tilt(im)
    centre = (im.width / 2, im.height / 2)
    rot = im.rotate(theta, resample=Image.BICUBIC, center=centre, fillcolor=(255, 255, 255))
    a = np.asarray(rot).astype(int)

    x0, x1, y0 = frame_box(a)
    bg = tuple(np.median(a[y0 + 58:y0 + 70, x0 + 50:x1 - 50].reshape(-1, 3), axis=0).astype(int))

    layer = Image.new('RGB', im.size, bg)
    layer.paste(draw_bar(x1 - x0, BAND, bg), (x0, y0))

    mask = Image.new('L', im.size, 0)
    md = ImageDraw.Draw(mask)
    for i, (a0, a1) in enumerate(screen_rows(a, x0, x1, y0)):
        if a1 > a0:
            md.line([(a0, y0 + i), (a1, y0 + i)], fill=255)

    back = dict(resample=Image.BICUBIC, center=centre)
    im.paste(layer.rotate(-theta, fillcolor=bg, **back),
             (0, 0), mask.rotate(-theta, fillcolor=0, **back))

    keep = path.parent / '_android' / path.name
    if not keep.exists():
        keep.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, keep)
    im.save(path)
    print('готов', path)


if __name__ == '__main__':
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    for arg in sys.argv[1:]:
        convert(pathlib.Path(arg))
