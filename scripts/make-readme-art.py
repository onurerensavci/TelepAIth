#!/usr/bin/env python3
"""README görsellerini üretir: assets/readme/*.svg (+ sosyal önizleme PNG).

Robot, RobotView.swift'teki FaceView/DotEyes çizimiyle birebir aynı ölçülerle çizilir
(100 × 100 nokta kafa, göz başına 14 × 18 LED noktası). Uygulamada bir şeyi değiştirirsen
burayı da güncelleyip `python3 scripts/make-readme-art.py` çalıştır.
"""
import math
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "readme")
FONT = "-apple-system, BlinkMacSystemFont, 'Segoe UI', Inter, 'Helvetica Neue', Arial, sans-serif"


def hex_rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def rgb_hex(c):
    return "#%02X%02X%02X" % tuple(max(0, min(255, round(v))) for v in c)


def mix(a, b, t):
    a, b = hex_rgb(a), hex_rgb(b)
    return rgb_hex(tuple(a[i] + (b[i] - a[i]) * t for i in range(3)))


CLAUDE = "#D97757"
GPT = "#3B82F6"
EYE = {"claude": mix(CLAUDE, "#FFFFFF", 0.18), "gpt": mix(GPT, "#FFFFFF", 0.18)}
ERROR_TINT = rgb_hex((255, 0.42 * 255, 0.42 * 255))
LED = {"ok": rgb_hex((0.2 * 255, 0.83 * 255, 0.47 * 255)),
       "update": rgb_hex((255, 0.6 * 255, 0.2 * 255)),
       "broken": rgb_hex((0.97 * 255, 0.3 * 255, 0.3 * 255))}

# ---------------------------------------------------------------- göz desenleri (DotEyes ile aynı)

def capsule(u, v, cx, cy, rx, ry):
    dx, dy = (u - cx) / rx, (v - cy) / ry
    d = dx * dx + dy * dy
    return 1 if d <= 1 else (0.35 if d <= 1.22 else 0)


def arc(u, v, cx, cy, radius):
    if v > cy:
        return 0
    d = math.hypot(u - cx, v - cy)
    return 1 if abs(d - radius) < 0.45 else 0


def cross(u, v):
    x, y = u - 3, v - 4
    if abs(x) > 2.6 or abs(y) > 2.6:
        return 0
    return 1 if (abs(x - y) < 0.4 or abs(x + y) < 0.4) else 0


def heart(u, v):
    x = (u - 3) / 2.6
    y = -(v - 4.3) / 2.6
    a = x * x + y * y - 1
    return 1 if a * a * a - x * x * y * y * y <= 0 else 0


def spiral(u, v, eye, t):
    x, y = u - 3, v - 4
    d = math.hypot(x, y)
    if abs(d - 2.4) >= 0.5:
        return 1 if d < 0.45 else 0
    phase = t * (6 if eye == 0 else -6)
    return 0.35 + 0.65 * max(0, math.cos(math.atan2(y, x) - phase))


def brightness(state, mood, u, v, eye, t=0.3, look=0.0):
    shift = look / 2.5
    if mood:
        return {
            "pleased": lambda: heart(u, v),
            "shocked": lambda: capsule(u, v, 3, 4, 2.9, 4.2),
            "nervous": lambda: capsule(u, v, 3 + math.sin(t * 14) * 1.1, 4.5, 1.2, 2),
            "party": lambda: arc(u, v, 3, 6.2, 2.7),
            "proud": lambda: arc(u, v, 3, 6.2, 2.7),
            "tired": lambda: capsule(u, v, 3, 5.2, 2.1, 1.1) * 0.8,
            "dizzy": lambda: spiral(u, v, eye, t),
            "denied": lambda: capsule(u, v, 3, 6, 1.7, 1.3),
        }[mood]()
    if state == "done":
        return arc(u, v, 3, 6.2, 2.7)
    if state == "error":
        return cross(u, v)
    if state == "sleeping":
        return 0.5 if (abs(v - 6) < 0.3 and abs(u - 3) <= 2.2) else 0
    if state == "thinking":
        return capsule(u, v, 3.9, 2.8, 1.5, 2.6)
    if state in ("reading", "searching"):
        return capsule(u, v, 3 + 0.9, 4.4, 1.5, 2.3)
    if state == "editing":
        return capsule(u, v, 3 + shift * 0.5, 5, 1.9, 1.5)
    if state in ("running", "delegating"):
        return capsule(u, v, 3, 4, 1.6, 2.8) * (0.75 + 0.25 * math.sin(1.2 + u * 2.6 + v * 1.4))
    if state == "waiting":
        return capsule(u, v, 3, 4, 2.5, 3.9)
    return capsule(u, v, 3 + shift, 4, 1.7, 3.3)  # idle


