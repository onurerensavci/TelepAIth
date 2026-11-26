#!/usr/bin/env python3
# Gardırop önizlemesi: python3 scripts/outfits-preview.py → /tmp/outfits-preview.html (tarayıcıda aç)
import json, itertools, pathlib
ROOT = pathlib.Path(__file__).resolve().parent.parent
items=json.load(open(ROOT / 'assets/outfits.json',encoding='utf-8'))
THEMES={'claude':(0xD9,0x77,0x57),'gpt':(0x4C,0x8D,0xF6)}
cnt=itertools.count()
def tok(t,theme):
    if t=='theme': return 'rgb(%d,%d,%d)'%theme,1
    if t=='theme-dark': return 'rgb(%d,%d,%d)'%tuple(int(c*0.72) for c in theme),1
    if t=='theme-light': return 'rgb(%d,%d,%d)'%tuple(int(c+(255-c)*0.35) for c in theme),1
    h=t[1:]
    if len(h)==8: return '#'+h[:6], int(h[6:],16)/255
    return '#'+h,1
def paint(v,theme,defs):
    if isinstance(v,str): c,a=tok(v,theme); return c,a
    gid='g%d'%next(cnt)
    stops=''.join(f'<stop offset="{o}" stop-color="{tok(c,theme)[0]}" stop-opacity="{tok(c,theme)[1]}"/>' for o,c in v['stops'])
    if 'lin' in v:
        x1,y1,x2,y2=v['lin']; defs.append(f'<linearGradient id="{gid}" gradientUnits="userSpaceOnUse" x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}">{stops}</linearGradient>')
    else:
        cx,cy,r=v['rad']; defs.append(f'<radialGradient id="{gid}" gradientUnits="userSpaceOnUse" cx="{cx}" cy="{cy}" r="{r}">{stops}</radialGradient>')
    return f'url(#{gid})',1
def shape(s,theme,defs):
    a=''
    if s.get('fill'): c,o=paint(s['fill'],theme,defs); a+=f' fill="{c}" fill-opacity="{o}" fill-rule="evenodd"'
    else: a+=' fill="none"'
    if s.get('stroke'): c,o=paint(s['stroke'],theme,defs); a+=f' stroke="{c}" stroke-opacity="{o}" stroke-width="{s.get("w",1)}" stroke-linecap="round" stroke-linejoin="round"'
    if 'd' in s: return f'<path d="{s["d"]}"{a}/>'
    if 'ellipse' in s: e=s['ellipse']; return f'<ellipse cx="{e[0]}" cy="{e[1]}" rx="{e[2]}" ry="{e[3]}"{a}/>'
    r=s['rect']; return f'<rect x="{r[0]}" y="{r[1]}" width="{r[2]}" height="{r[3]}" rx="{r[4]}"{a}/>'
def eyes(theme):
    col='rgb(%d,%d,%d)'%tuple(int(c+(255-c)*0.18) for c in theme)
    out=''
    for cx in (36,64):
        for i in range(14):
            for j in range(18):
                x=cx-11.4+i*1.75; y=52-14.9+j*1.75
                on=((x-cx)/5.2)**2+((y-52)/8.5)**2<=1
                out+=f'<circle cx="{x:.2f}" cy="{y:.2f}" r="0.65" fill="{col}" fill-opacity="{1 if on else 0.09}"/>'
    return out
def robot(theme,worn):
    defs=[]
    body=''.join(shape(s,theme,defs) for it in worn if it['slot'] in ('face','eyes') for s in it['shapes'])
    head=''.join(shape(s,theme,defs) for it in worn if it['slot']=='head' for s in it['shapes'])
    side=''.join(shape(s,theme,defs) for it in worn if it['slot']=='side' for s in it['shapes'])
    base=f'''<ellipse cx="50" cy="96" rx="29" ry="3" fill="#000" fill-opacity="0.14"/>
<circle cx="6" cy="50" r="6" fill="#BDB5D6"/><circle cx="94" cy="50" r="6" fill="#BDB5D6"/>
<rect x="7" y="15" width="86" height="70" rx="24" fill="url(#shell)"/><rect x="15" y="30" width="70" height="44" rx="18" fill="#17142A"/>{eyes(theme)}'''
    led='<circle cx="50" cy="22.5" r="5.5" fill="#33D478" fill-opacity="0.3"/><circle cx="50" cy="22.5" r="2.5" fill="#33D478"/>'
    return f'<svg viewBox="-26 -30 152 140" width="230" height="212"><defs><linearGradient id="shell" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#FAF7F2"/><stop offset="1" stop-color="#DBD6EB"/></linearGradient>{"".join(defs)}</defs>{side}{base}{body}{head}{led}</svg>'
cards=''
src=['claude','gpt']
for k,it in enumerate(items):
    theme=THEMES[src[k%2]]
    cards+=f'<div class="c">{robot(theme,[it])}<div>{it["tr"]}</div></div>'
combo=[i for i in items if i['id'] in ('cap','sunglasses','cactus')]
combo2=[i for i in items if i['id'] in ('crown','blush','bowtie','coffee')]
cards=f'<div class="c big">{robot(THEMES["claude"],combo)}<div>Kep + güneş gözlüğü + kaktüs</div></div><div class="c big">{robot(THEMES["gpt"],combo2)}<div>Taç + pembe yanak + papyon + kahve</div></div>'+cards
open('/tmp/outfits-preview.html','w').write(f'<html><body style="margin:0;background:#2b2a33;color:#ddd;font:13px -apple-system,Segoe UI,sans-serif;display:flex;flex-wrap:wrap;gap:10px;padding:14px;width:1220px">{cards}<style>.c{{background:linear-gradient(#45425a,#34324a);border-radius:14px;padding:6px 6px 10px;text-align:center}}</style></body></html>')
