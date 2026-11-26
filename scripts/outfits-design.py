#!/usr/bin/env python3
# Gardırobun kaynağı: python3 scripts/outfits-design.py → assets/outfits.json, sonra python3 scripts/gen-outfits.py
# 3B görünümlü gardırop: gradyanlar, parlamalar ve temas gölgeleri (100x100 kafa alanı; ışık sol üstten)
import json, pathlib
ROOT = pathlib.Path(__file__).resolve().parent.parent
HOLE=" M 55,22.5 C 55,25.26 52.76,27.5 50,27.5 C 47.24,27.5 45,25.26 45,22.5 C 45,19.74 47.24,17.5 50,17.5 C 52.76,17.5 55,19.74 55,22.5 Z"
def lin(x1,y1,x2,y2,*stops): return {"lin":[x1,y1,x2,y2],"stops":[[o,c] for o,c in stops]}
def rad(cx,cy,r,*stops): return {"rad":[cx,cy,r],"stops":[[o,c] for o,c in stops]}
def P(d,fill=None,stroke=None,w=1):
    s={"d":d}
    if fill: s["fill"]=fill
    if stroke: s["stroke"]=stroke; s["w"]=w
    return s
def E(cx,cy,rx,ry,fill=None,stroke=None,w=1):
    s={"ellipse":[cx,cy,rx,ry]}
    if fill: s["fill"]=fill
    if stroke: s["stroke"]=stroke; s["w"]=w
    return s
def R(x,y,w,h,r,fill=None,stroke=None,sw=1):
    s={"rect":[x,y,w,h,r]}
    if fill: s["fill"]=fill
    if stroke: s["stroke"]=stroke; s["w"]=sw
    return s
def A(shape,k,a,s,p=None,o=0):
    # Hareket: sway (p etrafında ±a derece), bob (±a nokta yukarı-aşağı), beat (1±a ölçek), rise (a nokta yükselip söner),
    # twinkle (arada bir parlayıp söner), slide (±a nokta kayan parlama); s: saniyedeki tur, o: faz
    shape["anim"]={"k":k,"a":a,"s":s,"o":o}
    if p: shape["anim"]["p"]=p
    return shape
THEME=lambda cx,cy,r: rad(cx,cy,r,(0,"theme-light"),(0.55,"theme"),(1,"theme-dark"))
GOLD=lambda x1,y1,x2,y2: lin(x1,y1,x2,y2,(0,"#FFF1A8"),(0.35,"#F7CC4A"),(0.75,"#E0A526"),(1,"#A8701A"))
CREAM=lin(0,14,0,28,(0,"#FFFFFF"),(1,"#DCD5E6"))
SHADOW="#2A1F4A33"
def eyelet(): return [E(50,22.5,5.6,5.6,stroke=lin(44,17,56,28,(0,"#FFFFFF"),(1,"#9C98AE")),w=1.8)]
items=[]
def item(id,slot,tr,en,shapes,level=None,ach=None):
    d={"id":id,"slot":slot,"tr":tr,"en":en}
    if level is not None: d["level"]=level
    if ach: d["achievement"]=ach
    d["shapes"]=shapes; items.append(d)

# --- BAŞ: kafanın şekline oturan parçalar; ışık için küçük delik (r 3.4) ve ince halka ---
import math, re
def circ(cx,cy,r):
    k=0.5523*r
    return (f" M {cx+r},{cy} C {cx+r},{cy+k} {cx+k},{cy+r} {cx},{cy+r} C {cx-k},{cy+r} {cx-r},{cy+k} {cx-r},{cy}"
            f" C {cx-r},{cy-k} {cx-k},{cy-r} {cx},{cy-r} C {cx+k},{cy-r} {cx+r},{cy-k} {cx+r},{cy} Z")