# ---------------------------------------------------------------- robot kafası

_uid = [0]


def uid(prefix):
    _uid[0] += 1
    return "%s%d" % (prefix, _uid[0])


def head(x, y, s, state="idle", mood=None, who="claude", health="ok", look=0.0, extras=True):
    """(x, y): kafanın 100 × 100 kutusunun sol üstü, s: ölçek."""
    tint = ERROR_TINT if (state == "error" and not mood) else EYE[who]
    g = uid("hg")
    parts = ['<g transform="translate(%.1f %.1f) scale(%.3f)">' % (x, y, s)]
    parts.append('<defs><linearGradient id="%s" x1="0" y1="0" x2="0" y2="1">'
                 '<stop offset="0" stop-color="#FAF7F2"/><stop offset="1" stop-color="#DBD6EB"/>'
                 '</linearGradient></defs>' % g)
    if extras and state == "thinking" and not mood:
        for r, o in ((60, 0.38), (70, 0.2)):
            parts.append('<circle cx="50" cy="50" r="%d" fill="none" stroke="%s" stroke-width="1.3" opacity="%.2f"/>'
                         % (r, tint, o))
    parts.append('<ellipse cx="50" cy="96" rx="30" ry="3.5" fill="#000" opacity="0.18"/>')
    parts.append('<circle cx="6" cy="50" r="6" fill="#BDB5D6"/><circle cx="94" cy="50" r="6" fill="#BDB5D6"/>')
    parts.append('<rect x="7" y="15" width="86" height="70" rx="24" fill="url(#%s)"/>' % g)
    parts.append('<rect x="15" y="30" width="70" height="44" rx="18" fill="#17142A"/>')
    cols, rows, sp, dot = 14, 18, 1.75, 1.3
    midc, midr = (cols - 1) / 2, (rows - 1) / 2
    dim, lit, glow = [], [], []
    for eye, cx in enumerate((50 - 14, 50 + 14)):
        for r in range(rows):
            for c in range(cols):
                px = cx + (c - midc) * sp
                py = 52 + (r - midr) * sp
                u = (c - midc) / 2 + 3
                v = (r - midr) / 2 + 4
                b = brightness(state, mood, u, v, eye, look=look)
                if b > 0.05:
                    glow.append('<circle cx="%.1f" cy="%.1f" r="1.45" opacity="%.2f"/>' % (px, py, 0.25 * b))
                    lit.append('<circle cx="%.1f" cy="%.1f" r="0.65"%s/>' % (px, py, "" if b >= 1 else ' opacity="%.2f"' % b))
    # Sönük noktalar her kafada aynı: bir kere tanımlanıp <use> ile kullanılır (dosya küçük kalsın)
    parts.append('<g fill="%s" opacity="0.09"><use href="#dimgrid"/></g>' % tint)
    parts.append('<g fill="%s">%s</g>' % (tint, "".join(glow)))
    parts.append('<g fill="%s">%s</g>' % (tint, "".join(lit)))
    led = LED[health]
    led_op = 0.45 if state == "sleeping" else 1
    parts.append('<circle cx="50" cy="22.5" r="5.5" fill="%s" opacity="%.2f"/>' % (led, 0.3 * led_op))
    parts.append('<circle cx="50" cy="22.5" r="2.5" fill="%s" opacity="%.2f"/>' % (led, led_op))
    if extras and state == "sleeping" and not mood:
        parts.append('<g font-family="%s" font-weight="700" fill="#C9C2E8">'
                     '<text x="82" y="16" font-size="9" opacity="0.8">z</text>'
                     '<text x="89" y="7" font-size="12" opacity="0.55">Z</text></g>' % FONT)
    if extras and (state == "done" or mood in ("party", "proud")):
        for sx, sy, sz in ((-4, 12, 5), (100, 20, 4), (96, -2, 3)):
            parts.append(sparkle(sx, sy, sz, "#FFE59A"))
    parts.append("</g>")
    return "".join(parts)


