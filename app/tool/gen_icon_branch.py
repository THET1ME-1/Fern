#!/usr/bin/env python3
"""Знак Fern: ветки с крупными листьями.

Форма взята из присланного референса — овальные листья на изогнутых стеблях,
чередующиеся по сторонам. Но плоско: ни обводки, ни теней, ни свечения, один
наш зелёный. Разделение листьев там, где они находят друг на друга, делается
зазором цвета фона — плоскими средствами, без контура.
"""
import json
import math
import os

GREEN = "#35A46F"
DEEP = "#227E55"
BG = "#242925"


def pt(x, y):
    return f"{x:.2f},{y:.2f}"


def bezier(p0, p1, p2, p3, t):
    u = 1 - t
    return (u ** 3 * p0[0] + 3 * u * u * t * p1[0] + 3 * u * t * t * p2[0]
            + t ** 3 * p3[0],
            u ** 3 * p0[1] + 3 * u * u * t * p1[1] + 3 * u * t * t * p2[1]
            + t ** 3 * p3[1])


def bezier_dir(p0, p1, p2, p3, t):
    u = 1 - t
    dx = (3 * u * u * (p1[0] - p0[0]) + 6 * u * t * (p2[0] - p1[0])
          + 3 * t * t * (p3[0] - p2[0]))
    dy = (3 * u * u * (p1[1] - p0[1]) + 6 * u * t * (p2[1] - p1[1])
          + 3 * t * t * (p3[1] - p2[1]))
    n = math.hypot(dx, dy) or 1
    return dx / n, dy / n


def leaf(cx, cy, length, width, angle_rad, grow=0.0):
    """Лист-миндалина: две дуги окружностей, сходящиеся остриями.

    Радиус выводится из длины и ширины, поэтому кончики всегда точные. [grow]
    раздувает форму — им же рисуется зазор под соседним листом.
    """
    half = length / 2 + grow
    w = width + grow * 2
    r = (half * half + (w / 2) ** 2) / w
    ca, sa = math.cos(angle_rad), math.sin(angle_rad)

    def rot(dx, dy):
        return cx + dx * ca - dy * sa, cy + dx * sa + dy * ca

    a, b = rot(0, -half), rot(0, half)
    return (f"M {pt(*a)} A {r:.2f},{r:.2f} 0 0,1 {pt(*b)} "
            f"A {r:.2f},{r:.2f} 0 0,1 {pt(*a)} Z")


def branch(p0, p1, p2, p3, count=7, leaf_len=27.0, leaf_w=11.5, spread=42.0,
           first=0.14, last=1.0, color=GREEN, gap=1.6, stem_w=3.0,
           alternate=True, shrink=0.35, tip_leaf=True):
    """Ветка: стебель-кривая и листья, чередующиеся по сторонам.

    Каждый лист сперва печатается зазором цвета фона, потом собой — так
    соседние листья разделяются без единой линии контура.
    """
    body, gaps = [], []

    # стебель
    left, right = [], []
    steps = 48
    for i in range(steps + 1):
        t = i / steps
        x, y = bezier(p0, p1, p2, p3, t)
        dx, dy = bezier_dir(p0, p1, p2, p3, t)
        w = stem_w * (1 - t * 0.55)
        left.append((x - dy * w / 2, y + dx * w / 2))
        right.append((x + dy * w / 2, y - dx * w / 2))
    d = "M " + pt(*left[0])
    for p in left[1:]:
        d += " L " + pt(*p)
    for p in reversed(right):
        d += " L " + pt(*p)
    body.append(f'<path d="{d} Z" fill="{color}"/>')

    for i in range(count):
        t = first + (last - first) * i / max(1, count - 1)
        x, y = bezier(p0, p1, p2, p3, t)
        dx, dy = bezier_dir(p0, p1, p2, p3, t)
        base = math.atan2(dy, dx)
        side = 1 if (i % 2 == 0 or not alternate) else -1
        ang = base + math.radians(spread) * side
        k = 1 - shrink * t
        length, width = leaf_len * k, leaf_w * k
        # лист сидит серединой чуть в стороне от стебля
        off = length / 2 * 0.86
        lx = x + math.cos(ang) * off
        ly = y + math.sin(ang) * off
        gaps.append(f'<path d="{leaf(lx, ly, length, width, ang + math.pi / 2, grow=gap)}" fill="{BG}"/>')
        body.append(f'<path d="{leaf(lx, ly, length, width, ang + math.pi / 2)}" fill="{color}"/>')

    if tip_leaf:
        x, y = bezier(p0, p1, p2, p3, 1.0)
        dx, dy = bezier_dir(p0, p1, p2, p3, 1.0)
        ang = math.atan2(dy, dx)
        k = 1 - shrink
        length, width = leaf_len * k * 0.95, leaf_w * k * 0.95
        lx = x + math.cos(ang) * length / 2 * 0.9
        ly = y + math.sin(ang) * length / 2 * 0.9
        gaps.append(f'<path d="{leaf(lx, ly, length, width, ang + math.pi / 2, grow=gap)}" fill="{BG}"/>')
        body.append(f'<path d="{leaf(lx, ly, length, width, ang + math.pi / 2)}" fill="{color}"/>')

    # зазоры печатаются под телом ветки: порядок и даёт плоское разделение
    out = []
    for i, piece in enumerate(body):
        if i < len(gaps):
            out.append(gaps[i])
        out.append(piece)
    return "\n".join(out)


