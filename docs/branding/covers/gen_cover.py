#!/usr/bin/env python3
"""Обложка товара Fern Pro для lava.top — 1160×464, на настоящих ассетах."""
from PIL import Image, ImageDraw, ImageFont
import os

APP = '/home/alelx/Projects/GitHub/Fern/app'
OUT = '/tmp/claude-1000/-home-alelx/36f209b5-d79c-41cc-b395-dbb4f2acdc8f/scratchpad/covers'
os.makedirs(OUT, exist_ok=True)

W, H = 1160, 464
DARK = (36, 41, 37)        # фон иконки #242925
GREEN = (46, 125, 91)      # фирменный seed #2E7D5B
LIGHT = (222, 233, 223)    # светлый текст темы
MINT = (139, 209, 176)     # акцент на тёмном

UNB = f'{APP}/assets/fonts/Unbounded.ttf'
ONEST = f'{APP}/assets/fonts/Onest.ttf'


def leaf(size, colour, alpha=255):
    """Лист папоротника из иконки: выбиваем тёмный фон по «зелёности»."""
    src = Image.open(f'{APP}/assets/icon/foreground.png').convert('RGB')
    px = src.load()
    mask = Image.new('L', src.size, 0)
    mp = mask.load()
    for y in range(src.size[1]):
        for x in range(src.size[0]):
            r, g, b = px[x, y]
            # Лист заметно зеленее фона — этого хватает как признака.
            mp[x, y] = 255 if (g - r) > 18 and g > 60 else 0
    box = mask.getbbox()          # обрезаем по самому растению
    mask = mask.crop(box)
    # Держим пропорции листа: size задаёт ВЫСОТУ.
    w = max(1, round(mask.size[0] * size[1] / mask.size[1]))
    size = (w, size[1])
    mask = mask.resize(size, Image.LANCZOS)
    if alpha != 255:
        mask = mask.point(lambda v: int(v * alpha / 255))
    tint = Image.new('RGBA', size, colour + (0,))
    tint.putalpha(mask)
    return tint


def text(d, xy, s, font, fill, anchor='ls'):
    d.text(xy, s, font=font, fill=fill, anchor=anchor)


def variant_readme():
    """Как баннер README: тёмное поле, лист справа, текст слева."""
    img = Image.new('RGB', (W, H), DARK)
    lf = leaf((520, 520), GREEN)
    img.paste(lf, (W - lf.size[0] - 60, H - 470), lf)
    d = ImageDraw.Draw(img)
    text(d, (80, 230), 'Fern Pro', ImageFont.truetype(UNB, 88), LIGHT)
    text(d, (84, 296), 'Учитесь на своих книгах,', ImageFont.truetype(ONEST, 30), MINT)
    text(d, (84, 340), 'видео и статьях', ImageFont.truetype(ONEST, 30), MINT)
    text(d, (84, 404), 'Разовая покупка  ·  без подписки  ·  офлайн',
         ImageFont.truetype(ONEST, 20), (150, 168, 152))
    img.save(f'{OUT}/1-readme.png')


def variant_green():
    """Зелёное поле: цвет несёт всю площадь, лист — тональный водяной знак."""
    img = Image.new('RGB', (W, H), GREEN)
    lf = leaf((620, 620), (22, 84, 60), alpha=210)
    img.paste(lf, (W - lf.size[0] - 30, -90), lf)
    d = ImageDraw.Draw(img)
    text(d, (80, 222), 'Fern Pro', ImageFont.truetype(UNB, 92), (240, 250, 242))
    text(d, (84, 288), 'Учитесь на своих книгах,', ImageFont.truetype(ONEST, 31), (208, 236, 219))
    text(d, (84, 334), 'видео и статьях', ImageFont.truetype(ONEST, 31), (208, 236, 219))
    text(d, (84, 400), 'Разовая покупка  ·  без подписки  ·  офлайн',
         ImageFont.truetype(ONEST, 20), (198, 230, 210))
    img.save(f'{OUT}/2-green.png')


def variant_split():
    """Лист слева во весь рост, текст справа — композиция строится на контрасте."""
    img = Image.new('RGB', (W, H), DARK)
    lf = leaf((640, 640), GREEN)
    img.paste(lf, (-70, -120), lf)
    d = ImageDraw.Draw(img)
    text(d, (W - 80, 214), 'Fern Pro', ImageFont.truetype(UNB, 84), LIGHT, anchor='rs')
    text(d, (W - 82, 276), 'Учитесь на своих книгах,', ImageFont.truetype(ONEST, 29), MINT, anchor='rs')
    text(d, (W - 82, 318), 'видео и статьях', ImageFont.truetype(ONEST, 29), MINT, anchor='rs')
    text(d, (W - 82, 388), 'Разовая покупка  ·  без подписки  ·  офлайн',
         ImageFont.truetype(ONEST, 19), (150, 168, 152), anchor='rs')
    img.save(f'{OUT}/3-split.png')


variant_readme()
variant_green()
variant_split()
print('готово:', sorted(os.listdir(OUT)))
