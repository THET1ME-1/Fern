#!/usr/bin/env python3
"""Собирает постеры App Store из настоящих снимков iPhone.

Снимки лежат в `shots-ios/<язык>/<слаг>.png` — это скриншоты с живого
устройства (1179×2556), они не правятся и не пересобираются: Apple отклонила
прошлый набор по правилу 2.3.10 именно за то, что снимки были сняты на другой
платформе и вставлены в чужую рамку.

Рамка рисуется здесь же, разметкой: корпус iPhone с титановым кантом,
скруглением экрана 55 pt и боковыми кнопками. Ничего от Android в постере
не остаётся — ни рамки, ни строки состояния, ни пропорций.

    python3 shots-build.py                 # все постеры, обе локализации
    python3 shots-build.py --only 02-home  # один слаг
    python3 shots-build.py --layout tilt   # другая компоновка

Компоновки: `side` — телефон справа, подписи слева (как в прежнем наборе),
`tilt` — то же с наклоном, `hero` — крупный телефон по центру.
Размеры: 6,5″ (1242×2688) — тот набор, что заливает `asc.py`, и 6,9″
(1290×2796) про запас.
"""
from __future__ import annotations

import argparse
import base64
import pathlib
import re
import subprocess
import tempfile

HERE = pathlib.Path(__file__).parent
APP = HERE.parent.parent / 'app'
FONTS = APP / 'assets' / 'fonts'
MARK = APP / 'assets' / 'icon' / 'mark.svg'
CHROME = pathlib.Path.home() / '.cache/ms-playwright/chromium-1234/chrome-linux64/chrome'

SIZES = {'65': (1242, 2688), '69': (1290, 2796)}

# ── токены темы приложения ────────────────────────────────────────────────
DEEP = '#2E7D5B'     # seed темы, им залит верхний блок
DARK = '#215F45'     # его же тень для градиента
PAPER = '#EFF4EE'    # нижний фон постера
INK = '#16241C'
MUTED = '#5C6F63'
LEAF = '#35A46F'


def b64(path: pathlib.Path) -> str:
    return base64.b64encode(path.read_bytes()).decode()


def font(name: str) -> str:
    return (f"@font-face{{font-family:'{name}';"
            f"src:url(data:font/ttf;base64,{b64(FONTS / f'{name}.ttf')}) format('truetype-variations');"
            f"font-weight:200 900;font-style:normal;}}")


def leaf(colour: str) -> str:
    """Знак приложения без плашки — идёт водяным знаком в верхний блок."""
    svg = MARK.read_text().replace('#35A46F', colour)
    svg = re.sub(r'width="\d+" height="\d+"', 'width="100%" height="100%"', svg)
    return svg.replace('#242925', 'none')