SMALLHOLE=circ(50,22.5,3.4)
def grommet(): return [E(50,22.5,3.9,3.9,stroke=lin(46,18.5,54,26.5,(0,"#FFFFFF"),(0.5,"#C9C4D8"),(1,"#7E7896")),w=1.1)]
def _rp(x,y,a,cx,cy):
    r=math.radians(a); dx,dy=x-cx,y-cy
    return round(cx+dx*math.cos(r)-dy*math.sin(r),2), round(cy+dx*math.sin(r)+dy*math.cos(r),2)
def rotd(d,a,cx,cy):
    out=[];nums=[]
    for tok in re.findall(r"[MLCQZ]|-?\d+(?:\.\d+)?",d):
        if tok.isalpha():
            out.append(tok)
        else:
            nums.append(float(tok))
            if len(nums)==2:
                x,y=_rp(nums[0],nums[1],a,cx,cy); out.append(f"{x},{y}"); nums=[]
    return " ".join(out)
def rotshape(s,a,cx,cy):
    s=dict(s)
    if "d" in s: s["d"]=rotd(s["d"],a,cx,cy)
    if "ellipse" in s:
        e=s["ellipse"]; x,y=_rp(e[0],e[1],a,cx,cy); s["ellipse"]=[x,y,e[2],e[3]]
    for key in ("fill","stroke"):
        v=s.get(key)
        if isinstance(v,dict):
            v=dict(v)
            if "lin" in v:
                x1,y1=_rp(v["lin"][0],v["lin"][1],a,cx,cy); x2,y2=_rp(v["lin"][2],v["lin"][3],a,cx,cy); v["lin"]=[x1,y1,x2,y2]
            if "rad" in v:
                x,y=_rp(v["rad"][0],v["rad"][1],a,cx,cy); v["rad"]=[x,y,v["rad"][2]]
            s[key]=v
    if "anim" in s and "p" in s["anim"]:
        an=dict(s["anim"]); x,y=_rp(an["p"][0],an["p"][1],a,cx,cy); an["p"]=[x,y]; s["anim"]=an
    return s
DARK_A="#00000026"

# Bere: kafayı saran örgü kubbe, katlanmış örgü kenar, kabarık ponpon
cuff="M 12,16 L 88,16 C 92.5,16 95.5,19.5 95.5,23 C 95.5,27 92.5,30 88,30 C 70,31.6 30,31.6 12,30 C 7.5,30 4.5,27 4.5,23 C 4.5,19.5 7.5,16 12,16 Z"
ribs=" ".join(f"M {x},18.6 L {x},28.4" for x in [9,13.5,18,22.5,27,31.5,36,40.5,59.5,64,68.5,73,77.5,82,86.5,91])
pom=[(50,-10,8.5)]
item("beanie","head","Bere","Beanie",[
  E(50,30.5,41,3,fill=SHADOW),
  P("M 8,22 C 8,3 27,-8 50,-8 C 73,-8 92,3 92,22 Z",fill=rad(34,-4,64,(0,"theme-light"),(0.5,"theme"),(1,"theme-dark"))),
  P("M 50,-6 L 50,17 M 39,-5 C 37,3 36.5,10 36.5,17 M 28.5,-2 C 25.5,5 24.5,11 24.5,17 M 19.5,4 C 16.5,9 15.5,13 15.5,17 M 61,-5 C 63,3 63.5,10 63.5,17 M 71.5,-2 C 74.5,5 75.5,11 75.5,17 M 80.5,4 C 83.5,9 84.5,13 84.5,17",stroke=DARK_A,w=2.6),
  P("M 51.3,-5 L 51.3,16 M 40.3,-4 C 38.4,3 37.9,10 37.9,16 M 29.8,-1 C 26.9,5 25.9,11 25.9,16 M 62.3,-4 C 64.3,3 64.8,10 64.8,16 M 72.8,-1 C 75.8,5 76.8,11 76.8,16",stroke="#FFFFFF24",w=0.9),
  P("M 18,6 C 25,-2 36,-6 46,-6.5",stroke="#FFFFFF66",w=2.6),
  P(cuff+SMALLHOLE,fill=lin(0,16,0,30,(0,"theme-light"),(0.5,"theme"),(1,"theme-dark"))),
  P(ribs,stroke="#00000024",w=1.7),
  P("M 11,17.4 L 89,17.4",stroke="#FFFFFF66",w=1.1),
  P("M 9,16.8 C 30,14.6 70,14.6 91,16.8",stroke="#00000026",w=1.2),
  *grommet(),
  *[A(E(x,y,r,r,fill=rad(x-r*0.35,y-r*0.4,r*1.25,(0,"#FFFFFF"),(0.6,"#F3EEF8"),(1,"#CFC6E0"))),"sway",7,0.9,p=[50,0]) for x,y,r in pom],
  A(E(50,-10,8.5,8.5,stroke="#FFFFFF66",w=1.4),"sway",7,0.9,p=[50,0]),
  A(P("M 45,-6 L 46,-7 M 53,-5.5 L 54.2,-6.4 M 49.5,-15 L 50.6,-15.8 M 55,-11 L 56.2,-11.6 M 44.5,-11.5 L 45.5,-12.5",stroke="#B9AFCF",w=1),"sway",7,0.9,p=[50,0]),
  A(E(46.6,-13.6,2.4,1.7,fill="#FFFFFFEE"),"sway",7,0.9,p=[50,0]),
],level=1)