def centered(body, dx=0.0, dy=0.0, scale=1.0):
    """Оптическая доводка: сдвиг и масштаб уже собранной композиции."""
    return (f'<g transform="translate({dx:.2f},{dy:.2f}) '
            f'scale({scale:.3f})" transform-origin="50 50">{body}</g>')


VARIANTS = {}

VARIANTS['sprig'] = {
    'name': 'Веточка',
    'idea': 'Четыре крупных листа вместо семи мелких. В иконке выигрывает тот '
            'знак, у которого меньше деталей: он читается и в списке '
            'приложений, и в уведомлении.',
    'svg': centered(branch((40, 84), (36, 62), (46, 40), (62, 26), count=4,
                           leaf_len=31, leaf_w=13.5, spread=46, shrink=0.22),
                    dx=-2, dy=1, scale=1.04),
}

VARIANTS['single'] = {
    'name': 'Ветка',
    'idea': 'Шесть листьев, чередующихся по сторонам, — форма из присланного '
            'примера. Ни контура, ни теней: там, где листья находят друг на '
            'друга, их разделяет зазор фона.',
    'svg': centered(branch((32, 88), (30, 62), (44, 34), (62, 18), count=6,
                           leaf_len=28, leaf_w=12, spread=44),
                    dx=1, dy=-2, scale=1.02),
}

VARIANTS['arc'] = {
    'name': 'Дуга',
    'idea': 'Ветка выгнута дугой: у знака появляется движение, и он перестаёт '
            'походить на гербарный лист под стеклом.',
    'svg': centered(branch((20, 72), (24, 34), (58, 16), (84, 36), count=7,
                           leaf_len=26, leaf_w=11, spread=52, shrink=0.28),
                    dy=2, scale=1.05),
}

VARIANTS['round'] = {
    'name': 'Ветка в круге',
    'idea': 'Ветка вырезана в плашке и вписана целиком, с полем по краю. Самый '
            'плотный силуэт: держится на любом фоне и не теряется при '
            'уменьшении.',
    'svg': (f'<circle cx="50" cy="50" r="35" fill="{GREEN}"/>\n'
            + centered(branch((41, 76), (36, 58), (46, 38), (60, 28), count=4,
                              leaf_len=24, leaf_w=10.4, spread=45, color=BG,
                              gap=0, stem_w=2.6, shrink=0.2),
                       dx=2, dy=3, scale=0.84)),
}

if __name__ == '__main__':
    path = os.path.join(os.path.dirname(__file__), 'branch.json')
    with open(path, 'w') as f:
        json.dump(VARIANTS, f, ensure_ascii=False, indent=1)
    print(f'вариантов: {len(VARIANTS)}')