def sparkle(cx, cy, r, color, opacity=1):
    k = r * 0.28
    return ('<path d="M%.1f %.1f L%.1f %.1f L%.1f %.1f L%.1f %.1f L%.1f %.1f L%.1f %.1f L%.1f %.1f L%.1f %.1f Z" '
            'fill="%s" opacity="%.2f"/>' % (cx, cy - r, cx + k, cy - k, cx + r, cy, cx + k, cy + k,
                                             cx, cy + r, cx - k, cy + k, cx - r, cy, cx - k, cy - k, color, opacity))


def esc(t):
    return t.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def text_width(t, size):
    w = 0
    for ch in t:
        if ord(ch) > 0x2000:
            w += 1.25
        elif ch in "il.,:;'|!·":
            w += 0.3
        elif ch == " ":
            w += 0.3
        elif ch.isupper() or ch in "mwMW":
            w += 0.68
        else:
            w += 0.54
    return w * size


def bubble(x, y, w, title, color, text, subtitle=None, tail_x=None, scale=1.0, tail_down=True):
    """(x, y): balonun sol üstü. BubbleView'e benzer: başlık satırı + metin, kuyruk kafaya bakar."""
    h = 52
    tail_x = tail_x if tail_x is not None else w - 50
    f = uid("sh")
    parts = ['<g transform="translate(%.1f %.1f) scale(%.3f)">' % (x, y, scale)]
    parts.append('<defs><filter id="%s" x="-20%%" y="-30%%" width="140%%" height="170%%">'
                 '<feDropShadow dx="0" dy="3" stdDeviation="4" flood-color="#000" flood-opacity="0.28"/>'
                 '</filter></defs>' % f)
    parts.append('<g filter="url(#%s)">' % f)
    parts.append('<rect x="0" y="0" width="%.1f" height="%d" rx="12" fill="#FFFFFF" fill-opacity="0.97"/>' % (w, h))
    if tail_down:
        parts.append('<path d="M%.1f %d l9 10 l9 -10 z" fill="#FFFFFF" fill-opacity="0.97"/>' % (tail_x - 9, h - 0.5))
    else:
        parts.append('<path d="M%.1f 0.5 l9 -10 l9 10 z" fill="#FFFFFF" fill-opacity="0.97"/>' % (tail_x - 9))
    parts.append("</g>")
    parts.append('<circle cx="16" cy="17" r="4" fill="%s"/>' % color)
    parts.append('<text x="25" y="21" font-family="%s" font-size="12" font-weight="600" fill="%s">%s'
                 % (FONT, color, esc(title)))
    if subtitle:
        parts.append('<tspan fill="#8A8798" font-weight="400"> · %s</tspan>' % esc(subtitle))
    parts.append("</text>")
    parts.append('<text x="12" y="40" font-family="%s" font-size="14" fill="#1D1B26">%s</text>' % (FONT, esc(text)))
    parts.append("</g>")
    return "".join(parts)


def bg_defs(id_, w, h):
    return ('<linearGradient id="%s" x1="0" y1="0" x2="0.35" y2="1">'
            '<stop offset="0" stop-color="#33216D"/><stop offset="1" stop-color="#130B31"/></linearGradient>' % id_)


def stars(w, h, seed=7, n=26, avoid=()):
    import random
    rnd = random.Random(seed)
    out = []
    tries = 0
    while len(out) < n and tries < n * 40:
        tries += 1
        i = len(out)
        x, y = rnd.uniform(14, w - 14), rnd.uniform(14, h - 14)
        if any(ax - 14 <= x <= ax + aw + 14 and ay - 14 <= y <= ay + ah + 14 for ax, ay, aw, ah in avoid):
            continue
        if i % 5 == 0:
            out.append(sparkle(x, y, rnd.uniform(4, 7), "#FFF4D6", rnd.uniform(0.35, 0.7)))
        else:
            out.append('<circle cx="%.1f" cy="%.1f" r="%.1f" fill="#FFF4D6" opacity="%.2f"/>'
                       % (x, y, rnd.uniform(0.8, 2), rnd.uniform(0.2, 0.55)))
    return "".join(out)