# Kep: yana dönük siperlik, dikiş çizgileri, tepede düğme; ışık önden küçük delikten
item("cap","head","Kep","Cap",[
  E(50,30.5,40,2.8,fill=SHADOW),
  P("M 62,23 C 78,19.5 97,20 106,25.5 C 101,30.5 80,31.5 62,29.5 Z",fill=lin(62,20,106,31,(0,"theme"),(0.6,"theme-dark"),(1,"theme-dark"))),
  P("M 64,24.3 C 79,21.4 95,21.8 103,25.3",stroke="#FFFFFF4D",w=1.3),
  P("M 8,29.5 C 8,6 27,-4 50,-4 C 73,-4 92,6 92,29.5 C 70,31.6 30,31.6 8,29.5 Z"+SMALLHOLE,fill=rad(35,1,64,(0,"theme-light"),(0.5,"theme"),(1,"theme-dark"))),
  P("M 50,-3.4 L 50,18.3 M 50,-3.4 C 37,0 29,12 27.3,30.4 M 50,-3.4 C 63,0 71,12 72.7,30.4",stroke="#00000026",w=1.3),
  P("M 51.1,-2.4 L 51.1,18.3 M 48.6,-2 C 36.5,1.5 29.6,12.5 28.5,30.5",stroke="#FFFFFF22",w=0.8),
  P("M 17,13 C 23,4 33,-0.5 43,-1.8",stroke="#FFFFFF66",w=2.6),
  P("M 8.4,29.4 C 30,31.6 70,31.6 91.6,29.4",stroke="theme-dark",w=1.8),
  *grommet(),
  E(50,-4,4.2,2.6,fill=rad(49,-5,4.6,(0,"theme-light"),(1,"theme-dark"))),
],level=3)

# Kulaklık: yastıklı kafa bandı, büyük yuvarlak kulaklıklar, AI renginde kapaklar
def cup(x,flip):
    sx=-1 if flip else 1
    return [
      R(x,31,18,38,9,fill=lin(x,31,x+18,69,(0,"#8C88AA"),(1,"#3C3954"))),
      R(x+2.5,35,13,30,6.5,fill=rad(x+6,40,18,(0,"theme-light"),(0.55,"theme"),(1,"theme-dark"))),
      E(x+9,50,3.4,6.5,fill="#FFFFFF1F"),
      R(x+(15 if not flip else -2),36,5,28,2.5,fill="#2A283A"),
    ]
