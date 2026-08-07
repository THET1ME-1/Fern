#!/usr/bin/env python3
"""Собирает три направления промо-изображения Fern Pro (1024×1024).

Токены настоящие: цвета из темы приложения (seed #2E7D5B, фон иконки
#242925), шрифты — те же файлы, что подшиты в приложение. Оба шрифта
вариативные, поэтому в @font-face указан диапазон весов: без него браузер
рисует синтетический жирный и характер Unbounded пропадает.
"""
import base64
import pathlib
import re

HERE = pathlib.Path(__file__).parent
MARK = (HERE / 'mark.svg').read_text()


def mark(leaf: str, cut: str) -> str:
    """Знак приложения. Тёмные куски — вырезы плашки, их красим под фон."""
    svg = MARK.replace('#35A46F', leaf).replace('#242925', cut)
    return re.sub(r'width="\d+" height="\d+"', 'width="100%" height="100%"', svg)


def font(name: str) -> str:
    data = base64.b64encode((HERE / f'{name}.ttf').read_bytes()).decode()
    return (f"@font-face{{font-family:'{name}';"
            f"src:url(data:font/ttf;base64,{data}) format('truetype-variations');"
            f"font-weight:200 900;font-style:normal;}}")


def image(name: str) -> str:
    data = base64.b64encode((HERE / name).read_bytes()).decode()
    return f'data:image/png;base64,{data}'


BASE = """
* { margin:0; padding:0; box-sizing:border-box; }
html,body { width:1024px; height:1024px; overflow:hidden; background:#242925; }
body { font-family:'Onest',sans-serif; -webkit-font-smoothing:antialiased; }
.canvas { width:1024px; height:1024px; position:relative; overflow:hidden; }
"""

DARK = '#242925'
LEAF = '#35A46F'
DEEP = '#2E7D5B'
MINT = '#8BE0B6'
PAPER = '#F2F5F0'
MUTED = '#9FB0A5'


def page(style: str, body: str) -> str:
    return (f"<!doctype html><html><head><meta charset='utf-8'><style>"
            f"{font('Unbounded')}{font('Onest')}{BASE}{style}"
            f"</style></head><body>{body}</body></html>")


# ── A. Знак ───────────────────────────────────────────────────────────────
# Продолжение иконки: та же плашка, тот же папоротник из угла. В списке
# покупок товар узнаётся раньше, чем прочитано название.
a = page(f"""
.canvas {{ background:{DARK} url('{image('icon.png')}') center/1024px 1024px no-repeat; }}
.words {{ position:absolute; left:88px; top:250px; }}
.name {{ font-family:'Unbounded'; font-weight:700; font-size:96px; line-height:1.06;
        color:{PAPER}; letter-spacing:-3px; }}
.pro {{ color:{MINT}; }}
.sub {{ margin-top:34px; font-size:33px; line-height:1.4; color:{MUTED}; max-width:380px; }}
""", f"""
<div class="canvas">
  <div class="words">
    <div class="name">Fern<br><span class="pro">Pro</span></div>
    <div class="sub">Слова из своих книг, видео и статей</div>
  </div>
</div>
""")

# ── B. Что открывает покупка ─────────────────────────────────────────────
# Три источника и карточка под ними: покупка объясняется картинкой, а не
# обещанием. Светлый вариант — в тёмной ленте покупок он заметнее.
b = page(f"""
.canvas {{ background:{PAPER}; padding:82px; display:flex;
          flex-direction:column; justify-content:center; }}
.title {{ font-family:'Unbounded'; font-weight:700; font-size:64px; color:{DARK};
         letter-spacing:-2px; }}
.lead {{ margin-top:14px; font-size:31px; color:#5C6B60; }}
.row {{ margin-top:70px; display:flex; gap:24px; }}
.tile {{ flex:1; height:200px; border-radius:44px; background:#DDE8E0;
        display:flex; flex-direction:column; align-items:center; justify-content:center;
        gap:16px; color:{DEEP}; }}
.tile svg {{ width:66px; height:66px; }}
.tile span {{ font-size:25px; font-weight:600; }}
.arrow {{ margin:34px auto 0; width:6px; height:56px; background:#C3D3C7; border-radius:3px; }}
.card {{ margin-top:34px; padding:44px 48px; border-radius:52px; background:{DARK}; }}
.word {{ font-family:'Unbounded'; font-weight:700; font-size:58px; color:{PAPER};
        letter-spacing:-2px; }}
.mean {{ margin-top:12px; font-size:34px; color:{MINT}; }}
""", f"""
<div class="canvas">
  <div class="title">Fern Pro</div>
  <div class="lead">Ваш материал становится словарём</div>
  <div class="row">
    <div class="tile">
      <svg viewBox="0 0 24 24" fill="none" stroke="{DEEP}" stroke-width="1.6"><path d="M4 4h7a2 2 0 0 1 2 2v14a2 2 0 0 0-2-2H4z"/><path d="M20 4h-7a2 2 0 0 0-2 2v14a2 2 0 0 1 2-2h7z"/></svg>
      <span>Книги</span>
    </div>
    <div class="tile">
      <svg viewBox="0 0 24 24" fill="none" stroke="{DEEP}" stroke-width="1.6"><rect x="3" y="5" width="18" height="14" rx="3"/><path d="M10 9.5v5l4.5-2.5z" fill="{DEEP}" stroke="none"/></svg>
      <span>Видео</span>
    </div>
    <div class="tile">
      <svg viewBox="0 0 24 24" fill="none" stroke="{DEEP}" stroke-width="1.6"><rect x="3" y="6" width="18" height="14" rx="3"/><circle cx="12" cy="13" r="4"/><path d="M8 6l1.6-2h4.8L16 6"/></svg>
      <span>Снимки</span>
    </div>
  </div>
  <div class="arrow"></div>
  <div class="card">
    <div class="word">interregnum</div>
    <div class="mean">междуцарствие</div>
  </div>
</div>
""")

# ── C. Типографика ────────────────────────────────────────────────────────
# Имя набрано во всю ширину, папоротник растёт за ним. Самый громкий из
# трёх: читается даже в мелком превью.
c = page(f"""
.canvas {{ background:{DARK}; }}
.leaf {{ position:absolute; right:-170px; bottom:-190px; width:820px; height:820px; }}
.stack {{ position:absolute; left:78px; top:150px; }}
.fern {{ font-family:'Unbounded'; font-weight:600; font-size:88px; color:{PAPER};
        letter-spacing:-3px; line-height:1; }}
.pro {{ font-family:'Unbounded'; font-weight:700; font-size:200px; color:{MINT};
       letter-spacing:-10px; line-height:0.92; }}
.foot {{ position:absolute; left:82px; top:520px; max-width:420px; line-height:1.4; font-size:30px; color:{MUTED}; }}
""", f"""
<div class="canvas">
  <div class="leaf">{mark(DEEP, DARK)}</div>
  <div class="stack">
    <div class="fern">Fern</div>
    <div class="pro">PRO</div>
  </div>
  <div class="foot">Книги, видео, статьи и снимки — в карточки</div>
</div>
""")

for slug, html in (('A', a), ('B', b), ('C', c)):
    (HERE / f'promo-{slug}.html').write_text(html, encoding='utf-8')
    print('готов', slug)