def dim_grid():
    cols, rows, sp = 14, 18, 1.75
    midc, midr = (cols - 1) / 2, (rows - 1) / 2
    dots = ['<circle cx="%.1f" cy="%.1f" r="0.65"/>' % (cx + (c - midc) * sp, 52 + (r - midr) * sp)
            for cx in (36, 64) for r in range(rows) for c in range(cols)]
    return '<g id="dimgrid">%s</g>' % "".join(dots)


def svg(w, h, body, extra_defs=""):
    if 'href="#dimgrid"' in body:
        extra_defs += dim_grid()
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d">'
            '<defs>%s</defs>%s</svg>\n' % (w, h, w, h, extra_defs, body))


# ---------------------------------------------------------------- görseller

T = {
    "tr": {
        "tagline1": "Claude ve GPT o an ne yapıyorsa",
        "tagline2": "ekranının köşesindeki robot söylesin.",
        "chips": ["Claude Code", "Codex", "Claude & ChatGPT uygulamaları", "+ kendi AI'ın"],
        "bubble": ("Claude", "telepaith", "🔮 Düşünüyor… şu işi anlıyor"),
        "states": [("idle", None, "claude", "Boşta"), ("thinking", None, "claude", "🔮 Düşünüyor"),
                   ("reading", None, "claude", "📖 Okuyor"), ("editing", None, "claude", "✏️ Düzenliyor"),
                   ("running", None, "claude", "⚙️ Komut çalıştırıyor"), ("waiting", None, "claude", "✋ Seni bekliyor"),
                   ("done", None, "gpt", "🎉 Bitti"), ("error", None, "gpt", "💥 Hata"),
                   ("sleeping", None, "gpt", "💤 Uyuyor"), ("idle", "pleased", "gpt", "💙 Teşekkür edince"),
                   ("idle", "shocked", "gpt", "😮 BÜYÜK HARFLE"), ("idle", "dizzy", "gpt", "😵 3 hata üst üste")],
        "health": [("ok", "Her şey yolunda"), ("update", "Güncelleme var"), ("broken", "Bir şey çalışmıyor")],
        "switch": [("claude", "Claude'a geçince"), ("gpt", "ChatGPT / Codex'e geçince")],
    },
    "en": {
        "tagline1": "Whatever Claude and GPT are doing,",
        "tagline2": "a little robot in your screen corner says it.",
        "chips": ["Claude Code", "Codex", "Claude & ChatGPT apps", "+ your own AI"],
        "bubble": ("Claude", "telepaith", "🔮 Thinking… figuring it out"),
        "states": [("idle", None, "claude", "Idle"), ("thinking", None, "claude", "🔮 Thinking"),
                   ("reading", None, "claude", "📖 Reading"), ("editing", None, "claude", "✏️ Editing"),
                   ("running", None, "claude", "⚙️ Running a command"), ("waiting", None, "claude", "✋ Waiting for you"),
                   ("done", None, "gpt", "🎉 Done"), ("error", None, "gpt", "💥 Error"),
                   ("sleeping", None, "gpt", "💤 Asleep"), ("idle", "pleased", "gpt", "💙 When you say thanks"),
                   ("idle", "shocked", "gpt", "😮 ALL CAPS"), ("idle", "dizzy", "gpt", "😵 3 errors in a row")],
        "health": [("ok", "All good"), ("update", "Update available"), ("broken", "Something's broken")],
        "switch": [("claude", "In Claude"), ("gpt", "In ChatGPT / Codex")],
    },
}