item("headphones","head","Kulaklık","Headphones",[
  P("M 3,40 C 3,-6 97,-6 97,40",stroke=lin(0,-2,0,40,(0,"#4A475E"),(1,"#2A283C")),w=8),
  P("M 3,40 C 3,-6 97,-6 97,40",stroke=lin(0,0,100,0,(0,"#6E6A88"),(0.5,"#B4B0CE"),(1,"#5A5674")),w=3.4),
  P("M 14,14 C 26,1 74,1 86,14",stroke="#FFFFFF40",w=1.1),
  R(-1,24,8,10,2.5,fill=lin(-1,24,7,34,(0,"#C9C4DA"),(1,"#6E6A88"))),
  R(93,24,8,10,2.5,fill=lin(93,24,101,34,(0,"#C9C4DA"),(1,"#6E6A88"))),
  *cup(-9,False),
  *cup(91,True),
],level=5)

# Silindir şapka: hafif yatık, kenarları kıvrık, AI renginde kurdele
tophat=[
  E(50,16,31,2.8,fill=SHADOW),
  P("M 35.5,12 L 33.5,-21 C 33.5,-23.5 35,-25 37.5,-25 L 62.5,-25 C 65,-25 66.5,-23.5 66.5,-21 L 64.5,12 Z",
    fill=lin(33.5,0,66.5,0,(0,"#4E4C5E"),(0.28,"#2B2A36"),(0.7,"#17161F"),(1,"#363444"))),
  E(50,-25,16.5,3.3,fill=rad(45,-26,17,(0,"#5E5C72"),(1,"#2A2935"))),
  P("M 35,3.5 L 65,3.5 L 64.6,11 L 35.4,11 Z",fill=lin(35,0,65,0,(0,"theme-light"),(0.45,"theme"),(1,"theme-dark"))),
  P("M 35.2,4.6 L 64.8,4.6",stroke="#FFFFFF55",w=0.9),
  P("M 39,-20 L 39.6,2",stroke="#FFFFFF2E",w=3),
  P("M 17,12.5 C 16,9 19,9.2 24,10.6 C 33,9.4 67,9.4 76,10.6 C 81,9.2 84,9 83,12.5 C 82,17 70,18 50,18 C 30,18 18,17 17,12.5 Z",
    fill=rad(42,11,34,(0,"#56546A"),(0.6,"#24232F"),(1,"#121119"))),
  P("M 22,12 C 34,10.4 66,10.4 78,12",stroke="#FFFFFF33",w=1),
]
item("tophat","head","Silindir şapka","Top hat",[rotshape(s,-6,50,13) for s in tophat],level=10)