# ── тексты постеров ───────────────────────────────────────────────────────
# Заголовки и подписи те же, что в прежнем наборе: их уже видели в Play и в
# консоли Apple, менять их вместе с рамкой значит менять две вещи разом.
TEXT = {
    'en': {
        '02-home': ('Start with the 500 words that matter', 'Four ready decks, day one', [
            ('55 languages', 'Spanish, Japanese, Georgian'),
            ('500 words each', 'Chosen, not scraped'),
            ('Daily goal', 'Streak, freezes, reminders')]),
        '03-modes': ('Twelve ways to drill one word', 'Not one flashcard on repeat', [
            ('Dictation', 'Listen and spell it'),
            ('Phrase building', 'Words in the right order'),
            ('Audio only', 'Answer without looking')]),
        '04-book': ('See how much of a book you already know', 'Fern counts every running word', [
            ('Word analysis', 'Known, learning, new'),
            ('Cards while reading', 'Tap any word on the page'),
            ('EPUB, FB2, TXT', 'Your own library')]),
        '05-library': ('Turn a video or a book into a deck', 'Bring your own material', [
            ('From subtitles', 'Paste a video link'),
            ('From a web page', 'Article turns into reading'),
            ('From a photo', 'Scan a page of text')]),
        '06-cards': ('Your deck, word by word', 'Every card speaks', [
            ('Tap to hear it', 'Native pronunciation'),
            ('Sort and search', 'Find any card fast'),
            ('Add your own', 'Or import from Anki')]),
        '07-progress': ('Streak, accuracy, and your best hour', 'The scheduler learns your pace', [
            ('Weekly card', 'Share what you did'),
            ('Freezes', 'Miss a day, keep the streak'),
            ('Best hour', 'Reminded when you study')]),
        '08-settings': ('Your words stay on your phone', 'No account, no upload', [
            ('Eight palettes', 'Or pure AMOLED black'),
            ('Daily goal', 'And new words per day'),
            ('Seven languages', 'Interface, not just cards')]),
    },
    'ru': {
        '02-home': ('Начните с 500 слов, которые нужны', 'Четыре готовые колоды в первый день', [
            ('55 языков', 'Испанский, японский, грузинский'),
            ('По 500 слов', 'Отобраны, а не выкачаны'),
            ('Цель дня', 'Серия, щиты, напоминания')]),
        '03-modes': ('Двенадцать способов выучить слово', 'Не одна карточка по кругу', [
            ('Диктант', 'Слушай и пиши слово'),
            ('Собери фразу', 'Слова в правильном порядке'),
            ('Аудио', 'Отвечай, не глядя на экран')]),
        '04-book': ('Сколько слов книги вы уже знаете', 'Fern считает все слова с повторами', [
            ('Анализ слов', 'Помнит, учит, не знает'),
            ('Карточка со страницы', 'Коснитесь слова при чтении'),
            ('EPUB, FB2, TXT', 'Ваша собственная библиотека')]),
        '05-library': ('Видео, книга и снимок станут колодой', 'Учите на своём материале', [
            ('Из субтитров', 'Вставьте ссылку на видео'),
            ('Из статьи', 'Веб-страница станет чтением'),
            ('Со снимка', 'Сфотографируйте страницу')]),
        '06-cards': ('Ваша колода, слово за словом', 'Каждая карточка звучит', [
            ('Нажмите и услышите', 'Живое произношение'),
            ('Поиск и сортировка', 'Любая карточка за секунду'),
            ('Свои карточки', 'Или импорт из Anki')]),
        '07-progress': ('Серия, точность и лучший час', 'Планировщик подстраивается под вас', [
            ('Карточка недели', 'Есть чем поделиться'),
            ('Щиты', 'Пропустили день — серия цела'),
            ('Лучший час', 'Напомним в ваше время')]),
        '08-settings': ('Слова остаются на телефоне', 'Без аккаунта и без выгрузки', [
            ('Восемь палитр', 'Или чистый AMOLED-чёрный'),
            ('Цель дня', 'И сколько новых слов'),
            ('Семь языков', 'Интерфейс, а не только карточки')]),
    },
}

COVER = {
    'en': ('Learn the words your books actually use',
           ['55 languages, 500 words each', 'Works offline, no account', 'Free and open source']),
    'ru': ('Учи те слова, которые встретишь в книге',
           ['55 языков, по 500 слов', 'Работает без сети, без аккаунта', 'Бесплатно, исходники открыты']),
}

SLUGS = ['01-cover', '02-home', '03-modes', '04-book', '05-library', '06-cards',
         '07-progress', '08-settings']


# ── рамка iPhone ──────────────────────────────────────────────────────────
# Пропорции взяты с устройства, снимок которого лежит в shots-ios: экран
# 1179×2556 (6,1″), скругление 55 pt, титановый кант и боковые кнопки.
FRAME_CSS = """
.phone { position:absolute; }
.body { position:relative; border-radius:var(--rBody);
        background:linear-gradient(148deg,#E3DFD9 0%,#8E8A85 34%,#D4D0CA 52%,#7C7874 74%,#B9B5AF 100%);
        padding:var(--rim); box-shadow:0 46px 90px rgba(16,38,27,.20), 0 8px 22px rgba(16,38,27,.10); }
.bezel { border-radius:var(--rBezel); background:#070908; padding:var(--bez); }
.screen { border-radius:var(--rScreen); overflow:hidden; display:block; width:var(--sw); height:var(--sh); }
.screen img { width:100%; height:100%; display:block; }
.btn { position:absolute; background:linear-gradient(180deg,#CFCBC5,#8B8782); border-radius:3px; }
.btn.l { left:calc(var(--rim) * -0.55); }
.btn.r { right:calc(var(--rim) * -0.55); }
"""