def hero(lang, social=False):
    t = T[lang]
    W, H = (1280, 640) if social else (1200, 460)
    oy = 90 if social else 0
    b = []
    b.append('<rect width="%d" height="%d" rx="%d" fill="url(#bg)"/>' % (W, H, 0 if social else 28))
    b.append('<g clip-path="url(#clip)">%s'
             '<circle cx="%d" cy="%d" r="420" fill="none" stroke="#9FB8FF" stroke-opacity="0.07" stroke-width="10"/>'
             '<circle cx="%d" cy="%d" r="520" fill="none" stroke="#9FB8FF" stroke-opacity="0.04" stroke-width="10"/>'
             '</g>' % ("{STARS}", W - 230, H - 120, W - 230, H - 120))
    # sol: başlık
    lx = 70
    b.append('<text x="%d" y="%d" font-family="%s" font-size="78" font-weight="800" fill="#FFFFFF" '
             'letter-spacing="-1.5">Telep<tspan fill="url(#ai)">AI</tspan>th</text>' % (lx, 150 + oy, FONT))
    b.append('<text font-family="%s" font-size="25" fill="#D4CCF2">'
             '<tspan x="%d" y="%d">%s</tspan><tspan x="%d" y="%d">%s</tspan></text>'
             % (FONT, lx, 205 + oy, esc(t["tagline1"]), lx, 240 + oy, esc(t["tagline2"])))
    cx, cy = lx, 290 + oy
    for i, chip in enumerate(t["chips"]):
        dots = [[CLAUDE], [GPT], [CLAUDE, GPT], ["#9C86FF"]][i]
        text_x = 16 + 10 * (len(dots) - 1) + 12
        w = text_x + text_width(chip, 16) + 16
        if cx + w > 600:
            cx, cy = lx, cy + 46
        b.append('<rect x="%.1f" y="%d" width="%.1f" height="34" rx="17" fill="#FFFFFF" fill-opacity="0.08" '
                 'stroke="#FFFFFF" stroke-opacity="0.16"/>' % (cx, cy, w))
        for k, dc in enumerate(dots):
            b.append('<circle cx="%.1f" cy="%d" r="4" fill="%s"/>' % (cx + 16 + 10 * k, cy + 17, dc))
        b.append('<text x="%.1f" y="%d" font-family="%s" font-size="16" fill="#EDE9FF">%s</text>'
                 % (cx + text_x, cy + 23, FONT, esc(chip)))
        cx += w + 10
    # sağ: genel bir uygulama penceresi + köşesine yapışmış robot
    wx, wy, ww, wh = W - 600, 50 + oy * 0.8, 450, 300
    b.append('<g filter="url(#win)"><rect x="%d" y="%d" width="%d" height="%d" rx="14" fill="#201C33"/></g>'
             % (wx, wy, ww, wh))
    b.append('<rect x="%d" y="%d" width="%d" height="%d" rx="14" fill="none" stroke="#FFFFFF" stroke-opacity="0.10"/>'
             % (wx, wy, ww, wh))
    for i, c in enumerate(("#FF5F57", "#FEBC2E", "#28C840")):
        b.append('<circle cx="%d" cy="%d" r="6" fill="%s"/>' % (wx + 22 + i * 20, wy + 20, c))
    lines = [(0.55, 0.0), (0.82, 0.0), (0.7, 0.0), (0.4, 0.0), (0.78, 0.0), (0.6, 0.0)]
    for i, (frac, _) in enumerate(lines):
        right = i in (0, 3)
        lw = (ww - 80) * frac
        lx2 = wx + ww - 32 - lw if right else wx + 32
        b.append('<rect x="%.1f" y="%.1f" width="%.1f" height="11" rx="5.5" fill="#FFFFFF" fill-opacity="%.2f"/>'
                 % (lx2, wy + 58 + i * 30, lw, 0.16 if right else 0.09))
    b.append('<rect x="%d" y="%d" width="%d" height="46" rx="14" fill="#2C2745" stroke="#FFFFFF" stroke-opacity="0.12"/>'
             % (wx + 24, wy + wh - 70, ww - 48))
    hs = 1.55
    hx, hy = wx + ww + 20 - 50 * hs, wy + wh - 50 * hs - 6
    b.append(head(hx, hy, hs, state="thinking", who="claude"))
    title, sub, text = t["bubble"]
    bw = max(250, text_width(text, 14) + 34)
    bs = 1.25
    bx, by = hx + 50 * hs - (bw - 50) * bs, hy - 52 * bs - 8
    b.append(bubble(bx, by, bw, title, CLAUDE, text, subtitle=sub, tail_x=bw - 50, scale=bs))
    avoid = [(lx - 10, 70 + oy, 560, cy + 40 - (70 + oy)), (wx, wy, ww, wh), (bx, by, bw * bs, 62 * bs),
             (hx - 70, hy - 70, 100 * hs + 140, 100 * hs + 140)]
    b[1] = b[1].replace("{STARS}", stars(W, H, avoid=avoid))
    defs = (bg_defs("bg", W, H) +
            '<clipPath id="clip"><rect width="%d" height="%d" rx="28"/></clipPath>'
            '<linearGradient id="ai" x1="0" y1="0" x2="1" y2="0"><stop offset="0.1" stop-color="#F2906A"/>'
            '<stop offset="0.9" stop-color="#5B9BFF"/></linearGradient>'
            '<filter id="win" x="-10%%" y="-10%%" width="120%%" height="130%%">'
            '<feDropShadow dx="0" dy="14" stdDeviation="16" flood-color="#000" flood-opacity="0.45"/></filter>' % (W, H))
    return svg(W, H, "".join(b), defs)