# Taç: içi kadife, uçlarında inci, kenarında inci dizisi ve mücevherler
crown=[
  E(50,17,23,2.5,fill=SHADOW),
  P("M 30,12 C 30,1 39,-3 50,-3 C 61,-3 70,1 70,12 Z",fill=rad(44,-1,24,(0,"#E2475E"),(0.6,"#A81E36"),(1,"#5E0F1E"))),
  P("M 28,11 L 26,-1 L 37,6 L 43.5,-4 L 50,-10 L 56.5,-4 L 63,6 L 74,-1 L 72,11 Z",fill=GOLD(28,-10,72,11),stroke="#9A6516",w=0.9),
  P("M 29.5,9 L 28.2,1.6 L 36.4,7.6 M 44.6,-2.8 L 50,-7.8",stroke="#FFFFFF80",w=1.1),
  R(27,10,46,7.5,2.5,fill=lin(0,10,0,17.5,(0,"#FFE786"),(0.5,"#E9B53A"),(1,"#B47A1C")),stroke="#9A6516",sw=0.8),
  *[E(x,10.3,1.15,1.15,fill=rad(x-0.4,9.9,1.5,(0,"#FFFFFF"),(1,"#CFC6DA"))) for x in [31,35,39,43,57,61,65,69]],
  E(50,13.8,3.4,2.8,fill=rad(49,12.8,3.8,(0,"#FFA0A8"),(0.5,"#E5484D"),(1,"#8E1424"))),
  E(39,13.8,2.3,2.1,fill=rad(38.4,13.1,2.7,(0,"#A8D4FF"),(0.5,"#3E9BFF"),(1,"#1A55A8"))),
  E(61,13.8,2.3,2.1,fill=rad(60.4,13.1,2.7,(0,"#A8D4FF"),(0.5,"#3E9BFF"),(1,"#1A55A8"))),
  E(31.5,13.8,1.6,1.6,fill=rad(31,13.3,2,(0,"#B8FFD8"),(0.5,"#2FBF71"),(1,"#14713E"))),
  E(68.5,13.8,1.6,1.6,fill=rad(68,13.3,2,(0,"#B8FFD8"),(0.5,"#2FBF71"),(1,"#14713E"))),
  E(49,12.9,1,0.8,fill="#FFFFFFDD"),
  *[E(x,y,r,r,fill=rad(x-r*0.35,y-r*0.4,r*1.3,(0,"#FFFFFF"),(0.6,"#F2EEF6"),(1,"#BDB4CC"))) for x,y,r in [(26,-1.5,2.4),(50,-10.6,2.7),(74,-1.5,2.4),(37,5.6,1.6),(63,5.6,1.6),(43.5,-4.4,1.5),(56.5,-4.4,1.5)]],
  A(P("M 65,-6 L 66,-3 L 69,-2 L 66,-1 L 65,2 L 64,-1 L 61,-2 L 64,-3 Z",fill="#FFFFFF"),"twinkle",1,0.35,p=[65,-2]),
  A(P("M 33,0 L 33.7,2 L 35.7,2.7 L 33.7,3.4 L 33,5.4 L 32.3,3.4 L 30.3,2.7 L 32.3,2 Z",fill="#FFFFFF"),"twinkle",1,0.35,p=[33,2.7],o=0.5),
]
item("crown","head","Taç","Crown",crown,level=20)

# Parti şapkası: yana yatık koni, puantiyeler, tabanda fırfır, tepede püskül
party=[
  E(50,17.5,17,2.4,fill=SHADOW),
  P("M 37,16.5 L 65,16.5 L 51,-21 Z",fill=lin(37,0,65,0,(0,"#B19BFF"),(0.45,"#7C5CFF"),(1,"#4A2BC4"))),
  P("M 41,12 L 47,-8",stroke="#FFFFFF55",w=1.8),
  *[E(x,y,r,r,fill=rad(x-r*0.3,y-r*0.3,r*1.3,(0,c1),(1,c2))) for x,y,r,c1,c2 in
    [(45.5,10.5,2.4,"#FFF3B0","#F2B90F"),(56.5,8.5,2.1,"#FFC4D6","#E5487A"),(51,1,2,"#B8FFE6","#25B784"),(47.5,-6,1.6,"#C8E4FF","#3E8BE6"),(55,-3,1.3,"#FFF3B0","#F2B90F")]],
  *[E(x,16.8,2.3,2.3,fill=rad(x-0.6,16.1,2.8,(0,"#FFFFFF"),(1,"theme-light"))) for x in [38,42.5,47,51.5,56,60.5,65]],
  A(E(51,-22.5,5,5,fill=rad(49.3,-24.5,6.3,(0,"#FFF6C2"),(0.6,"#FFD34E"),(1,"#D99A10"))),"bob",1.2,1.6),
  A(E(51,-22.5,5,5,stroke="#FFFFFF55",w=1.2),"bob",1.2,1.6),
  A(E(49.4,-24.3,1.6,1.1,fill="#FFFFFFDD"),"bob",1.2,1.6),
]
item("party","head","Parti şapkası","Party hat",[rotshape(s,14,51,16.5) for s in party],ach="bigday")

# Çiçek: başın sağ üstünde papatya toka
petals=[]
for i in range(9):
    a=math.radians(i*40-90)
    x=82+6.3*math.cos(a); y=9+6.3*math.sin(a)
    petals.append(E(round(x,2),round(y,2),3.4,3.4,fill=rad(round(x-1,2),round(y-1,2),3.6,(0,"#FFFFFF"),(0.7,"#F6F2FA"),(1,"#CFC6DE"))))