def phone(shot: pathlib.Path, width: int, style: str = '') -> str:
    """Корпус с настоящим снимком внутри. width — ширина корпуса в пикселях."""
    rim = round(width * 0.013)          # титановый кант
    bez = round(width * 0.026)          # чёрная кромка вокруг экрана
    sw = width - 2 * (rim + bez)
    sh = round(sw * 2556 / 1179)
    r_screen = round(sw * 0.140)        # 55 pt при ширине экрана 393 pt
    css = (f"--rim:{rim}px;--bez:{bez}px;--sw:{sw}px;--sh:{sh}px;"
           f"--rScreen:{r_screen}px;--rBezel:{r_screen + bez}px;--rBody:{r_screen + bez + rim}px;")
    btn = lambda side, top, h: (f"<i class='btn {side}' style='top:{round(sh * top)}px;"
                                f"width:{max(3, round(width * 0.009))}px;height:{round(sh * h)}px'></i>")
    return f"""
    <div class="phone" style="{css}{style}">
      <div class="body">
        {btn('l', 0.118, 0.032)}{btn('l', 0.183, 0.062)}{btn('l', 0.262, 0.062)}{btn('r', 0.205, 0.098)}
        <div class="bezel"><div class="screen"><img src="data:image/png;base64,{b64(shot)}"></div></div>
      </div>
    </div>"""


def cover(lang: str, w: int, h: int) -> str:
    """Первый постер: знак, имя и три обещания. Телефона на нём нет."""
    sub, pills = COVER[lang]
    k = w / 1242

    def px(v: float) -> str:
        return f'{round(v * k)}px'

    items = ''.join(f"<div class='pill'>{p}</div>" for p in pills)
    return f"""<!doctype html><html><head><meta charset="utf-8"><style>
*{{margin:0;padding:0;box-sizing:border-box}}
html,body{{width:{w}px;height:{h}px;overflow:hidden;background:#14503A;
  font-family:'Onest',sans-serif;-webkit-font-smoothing:antialiased;text-align:center}}
{font('Unbounded')}{font('Onest')}
.icon{{position:absolute;left:50%;top:{px(470)};transform:translateX(-50%);
  width:{px(230)};height:{px(230)};border-radius:{px(56)};overflow:hidden}}
.icon img{{width:100%;height:100%;display:block}}
.name{{position:absolute;left:0;top:{px(860)};width:{w}px;font-family:'Unbounded';
  font-weight:700;font-size:{px(122)};letter-spacing:{px(-4)};color:#F4F8F3}}
.sub{{position:absolute;left:{px(160)};top:{px(1050)};width:{w - round(320 * k)}px;
  font-size:{px(46)};line-height:1.36;color:#A9D8BF;text-wrap:balance}}
.pills{{position:absolute;left:{px(160)};top:{px(1330)};width:{w - round(320 * k)}px;
  display:flex;flex-direction:column;gap:{px(28)}}}
.pill{{padding:{px(30)} {px(24)};border-radius:{px(56)};font-size:{px(38)};
  color:#DCEFE3;background:rgba(255,255,255,.055);border:2px solid rgba(255,255,255,.10)}}
#leafbig{{position:absolute;right:{px(-210)};bottom:{px(-260)};width:{px(880)};height:{px(880)};opacity:.06}}
</style></head><body>
<div id="leafbig">{leaf('#EAF6EE')}</div>
<div class="icon"><img src="data:image/png;base64,{b64(APP / 'assets' / 'icon' / 'icon.png')}"></div>
<div class="name">Fern</div>
<div class="sub">{sub}</div>
<div class="pills">{items}</div>
</body></html>"""