def card_grid(items, cols, cell_w, cell_h, head_s, pad=26):
    rows = math.ceil(len(items) / cols)
    W, H = cols * cell_w + pad * 2, rows * cell_h + pad * 2
    b = ['<rect width="%d" height="%d" rx="24" fill="url(#bg)"/>' % (W, H), ""]
    avoid = []
    for i, (draw, label) in enumerate(items):
        r, c = divmod(i, cols)
        x0, y0 = pad + c * cell_w, pad + r * cell_h
        hx = x0 + (cell_w - 100 * head_s) / 2
        tw = text_width(label, 15)
        avoid += [(hx - 18, y0, 100 * head_s + 36, 100 * head_s + 26),
                  (x0 + cell_w / 2 - tw / 2 - 6, y0 + 18 + 100 * head_s + 8, tw + 12, 26)]
        b.append(draw(hx, y0 + 18, head_s))
        b.append('<text x="%.1f" y="%.1f" text-anchor="middle" font-family="%s" font-size="15" fill="#E7E2FB">%s</text>'
                 % (x0 + cell_w / 2, y0 + 18 + 100 * head_s + 26, FONT, esc(label)))
    b[1] = '<g clip-path="url(#clip)">%s</g>' % stars(W, H, seed=len(items), n=14, avoid=avoid)
    defs = bg_defs("bg", W, H) + '<clipPath id="clip"><rect width="%d" height="%d" rx="24"/></clipPath>' % (W, H)
    return svg(W, H, "".join(b), defs)


def states(lang):
    items = [((lambda s, m, w: (lambda x, y, k: head(x, y, k, state=s, mood=m, who=w)))(s, m, w), label)
             for s, m, w, label in T[lang]["states"]]
    return card_grid(items, 6, 180, 175, 1.15)


def health(lang):
    items = [((lambda h: (lambda x, y, k: head(x, y, k, state="idle", who="claude", health=h)))(h), label)
             for h, label in T[lang]["health"]]
    return card_grid(items, 3, 210, 185, 1.25)


def switch(lang):
    items = [((lambda w: (lambda x, y, k: head(x, y, k, state="idle", who=w)))(w), label)
             for w, label in T[lang]["switch"]]
    return card_grid(items, 2, 250, 185, 1.25)


def main():
    os.makedirs(OUT, exist_ok=True)
    files = {}
    for lang in ("tr", "en"):
        files["hero-%s.svg" % lang] = hero(lang)
        files["states-%s.svg" % lang] = states(lang)
        files["switch-%s.svg" % lang] = switch(lang)
    files["social-preview.svg"] = hero("tr", social=True)
    for name, content in files.items():
        with open(os.path.join(OUT, name), "w") as f:
            f.write(content)
    # Sosyal önizleme PNG (GitHub → Settings → Social preview)
    src = os.path.join(OUT, "social-preview.svg")
    dst = os.path.join(OUT, "social-preview.png")
    try:
        # Renkli emoji için Chrome ile; yoksa rsvg-convert
        try:
            from playwright.sync_api import sync_playwright
            with sync_playwright() as p:
                chrome = os.environ.get("CHROME", "/usr/bin/google-chrome")
                br = p.chromium.launch(executable_path=chrome) if os.path.exists(chrome) else p.chromium.launch()
                pg = br.new_page(viewport={"width": 1280, "height": 640})
                pg.goto("file://" + src)
                pg.screenshot(path=dst)
                br.close()
        except ImportError:
            subprocess.run(["rsvg-convert", "-w", "1280", "-h", "640", "-o", dst, src], check=True)
        os.remove(src)
    except (OSError, subprocess.CalledProcessError) as e:
        print("PNG üretilemedi:", e, file=sys.stderr)
    print("\n".join(sorted(os.listdir(OUT))))


if __name__ == "__main__":
    main()