item("flower","head","Çiçek","Flower",[A(sh,"sway",5,0.7,p=[80,16]) for sh in [
  P("M 74,17 C 72,13 72.5,10 75,8 C 77,11 76.5,14.5 74,17 Z",fill=lin(72,8,77,17,(0,"#8BE6A6"),(1,"#2F8A4A"))),
  *petals,
  E(82,9,4,4,fill=rad(80.8,7.8,4.8,(0,"#FFF6C2"),(0.6,"#FFC93C"),(1,"#D9940F"))),
  E(80.9,7.8,1.3,0.9,fill="#FFFFFFCC"),
]],ach="streak7")

# Hale: parlayan altın halka, çevresinde ışık ve küçük yıldızlar
item("halo","head","Hale","Halo",[
  A(E(50,-4,24,5.4,stroke="#FFE08A33",w=9),"bob",1.4,0.6),
  A(E(50,-4,24,5.4,stroke=lin(26,0,74,0,(0,"#FFF6C8"),(0.5,"#FFD54A"),(1,"#D9981E")),w=3.4),"bob",1.4,0.6),
  A(P("M 31,-7.6 C 39,-9.4 51,-9.7 61,-9",stroke="#FFFFFFCC",w=1.1),"bob",1.4,0.6),
  A(P("M 77,-8 L 77.7,-6 L 79.7,-5.3 L 77.7,-4.6 L 77,-2.6 L 76.3,-4.6 L 74.3,-5.3 L 76.3,-6 Z",fill="#FFF6C8"),"twinkle",1,0.3,p=[77,-5.3]),
],ach="hundred")

LENS=lin(0,41,0,62,(0,"#4A4A66"),(0.5,"#16161F"),(1,"#050508"))
item("sunglasses","eyes","Güneş gözlüğü","Sunglasses",[
  P("M 20,46 L 6,46 M 80,46 L 94,46",stroke="#16161E",w=2.4),
  P("M 18.5,40.5 L 47.5,40.5 C 48.8,40.5 49.5,41.5 49.5,43 L 49.5,53 C 49.5,59.5 45.5,62.5 39,62.5 L 28,62.5 C 21.5,62.5 18.5,58.5 18.5,52 Z",fill=LENS,stroke="#000000",w=1.6),
  P("M 81.5,40.5 L 52.5,40.5 C 51.2,40.5 50.5,41.5 50.5,43 L 50.5,53 C 50.5,59.5 54.5,62.5 61,62.5 L 72,62.5 C 78.5,62.5 81.5,58.5 81.5,52 Z",fill=LENS,stroke="#000000",w=1.6),
  P("M 22,45 L 30,44 L 24,56 Z M 54,45 L 62,44 L 56,56 Z",fill="#FFFFFF26"),
  P("M 49.5,44.5 L 50.5,44.5",stroke="#000000",w=3),
  P("M 21,42.5 L 46,42.5 M 54,42.5 L 79,42.5",stroke="#FFFFFF30",w=0.8),
  A(P("M 46,42 L 52,42 L 44,61 L 38,61 Z",fill="#FFFFFF30"),"slide",22,0.25),
],level=8)

GOLDR=lin(22,40,50,64,(0,"#FFF1A8"),(0.5,"#D9A93A"),(1,"#8F6418"))
item("round","eyes","Yuvarlak gözlük","Round glasses",[
  P("M 23.5,50 L 7,47 M 76.5,50 L 93,47",stroke="#B88A2E",w=2),
  E(36,52,12.5,12.5,fill=rad(32,47,15,(0,"#FFFFFF2A"),(1,"#FFFFFF08")),stroke=GOLDR,w=2.6),
  E(64,52,12.5,12.5,fill=rad(60,47,15,(0,"#FFFFFF2A"),(1,"#FFFFFF08")),stroke=GOLDR,w=2.6),
  P("M 28,46 C 30,43 33,42 36,42 M 56,46 C 58,43 61,42 64,42",stroke="#FFFFFF66",w=1.4),
  P("M 48.5,50 C 50,47 50,47 51.5,50",stroke="#B88A2E",w=2.2),
],ach="storyteller")