def page(lang: str, slug: str, w: int, h: int, layout: str) -> str:
    if slug == '01-cover':
        return cover(lang, w, h)
    title, sub, bullets = TEXT[lang][slug]
    shot = HERE / 'shots-ios' / lang / f'{slug}.png'
    k = w / 1242                        # всё разложено под 6,5″, остальное — масштабом

    def px(v: float) -> str:
        return f'{round(v * k)}px'

    band = 0.281 * h                    # высота зелёного блока
    items = ''.join(
        f"<li><b>{name}</b><span>{note}</span></li>" for name, note in bullets)

    if layout == 'hero':
        ph = phone(shot, round(770 * k), f'left:{px(236)};top:{px(1075)};')
        aside = f"<ul class='row'>{items}</ul>"
    else:
        tilt = 'transform:rotate(-5.5deg);' if layout == 'tilt' else ''
        ph = phone(shot, round(690 * k), f'left:{px(505)};top:{px(1000)};{tilt}')
        aside = f"<ul class='col'>{items}</ul>"

    return f"""<!doctype html><html><head><meta charset="utf-8"><style>
*{{margin:0;padding:0;box-sizing:border-box}}
html,body{{width:{w}px;height:{h}px;overflow:hidden;background:{PAPER};
  font-family:'Onest',sans-serif;-webkit-font-smoothing:antialiased}}
{font('Unbounded')}{font('Onest')}{FRAME_CSS}
.band{{position:absolute;left:0;top:0;width:{w}px;height:{round(band)}px;
  background:linear-gradient(160deg,{DEEP} 0%,{DARK} 100%);
  border-radius:0 0 {px(72)} {px(72)};overflow:hidden}}
.leaf{{position:absolute;right:{px(-150)};top:{px(-120)};width:{px(700)};height:{px(700)};opacity:.10}}
h1{{position:absolute;left:{px(92)};top:{px(215)};width:{px(1010)};
  font-family:'Unbounded';font-weight:700;font-size:{px(88)};line-height:1.10;
  letter-spacing:{px(-3)};color:#F4F8F3;text-wrap:balance}}
.sub{{position:absolute;left:{px(94)};top:{round(band) - round(150 * k)}px;
  font-size:{px(40)};color:rgba(240,248,242,.74)}}
ul{{position:absolute;list-style:none}}
ul.col{{left:{px(92)};top:{px(1046)};width:{px(372)}}}
ul.col li{{margin-bottom:{px(86)}}}
ul.row{{left:{px(92)};top:{round(band) + round(78 * k)}px;width:{w - round(184 * k)}px;
  display:flex;gap:{px(60)}}}
ul.row li{{flex:1}}
li{{position:relative;padding-left:{px(40)}}}
li::before{{content:'';position:absolute;left:0;top:{px(16)};width:{px(18)};height:{px(18)};
  border-radius:50%;background:{LEAF}}}
li b{{display:block;font-size:{px(42)};font-weight:700;color:{INK};line-height:1.22}}
li span{{display:block;margin-top:{px(10)};font-size:{px(32)};color:{MUTED};line-height:1.36}}
</style></head><body>
<div class="band"><div class="leaf">{leaf('#EAF6EE')}</div></div>
<h1>{title}</h1><div class="sub">{sub}</div>
{aside}{ph}
</body></html>"""


def render(html: str, out: pathlib.Path, w: int, h: int) -> None:
    with tempfile.TemporaryDirectory() as tmp:
        src = pathlib.Path(tmp) / 'p.html'
        src.write_text(html, encoding='utf-8')
        subprocess.run([str(CHROME), '--headless=new', '--no-sandbox', '--disable-gpu', '--hide-scrollbars',
                        '--force-device-scale-factor=1', f'--window-size={w},{h}',
                        f'--screenshot={out}', src.as_uri()],
                       check=True, capture_output=True)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument('--only', help='один слаг, например 02-home')
    ap.add_argument('--lang', choices=['en', 'ru'], help='одна локализация')
    ap.add_argument('--layout', default='side', choices=['side', 'tilt', 'hero'])
    ap.add_argument('--size', default='65', choices=list(SIZES))
    ap.add_argument('--out', default=None, help='куда класть (по умолчанию screens-<язык>)')
    a = ap.parse_args()

    w, h = SIZES[a.size]
    for lang in ([a.lang] if a.lang else ['en', 'ru']):
        out_dir = pathlib.Path(a.out) if a.out else HERE / f'screens-{lang}'
        out_dir.mkdir(parents=True, exist_ok=True)
        for slug in ([a.only] if a.only else SLUGS):
            out = out_dir / f'{slug}.png'
            render(page(lang, slug, w, h, a.layout), out, w, h)
            print('готов', lang, out.name)


if __name__ == '__main__':
    main()