HEART="M {x},64 C {a},56 {b},47 {c},42 C {d},39 {e},41 {x},45 C {f},41 {g},39 {h},42 C {i},47 {j},56 {x},64 Z"
def heart(x): return HEART.format(x=x,a=x-13,b=x-16,c=x-10,d=x-6,e=x-2,f=x+2,g=x+6,h=x+10,i=x+16,j=x+13)
HFILL=lambda x: lin(x-14,40,x+10,64,(0,"#FF9CC0EE"),(0.5,"#FF4F8BDD"),(1,"#C2185BEE"))
item("hearts","eyes","Kalp gözlük","Heart glasses",[
  P("M 23,49 L 7,47 M 77,49 L 93,47",stroke="#C2185B",w=2),
  A(P(heart(36),fill=HFILL(36),stroke="#A0154D",w=1.3),"beat",0.07,1.1,p=[36,52]),
  A(P(heart(64),fill=HFILL(64),stroke="#A0154D",w=1.3),"beat",0.07,1.1,p=[64,52]),
  A(E(30.5,46,3,2,fill="#FFFFFF77"),"beat",0.07,1.1,p=[36,52]), A(E(58.5,46,3,2,fill="#FFFFFF77"),"beat",0.07,1.1,p=[64,52]),
  P("M 46,47 C 50,45 50,45 54,47",stroke="#A0154D",w=2),
],ach="night")

item("blush","face","Pembe yanak","Rosy cheeks",[
  E(25,66,8,4.5,fill=rad(25,66,8,(0,"#FF7FA8CC"),(1,"#FF7FA800"))),
  E(75,66,8,4.5,fill=rad(75,66,8,(0,"#FF7FA8CC"),(1,"#FF7FA800"))),
  E(23,64.8,1.4,0.8,fill="#FFFFFF66"), E(73,64.8,1.4,0.8,fill="#FFFFFF66"),
],level=2)

item("mustache","face","Bıyık","Mustache",[
  P("M 50,66 C 46,62.5 40,62.5 37,65.5 C 34,68.5 30,68.5 27.5,65.5 C 29.5,72.5 38,74 44,70.5 C 47,69 49,68 50,68 C 51,68 53,69 56,70.5 C 62,74 70.5,72.5 72.5,65.5 C 70,68.5 66,68.5 63,65.5 C 60,62.5 54,62.5 50,66 Z",
    fill=lin(0,62,0,74,(0,"#9A6A42"),(0.5,"#6B4428"),(1,"#3E2414"))),
  P("M 40,65.5 C 43,64.5 46,65 48.5,66.5 M 60,65.5 C 57,64.5 54,65 51.5,66.5",stroke="#FFFFFF33",w=1),
],level=12)

item("bowtie","face","Papyon","Bow tie",[
  E(50,95.5,13,1.8,fill="#00000022"),
  P("M 50,90 C 45,86 40,83 37,84 C 35,85 35,95 37,96 C 40,97 45,94 50,90 Z",fill=lin(36,84,50,96,(0,"theme-light"),(0.5,"theme"),(1,"theme-dark"))),
  P("M 50,90 C 55,86 60,83 63,84 C 65,85 65,95 63,96 C 60,97 55,94 50,90 Z",fill=lin(50,84,64,96,(0,"theme"),(1,"theme-dark"))),
  P("M 39,86.5 C 41,86 44,87 46,88.5",stroke="#FFFFFF55",w=1),
  R(46.8,86.8,6.4,6.4,2.4,fill=rad(49,88.5,5,(0,"theme-light"),(1,"theme-dark"))),
],ach="team")

POT=lin(100,86,114,100,(0,"#E8946A"),(0.5,"#C9744A"),(1,"#8E4A2A"))
RIM=lin(0,85.5,0,89,(0,"#F0A27C"),(1,"#A85A36"))
item("cactus","side","Kaktüs","Cactus",[
  E(107,100.5,8,1.6,fill="#00000026"),
  P("M 104,80 C 99.5,80 99.5,76 99.5,72.5",stroke=lin(98,72,104,80,(0,"#7FD69A"),(1,"#2F8A4A")),w=3.4),
  P("M 110,78 C 114.5,78 114.5,74 114.5,70.5",stroke=lin(110,70,116,78,(0,"#7FD69A"),(1,"#2F8A4A")),w=3.4),
  R(103.5,68,7,20,3.5,fill=lin(103.5,0,110.5,0,(0,"#8FE0A8"),(0.45,"#4FA36A"),(1,"#2A7A42"))),
  P("M 105.3,71 L 105.3,86",stroke="#FFFFFF44",w=1),
  P("M 99.5,87.5 L 114.5,87.5 L 112.2,100 L 101.8,100 Z",fill=POT),
  R(98.5,85,17,3.6,1.4,fill=RIM),
  P("M 101,89.5 L 102.5,99",stroke="#FFFFFF33",w=1),
],level=4)

item("coffee","side","Kahve","Coffee",[
  E(106,100.5,8,1.6,fill="#00000026"),
  A(P("M 103,81 C 101,78 105,77 103,74",stroke="#CFC9DCCC",w=1.6),"rise",5,0.6),
  A(P("M 108,81 C 106,78 110,77 108,74",stroke="#CFC9DCCC",w=1.6),"rise",5,0.6,o=0.5),
  P("M 112,87 C 117.5,87 117.5,95.5 112,95.5",stroke=lin(112,87,118,96,(0,"#FFFFFF"),(1,"#B9B0CC")),w=2.4),
  R(100,84,12.5,15.5,3.4,fill=lin(100,0,112.5,0,(0,"#FFFFFF"),(0.5,"#F2EEE8"),(1,"#C9C0D8"))),
  E(106.25,85.4,5.3,1.6,fill=rad(105,85,5,(0,"#9A6438"),(1,"#4A2A14"))),
  P("M 101.8,87.5 L 101.8,97",stroke="#FFFFFFBB",w=1.2),
  R(101.5,90.5,9.5,3,1.5,fill="theme"),
],ach="early")

item("sprout","side","Fidan","Sprout",[
  E(107,100.5,8,1.6,fill="#00000026"),
  P("M 107,88 L 107,77",stroke=lin(106,77,108,88,(0,"#5BD07E"),(1,"#2F8A4A")),w=2.2),
  A(P("M 107,80 C 101,80 98.5,75 99.5,72.5 C 104,72.5 107,76 107,80 Z",fill=lin(99,72,107,80,(0,"#9BF0B4"),(1,"#2F9A52"))),"sway",6,0.8,p=[107,80]),
  A(P("M 107,78 C 113,78 115.5,73 114.5,70.5 C 110,70.5 107,74 107,78 Z",fill=lin(107,70,115,78,(0,"#9BF0B4"),(1,"#2F9A52"))),"sway",6,0.8,p=[107,78],o=0.25),
  P("M 99.5,87.5 L 114.5,87.5 L 112.2,100 L 101.8,100 Z",fill=lin(100,86,114,100,(0,"#8FAAF0"),(0.5,"#5B7DD8"),(1,"#3A55A8"))),
  R(98.5,85,17,3.6,1.4,fill=lin(0,85.5,0,89,(0,"#A4BAF5"),(1,"#4A69BF"))),
  P("M 101,89.5 L 102.5,99",stroke="#FFFFFF44",w=1),
],level=15)

json.dump(items,open(ROOT / 'assets/outfits.json','w',encoding='utf-8'),ensure_ascii=False,indent=1)
print(len(items))
