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
def item(id,slot,tr,en,shapes,level=None,ach=None,type=None,legendary=False):
    # type: hangi tipin parçası (polis, hipster…); legendary: tipin gizli ödülü (parıltılı, seviyeyle açılır)
    d={"id":id,"slot":slot,"tr":tr,"en":en,"type":type}
    if legendary: d["legendary"]=True
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

# ---------- yardımcılar: kaydır, aynala, leke ----------
def _map_d(d,f):
    out=[];nums=[]
    for tok in re.findall(r"[MLCQZ]|-?\d+(?:\.\d+)?",d):
        if tok.isalpha(): out.append(tok)
        else:
            nums.append(float(tok))
            if len(nums)==2:
                x,y=f(nums[0],nums[1]); out.append(f"{round(x,2)},{round(y,2)}"); nums=[]
    return " ".join(out)
def _map_shape(s,f,flip=False):
    s=dict(s)
    if "d" in s: s["d"]=_map_d(s["d"],f)
    if "ellipse" in s:
        e=s["ellipse"]; x,y=f(e[0],e[1]); s["ellipse"]=[round(x,2),round(y,2),e[2],e[3]]
    if "rect" in s:
        r=s["rect"]; x,y=f(r[0],r[1])
        if flip: x-=r[2]
        s["rect"]=[round(x,2),round(y,2),r[2],r[3],r[4]]
    for key in ("fill","stroke"):
        v=s.get(key)
        if isinstance(v,dict):
            v=dict(v)
            if "lin" in v:
                x1,y1=f(v["lin"][0],v["lin"][1]); x2,y2=f(v["lin"][2],v["lin"][3]); v["lin"]=[round(x1,2),round(y1,2),round(x2,2),round(y2,2)]
            if "rad" in v:
                x,y=f(v["rad"][0],v["rad"][1]); v["rad"]=[round(x,2),round(y,2),v["rad"][2]]
            s[key]=v
    if "anim" in s and "p" in s["anim"]:
        an=dict(s["anim"]); x,y=f(an["p"][0],an["p"][1]); an["p"]=[round(x,2),round(y,2)]; s["anim"]=an
    return s
def shift(shapes,dx,dy): return [_map_shape(s,lambda x,y:(x+dx,y+dy)) for s in shapes]
def mirror(shapes): return [_map_shape(s,lambda x,y:(100-x,y),flip=True) for s in shapes]
def blob(cx,cy,r,seed,n=8,j=0.28):
    import random
    rnd=random.Random(seed); pts=[]
    for i in range(n):
        a=2*math.pi*i/n+rnd.uniform(-0.2,0.2); rr=r*(1+rnd.uniform(-j,j))
        pts.append((cx+rr*math.cos(a),cy+rr*math.sin(a)*0.85))
    mids=[((pts[i][0]+pts[(i+1)%n][0])/2,(pts[i][1]+pts[(i+1)%n][1])/2) for i in range(n)]
    d=f"M {mids[-1][0]:.2f},{mids[-1][1]:.2f}"
    for i in range(n): d+=f" Q {pts[i][0]:.2f},{pts[i][1]:.2f} {mids[i][0]:.2f},{mids[i][1]:.2f}"
    return d+" Z"
def star(x,y,r,k=0.32):
    pts=[]
    for i in range(10):
        a=math.radians(-90+36*i); rr=r if i%2==0 else r*k*1.4
        pts.append(f"{x+rr*math.cos(a):.2f},{y+rr*math.sin(a):.2f}")
    return "M "+" L ".join(pts)+" Z"
def sparkle(x,y,r): return f"M {x},{y-r} L {x+r*0.25},{y-r*0.25} L {x+r},{y} L {x+r*0.25},{y+r*0.25} L {x},{y+r} L {x-r*0.25},{y+r*0.25} L {x-r},{y} L {x-r*0.25},{y-r*0.25} Z"
SILVER=lambda x1,y1,x2,y2: lin(x1,y1,x2,y2,(0,"#FFFFFF"),(0.45,"#C9C6D6"),(1,"#6E6A88"))
NAVY=lambda x1,y1,x2,y2: lin(x1,y1,x2,y2,(0,"#4A6BC0"),(0.55,"#22377A"),(1,"#101A40"))
GOLDR=lin(22,40,50,64,(0,"#FFF1A8"),(0.5,"#D9A93A"),(1,"#8F6418"))
def gem(x,y,r,c1,c2,c3): return E(x,y,r,r,fill=rad(x-r*0.35,y-r*0.4,r*1.3,(0,c1),(0.5,c2),(1,c3)))
RUBY=("#FFA0A8","#E5484D","#8E1424"); SAPPH=("#A8D4FF","#3E9BFF","#1A55A8"); EMER=("#B8FFD8","#2FBF71","#14713E")

# =====================================================================
# KODCU 💻 — kulaklık, mikrofon, yaka kartı, lastik ördek; gizli ödül: hacker vizörü
# =====================================================================
def cup(x,flip):
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
],level=1,type="coder")

# Mikrofon: sol kulaktan ağza uzanan ince kol, süngerli mikrofon başı, AI renginde halka
item("mic","face","Yayın mikrofonu","Headset mic",[
  P("M 7,58 C 8,70 15,77.5 28,77.5",stroke=lin(6,58,28,78,(0,"#5A5674"),(1,"#2A283C")),w=2.4),
  P("M 8.2,59 C 9.4,69.5 15.8,76 27,76.4",stroke="#FFFFFF3A",w=0.8),
  E(28.6,77.5,1.3,2.4,fill="theme"),
  E(33.4,77.5,4.6,3.8,fill=rad(31.8,75.8,5.6,(0,"#6E6A88"),(0.55,"#2E2C3E"),(1,"#121119"))),
  P("M 30.6,76 L 31,79 M 33.2,74.6 L 33.4,80.4 M 35.8,75.2 L 35.6,79.8",stroke="#FFFFFF1C",w=0.7),
  E(31.8,75.7,1.5,0.9,fill="#FFFFFF55"),
  A(E(38.6,74.4,0.8,0.8,fill="#FF5A5F"),"twinkle",1,0.5),
],level=2,type="coder")

# Yaka kartı: AI renginde ip, gümüş klips, fotoğraflı kart
item("lanyard","neck","Yaka kartı","Lanyard",[
  P("M 27,80 C 33,88 42,90.5 50,90.5 M 73,80 C 67,88 58,90.5 50,90.5",stroke="theme-dark",w=3),
  P("M 27.5,80.2 C 33.4,87.6 42,89.8 50,89.8 M 72.5,80.2 C 66.6,87.6 58,89.8 50,89.8",stroke="theme-light",w=1.2),
  R(48.2,89,3.6,3.6,1,fill=SILVER(48,89,52,93)),
  E(50,104.5,9,1.4,fill="#00000020"),
  R(42,92,16,12,2.2,fill=lin(42,92,58,104,(0,"#FFFFFF"),(1,"#D6D0E2"))),
  P("M 44.2,92 L 55.8,92 C 57,92 58,93 58,94.2 L 58,95.4 L 42,95.4 L 42,94.2 C 42,93 43,92 44.2,92 Z",fill="theme"),
  R(44,97,4.6,5.2,1,fill=lin(44,97,48.6,102,(0,"#C9C4DA"),(1,"#8C88AA"))),
  E(46.3,98.7,1.1,1.1,fill="#F2EEF8"),
  P("M 50.4,98 L 56,98 M 50.4,100.2 L 54.6,100.2",stroke="#9C98AE",w=0.9),
  P("M 43,92.9 L 52,92.9",stroke="#FFFFFF66",w=0.6),
],ach="firsttouch",type="coder")

# Lastik ördek: hata ayıklamanın sırdaşı; hafifçe sallanır
DUCK=lambda x1,y1,x2,y2: lin(x1,y1,x2,y2,(0,"#FFF3A0"),(0.5,"#FFD234"),(1,"#E09A12"))
item("duck","side","Lastik ördek","Rubber duck",[
  E(108,101,8.5,1.5,fill="#00000026"),
  *[A(sh,"sway",4,0.6,p=[108,100]) for sh in [
    P("M 113.5,92.5 L 117.5,88.5 L 116,95 Z",fill=DUCK(113,88,118,95)),
    E(108,95.6,8,5,fill=rad(105,92.5,10,(0,"#FFF6B8"),(0.55,"#FFD234"),(1,"#D98E10"))),
    P("M 105.5,95 C 107.5,92.6 111.6,92.8 113,95.6 C 111,97.6 107.5,97.6 105.5,95 Z",fill="#F2B4206E"),
    E(103.4,87.6,4.8,4.6,fill=rad(101.8,85.8,6,(0,"#FFF6B8"),(0.55,"#FFD234"),(1,"#D98E10"))),
    P("M 99.2,87.6 C 97,87.4 95.6,88.4 96,89.4 C 96.9,90.5 98.8,90.1 100,89.4 Z",fill=lin(96,87,100,90,(0,"#FFB070"),(1,"#E0641A"))),
    E(102.4,86.6,0.95,0.95,fill="#1A1826"),
    E(102.1,86.3,0.35,0.35,fill="#FFFFFF"),
    E(101.6,84.5,1.6,1,fill="#FFFFFF88"),
    P("M 103,93 C 105,91.6 109,91.4 112,92.2",stroke="#FFFFFF77",w=0.9),
  ]],
],ach="green",type="coder")

# Gizli ödül — Hacker vizörü: yeşil camda akan kod, tarama çizgisi, kayan parlama
code=[]
for k,(x,o,sp) in enumerate([(22,0,0.55),(27,0.4,0.7),(32,0.15,0.5),(38,0.65,0.62),(44,0.3,0.75),(56,0.8,0.58),(62,0.05,0.68),(68,0.5,0.52),(73,0.25,0.72),(78,0.7,0.6)]):
    y=44+(k*3)%8
    code.append(A(P(f"M {x},{y} L {x},{y+1.6} M {x},{y+3.4} L {x},{y+4.6} M {x},{y+6.6} L {x},{y+8.4}",stroke="#3DFF8F",w=1.2),"rise",-6,sp,o=o))
item("visor","eyes","Hacker vizörü","Hacker visor",[
  P("M 15,48 L 5,47 M 85,48 L 95,47",stroke="#26262F",w=2.6),
  E(50,51,40,16,fill=rad(50,51,40,(0,"#3DFF8F22"),(1,"#3DFF8F00"))),
  P("M 16,43 C 16,40.5 18,39.5 21,39.5 L 79,39.5 C 82,39.5 84,40.5 84,43 L 84,57 C 84,61 81,63 77,63 L 59,63 C 55,63 53,60 50,60 C 47,60 45,63 41,63 L 23,63 C 19,63 16,61 16,57 Z",
    fill=lin(0,39.5,0,63,(0,"#0E4A2EEE"),(1,"#02140AF5")),stroke=lin(16,39,84,63,(0,"#D8FFE8"),(0.5,"#5FB98A"),(1,"#1E5A3A")),w=1.6),
  *code,
  A(P("M 18,50 L 82,50",stroke="#9DFFC8AA",w=0.8),"bob",8,0.35),
  P("M 20,41.6 L 80,41.6",stroke="#FFFFFF40",w=0.8),
  A(P("M 40,40 L 46,40 L 38,62.5 L 32,62.5 Z",fill="#FFFFFF22"),"slide",24,0.22),
  A(E(80.5,43,1.1,1.1,fill="#3DFF8F"),"twinkle",1,0.6),
  A(P(sparkle(86,36,3),fill="#D8FFE8"),"twinkle",1,0.3,p=[86,36]),
],level=12,type="coder",legendary=True)

# =====================================================================
# HİPSTER ☕ — bere, yuvarlak gözlük, bıyık, ekose atkı; gizli ödül: gramofon
# =====================================================================
cuff="M 12,16 L 88,16 C 92.5,16 95.5,19.5 95.5,23 C 95.5,27 92.5,30 88,30 C 70,31.6 30,31.6 12,30 C 7.5,30 4.5,27 4.5,23 C 4.5,19.5 7.5,16 12,16 Z"
ribs=" ".join(f"M {x},18.6 L {x},28.4" for x in [9,13.5,18,22.5,27,31.5,36,40.5,59.5,64,68.5,73,77.5,82,86.5,91])
dome=shift([
  P("M 8,22 C 8,3 27,-8 50,-8 C 73,-8 92,3 92,22 Z",fill=rad(34,-4,64,(0,"theme-light"),(0.5,"theme"),(1,"theme-dark"))),
  P("M 50,-6 L 50,17 M 39,-5 C 37,3 36.5,10 36.5,17 M 28.5,-2 C 25.5,5 24.5,11 24.5,17 M 19.5,4 C 16.5,9 15.5,13 15.5,17 M 61,-5 C 63,3 63.5,10 63.5,17 M 71.5,-2 C 74.5,5 75.5,11 75.5,17 M 80.5,4 C 83.5,9 84.5,13 84.5,17",stroke=DARK_A,w=2.6),
  P("M 51.3,-5 L 51.3,16 M 40.3,-4 C 38.4,3 37.9,10 37.9,16 M 29.8,-1 C 26.9,5 25.9,11 25.9,16 M 62.3,-4 C 64.3,3 64.8,10 64.8,16 M 72.8,-1 C 75.8,5 76.8,11 76.8,16",stroke="#FFFFFF24",w=0.9),
  P("M 18,6 C 25,-2 36,-6 46,-6.5",stroke="#FFFFFF66",w=2.6),
],0,5)
pomp=shift([
  A(E(50,-10,8.5,8.5,fill=rad(47,-13.4,10.6,(0,"#FFFFFF"),(0.6,"#F3EEF8"),(1,"#CFC6E0"))),"sway",7,0.9,p=[50,0]),
  A(E(50,-10,8.5,8.5,stroke="#FFFFFF66",w=1.4),"sway",7,0.9,p=[50,0]),
  A(P("M 45,-6 L 46,-7 M 53,-5.5 L 54.2,-6.4 M 49.5,-15 L 50.6,-15.8 M 55,-11 L 56.2,-11.6 M 44.5,-11.5 L 45.5,-12.5",stroke="#B9AFCF",w=1),"sway",7,0.9,p=[50,0]),
  A(E(46.6,-13.6,2.4,1.7,fill="#FFFFFFEE"),"sway",7,0.9,p=[50,0]),
],0,5)
band=shift([
  P(cuff,fill=lin(0,16,0,30,(0,"theme-light"),(0.5,"theme"),(1,"theme-dark"))),
  P(ribs,stroke="#00000024",w=1.7),
  P("M 11,17.4 L 89,17.4",stroke="#FFFFFF66",w=1.1),
  P("M 9,16.8 C 30,14.6 70,14.6 91,16.8",stroke="#00000026",w=1.2),
],0,2)
band[0]["d"]+=SMALLHOLE
item("beanie","head","Örgü bere","Beanie",[E(50,32.5,41,3,fill=SHADOW),*dome,*band,*grommet(),*pomp],level=3,type="hipster")

item("round","eyes","Yuvarlak gözlük","Round glasses",[
  P("M 23.5,50 L 7,47 M 76.5,50 L 93,47",stroke="#B88A2E",w=2),
  E(36,52,12.5,12.5,fill=rad(32,47,15,(0,"#FFFFFF2A"),(1,"#FFFFFF08")),stroke=GOLDR,w=2.6),
  E(64,52,12.5,12.5,fill=rad(60,47,15,(0,"#FFFFFF2A"),(1,"#FFFFFF08")),stroke=GOLDR,w=2.6),
  P("M 28,46 C 30,43 33,42 36,42 M 56,46 C 58,43 61,42 64,42",stroke="#FFFFFF66",w=1.4),
  P("M 48.5,50 C 50,47 50,47 51.5,50",stroke="#B88A2E",w=2.2),
],level=5,type="hipster")

item("mustache","face","Gür bıyık","Bushy mustache",[
  P("M 50,66 C 46,62.5 40,62.5 37,65.5 C 34,68.5 30,68.5 27.5,65.5 C 29.5,72.5 38,74 44,70.5 C 47,69 49,68 50,68 C 51,68 53,69 56,70.5 C 62,74 70.5,72.5 72.5,65.5 C 70,68.5 66,68.5 63,65.5 C 60,62.5 54,62.5 50,66 Z",
    fill=lin(0,62,0,74,(0,"#9A6A42"),(0.5,"#6B4428"),(1,"#3E2414"))),
  P("M 40,65.5 C 43,64.5 46,65 48.5,66.5 M 60,65.5 C 57,64.5 54,65 51.5,66.5",stroke="#FFFFFF33",w=1),
  P("M 34,69 C 36,70.4 39,70.8 41.5,70 M 66,69 C 64,70.4 61,70.8 58.5,70",stroke="#00000033",w=0.8),
],level=7,type="hipster")

# Ekose atkı: boynu saran kırmızı ekose, yandan sarkan saçaklı uç
PLAID=lin(0,80,0,95,(0,"#D9504E"),(0.5,"#B23A3A"),(1,"#7E2228"))
item("scarf","neck","Ekose atkı","Plaid scarf",[
  E(50,94,34,2.4,fill=SHADOW),
  P("M 61,88 L 72,88 L 74.5,104 L 62.5,104 Z",fill=lin(61,88,74,104,(0,"#C24644"),(1,"#7A2026"))),
  P("M 64.6,88 L 65.5,104 M 69,88 L 70.4,104",stroke="#4E101655",w=1.8),
  P("M 61.6,93 L 72.8,93 M 62.2,98.6 L 73.6,98.6",stroke="#4E101655",w=1.6),
  P("M 66.8,88 L 68,104 M 62,95.8 L 73.2,95.8",stroke="#F2C14E77",w=0.6),
  P("M 63.5,104 L 63.3,107.4 M 66,104 L 66,107.8 M 68.5,104 L 68.7,107.4 M 71,104 L 71.3,107.8 M 73.4,104 L 73.8,107.2",stroke="#9A2C32",w=1.1),
  P("M 13,84 C 30,79.6 70,79.6 87,84 L 88,90.5 C 70,95 30,95 12,90.5 Z",fill=PLAID),
  P("M 22,82.4 L 21.4,92.4 M 32,81.4 L 31.7,93.4 M 42,81 L 41.9,93.9 M 58,81 L 58.1,93.9 M 68,81.4 L 68.3,93.4 M 78,82.4 L 78.6,92.4",stroke="#4E101655",w=2.4),
  P("M 13,87.2 C 30,83.2 70,83.2 87,87.2",stroke="#4E101655",w=2.2),
  P("M 27,81.9 L 26.6,92.9 M 50,80.9 L 50,94.1 M 73,81.9 L 73.4,92.9",stroke="#F2C14E77",w=0.7),
  P("M 12.6,89.4 C 30,85.6 70,85.6 87.4,89.4",stroke="#F2C14E66",w=0.7),
  E(66.5,89.2,6.2,4.6,fill=rad(64.5,87.6,7.5,(0,"#E2605C"),(0.6,"#B23A3A"),(1,"#6E1C22"))),
  P("M 63,87.4 L 70,91 M 62.4,90.4 L 68.6,87.2",stroke="#4E101644",w=1.2),
  P("M 17,83.2 C 32,80 68,80 83,83.2",stroke="#FFFFFF44",w=1),
],ach="early",type="hipster")

# Gizli ödül — Gramofon: ahşap kutu, pirinç boru, borudan yükselen notalar
BRASS=lambda x1,y1,x2,y2: lin(x1,y1,x2,y2,(0,"#FFF1B0"),(0.35,"#E8C25A"),(0.75,"#C08A2A"),(1,"#7A5214"))
note=lambda x,y: [E(x,y,1.6,1.15,fill="theme-light"),P(f"M {x+1.4},{y} L {x+1.4},{y-5.2} L {x+3.6},{y-6.2}",stroke="theme-light",w=0.9)]
item("gramophone","side","Gramofon","Gramophone",[
  E(107,101,9.5,1.6,fill="#00000026"),
  R(98.5,92.5,17,8,1.6,fill=lin(98.5,92.5,115.5,100.5,(0,"#C89060"),(0.5,"#9A6438"),(1,"#5E3A1C"))),
  P("M 99.5,94.6 L 114.5,94.6",stroke="#FFFFFF33",w=0.7),
  R(103,96,8,2.6,1,fill="#00000033"),
  E(107,92.4,7.2,1.6,fill=rad(105,92,7.5,(0,"#4A4760"),(1,"#121119"))),
  E(107,92.3,2,0.6,fill="theme"),
  P("M 111,92 C 112,88 110.5,85.6 108,84",stroke=BRASS(108,84,112,92),w=1.8),
  P("M 107.4,84.6 L 99.4,74.6 C 101.5,70 112,69 114.8,72.6 L 109.2,84.6 Z",fill=BRASS(99,70,115,85)),
  E(107.1,73.4,7.4,2.9,fill=rad(107,73.4,7.6,(0,"#3A2408"),(0.7,"#6A4612"),(1,"#C08A2A"))),
  E(107.1,73.4,7.4,2.9,stroke="#FFF1B0AA",w=0.7),
  P("M 101,75.8 L 107.6,83.6",stroke="#FFFFFF55",w=0.8),
  *[A(sh,"rise",9,0.45) for sh in note(103,69)],
  *[A(sh,"rise",9,0.45,o=0.5) for sh in note(109.5,67)],
  A(P(sparkle(116,79,2.4),fill="#FFF1B0"),"twinkle",1,0.35,p=[116,79]),
],level=15,type="hipster",legendary=True)

# =====================================================================
# POLİS 🚓 — pilot gözlüğü, düdük, rozetli kravat, telsiz; gizli ödül: sirenli polis şapkası
# =====================================================================
AVI=lin(0,40,0,63,(0,"#5C8FD0F2"),(0.45,"#1E3550F5"),(1,"#B07A44F0"))
lens_l="M 19,44 C 19,41.5 21,40.5 24,40.5 L 41,40.5 C 44.5,40.5 46.5,42.5 46.5,46 C 46.5,54 43,62.5 34,62.5 C 25,62.5 19,56 19,48 Z"
avl=[P(lens_l,fill=AVI,stroke=GOLD(19,40,46,63),w=1.5), P("M 23,44 L 31,43.5 L 25,55 Z",fill="#FFFFFF2E")]
item("sunglasses","eyes","Pilot gözlüğü","Aviators",[
  P("M 19,45 L 6,46 M 81,45 L 94,46",stroke=GOLD(0,44,100,47),w=1.6),
  *avl, *mirror(avl),
  P("M 44,43.4 C 47,41.8 53,41.8 56,43.4",stroke=GOLD(44,42,56,44),w=1.5),
  P("M 46.6,47.6 C 48.5,46.7 51.5,46.7 53.4,47.6",stroke=GOLD(46,46,54,48),w=1.1),
  A(P("M 46,41 L 52,41 L 44,61 L 38,61 Z",fill="#FFFFFF2A"),"slide",22,0.25),
],level=4,type="police")

# Düdük: ağızda gümüş düdük, mavi kordon, ara sıra öten çizgiler
item("whistle","face","Düdük","Whistle",[
  P("M 72,73 C 80,71 86,75 89,82",stroke="#2E5CB8",w=1.3),
  P("M 52,70.4 L 64.5,70.4 C 65.8,69.4 67.4,68.8 69,68.8 C 72.8,68.8 75.6,71.6 75.6,75.4 C 75.6,79.2 72.8,82 69,82 C 66,82 63.4,80 62.6,77.4 L 52,75.6 Z",
    fill=SILVER(52,68,76,82),stroke="#6E6A88",w=0.6),
  R(60.4,69,3.6,1.8,0.8,fill="#2A283A"),
  E(69,75.4,3,3,fill=rad(68,74.4,3.6,(0,"#FFFFFF"),(1,"#9C98AE"))),
  P("M 53.5,71.6 L 62,71.6",stroke="#FFFFFFAA",w=0.8),
  E(72.6,72.4,1,1,fill="#6E6A88"),
  A(P("M 61.2,66.6 L 60.4,63.8 M 63.6,66.4 L 64.6,63.6 M 58.8,67.4 L 56.8,65.6",stroke="#FFFFFFCC",w=0.9),"twinkle",1,0.7),
],ach="chatty",type="police")

# Rozetli kravat: beyaz yaka, lacivert kravat, altın iğne; göğüste polis rozeti
collar=[P("M 39,83.2 L 46.4,83.2 L 48,89.6 L 41.6,88.4 Z",fill=lin(39,83,48,90,(0,"#FFFFFF"),(1,"#CFC8DC")))]
item("tie","neck","Rozetli kravat","Badge & tie",[
  E(50,96,14,1.6,fill="#00000022"),
  *collar, *mirror(collar),
  P("M 47.4,88.8 L 52.6,88.8 L 55.2,101.4 L 50,106 L 44.8,101.4 Z",fill=NAVY(44,88,56,106)),
  P("M 46,84 L 54,84 L 52.8,89.4 L 47.2,89.4 Z",fill=NAVY(46,84,54,90)),
  P("M 48.4,90 L 47,100.6",stroke="#FFFFFF33",w=0.8),
  R(44.6,94.4,10.8,1.5,0.7,fill=GOLD(44,94,56,96)),
  P("M 28.6,86.6 L 35.4,86.6 L 35.4,90 C 35.4,92.8 33.4,94.4 32,95 C 30.6,94.4 28.6,92.8 28.6,90 Z",fill=GOLD(28,86,36,95),stroke="#9A6516",w=0.5),
  P(star(32,90.4,2.2),fill="#FFF6D0"),
],level=9,type="police")

# Telsiz: siyah gövde, anten, yeşil ekran, yanıp sönen mavi ışık
item("radio","side","Telsiz","Walkie-talkie",[
  E(107.5,101,7.5,1.5,fill="#00000026"),
  R(110,69,2.4,12,1.2,fill=lin(110,69,112.4,81,(0,"#5A5674"),(1,"#1A1826"))),
  R(101.5,79.5,12,21,2.8,fill=lin(101.5,79.5,113.5,100.5,(0,"#4A4760"),(0.5,"#2A2838"),(1,"#121119"))),
  R(103.5,82,8,4.6,1,fill=lin(0,82,0,86.6,(0,"#B8FFD8"),(1,"#4FBF84"))),
  P("M 104.6,83.6 L 108.6,83.6 M 104.6,85 L 107,85",stroke="#14503088",w=0.7),
  P("M 104,90 L 111,90 M 104,92.2 L 111,92.2 M 104,94.4 L 111,94.4 M 104,96.6 L 111,96.6",stroke="#00000066",w=1),
  P("M 102.8,81 L 102.8,98",stroke="#FFFFFF2E",w=0.8),
  R(113.2,86,1.6,5,0.7,fill="#5A5674"),
  A(E(104.4,79.8,1.6,1.6,fill="#3E9BFF66"),"twinkle",1,0.8),
  A(E(104.4,79.8,0.8,0.8,fill="#BFE0FF"),"twinkle",1,0.8),
],ach="team",type="police")

# Gizli ödül — Sirenli polis şapkası: lacivert tepe, siyah bant (ışık bantta), parlak siper, altın rozet, kırmızı-mavi siren
siren_glow=lambda x,c,o: A(E(x,-11,9,7,fill=rad(x,-11,9,(0,c+"AA"),(1,c+"00"))),"twinkle",1,1.6,o=o)
item("sirencap","head","Sirenli polis şapkası","Siren police cap",[
  E(50,33,40,2.8,fill=SHADOW),
  P("M 13,12 C 30,17 70,17 87,12 L 85,20 C 70,23 30,23 15,20 Z",fill=NAVY(15,12,85,22)),
  P("M 9,11 C 5,3 22,-4 50,-4 C 78,-4 95,3 91,11 C 85,16.5 15,16.5 9,11 Z",fill=rad(40,0,52,(0,"#5A7CD0"),(0.55,"#22377A"),(1,"#101A40"))),
  P("M 14,6 C 24,0 38,-2 50,-2.4",stroke="#FFFFFF44",w=1.8),
  P("M 15,19 C 30,21.8 70,21.8 85,19 L 85,26 C 70,28.8 30,28.8 15,26 Z"+SMALLHOLE,fill=lin(0,19,0,28,(0,"#3A3A48"),(1,"#0E0E14"))),
  P("M 15.6,20.4 C 30,23.2 70,23.2 84.4,20.4",stroke=GOLD(15,20,85,23),w=1),
  P("M 15,26 C 30,28.8 70,28.8 85,26 C 88,28.6 86,31.6 80,33 C 65,35.4 35,35.4 20,33 C 14,31.6 12,28.6 15,26 Z",fill=lin(0,26,0,35,(0,"#4A4A5A"),(1,"#050508"))),
  P("M 24,30.4 C 38,32.4 62,32.4 76,30.4",stroke="#FFFFFF55",w=1),
  P("M 45.8,5.4 L 54.2,5.4 L 54.2,10 C 54.2,13.4 51.8,15 50,15.8 C 48.2,15 45.8,13.4 45.8,10 Z",fill=GOLD(45,5,55,16),stroke="#9A6516",w=0.6),
  P(star(50,10,2.6),fill="#FFF6D0"),
  *grommet(),
  siren_glow(45,"#FF3B3B",0), siren_glow(55,"#3E8BFF",0.5),
  R(42.5,-5.4,15,3.6,1.4,fill=SILVER(42,-5,58,-2)),
  P("M 43.6,-5.2 C 43.6,-11.6 46.6,-14.2 50,-14.2 L 50,-5.2 Z",fill=lin(43,-14,50,-5,(0,"#FF9A9A"),(0.5,"#E5262B"),(1,"#8E0E14"))),
  P("M 56.4,-5.2 C 56.4,-11.6 53.4,-14.2 50,-14.2 L 50,-5.2 Z",fill=lin(57,-14,50,-5,(0,"#A8CCFF"),(0.5,"#2E6FE0"),(1,"#0E2A7A"))),
  A(P("M 43.6,-5.2 C 43.6,-11.6 46.6,-14.2 50,-14.2 L 50,-5.2 Z",fill="#FFFFFFAA"),"twinkle",1,1.6),
  A(P("M 56.4,-5.2 C 56.4,-11.6 53.4,-14.2 50,-14.2 L 50,-5.2 Z",fill="#FFFFFFAA"),"twinkle",1,1.6,o=0.5),
  E(47.2,-11,1,1.8,fill="#FFFFFF77"),
],level=18,type="police",legendary=True)

# =====================================================================
# PAZARLAMACI 📣 — fikir ampulü, kalın çerçeve, megafon, ipek fular; gizli ödül: roket
# =====================================================================
bulb=[
  E(50,-3,13,13,fill=rad(50,-3,13,(0,"#FFE46B66"),(1,"#FFE46B00"))),
  P("M 50,-13 C 55.4,-13 58.6,-9.2 58.6,-4.8 C 58.6,-1.6 56.6,0 55.4,2.2 C 54.8,3.2 54.6,4.2 54.6,5 L 45.4,5 C 45.4,4.2 45.2,3.2 44.6,2.2 C 43.4,0 41.4,-1.6 41.4,-4.8 C 41.4,-9.2 44.6,-13 50,-13 Z",
    fill=rad(47.4,-8,13,(0,"#FFFDE8"),(0.5,"#FFE46B"),(1,"#F2B90F"))),
  P("M 47.2,4.4 L 47.6,-1.4 L 48.8,-3.8 L 50,-1.4 L 51.2,-3.8 L 52.4,-1.4 L 52.8,4.4",stroke="#C27A0A",w=0.8),
  R(45.4,5,9.2,5,1.4,fill=SILVER(45,5,55,10)),
  P("M 45.6,6.7 L 54.4,6.7 M 45.6,8.4 L 54.4,8.4",stroke="#6E6A88",w=0.7),
  E(50,10.4,2.4,1.2,fill="#3A3850"),
  E(46.4,-7.8,1.6,2.6,fill="#FFFFFFCC"),
]
item("bulb","head","Fikir ampulü","Idea bulb",[
  *[A(sh,"bob",1.4,0.8) for sh in bulb],
  A(P("M 50,-17 L 50,-19.6 M 59.6,-13.6 L 61.6,-15.4 M 40.4,-13.6 L 38.4,-15.4 M 63,-5 L 65.8,-5 M 37,-5 L 34.2,-5",stroke="#FFD34E",w=1.5),"twinkle",1,0.7),
],level=6,type="marketing")

# Kalın çerçeve gözlük: siyah kalın çerçeve, menteşede AI rengi
bold=[R(18.5,41,28,20,6.5,fill="#FFFFFF14",stroke=lin(18,41,46,61,(0,"theme-light"),(0.5,"theme"),(1,"theme-dark")),sw=3.6),
      P("M 22,42.4 L 34,42.4",stroke="#FFFFFF88",w=1), R(14.6,43.8,4,3.6,1.2,fill="#16161E")]
item("boldframes","eyes","Kalın çerçeve","Bold frames",[
  P("M 17,46 L 6,45 M 83,46 L 94,45",stroke="#16161E",w=2.6),
  *bold, *mirror(bold),
  P("M 46.4,47 C 48.4,45.4 51.6,45.4 53.6,47",stroke="theme",w=3),
  A(P("M 40,42 L 45,42 L 39,60 L 34,60 Z",fill="#FFFFFF22"),"slide",24,0.22),
],level=8,type="marketing")

# Megafon: AI renginde huni, beyaz ağız, sırayla yayılan ses dalgaları
waves=[A(P(f"M {x},{70-h} C {x+2.6},{70-h*0.5} {x+2.6},{70+h*0.5} {x},{70+h}",stroke="theme-light",w=1.4),"twinkle",1,0.9,o=o)
       for x,h,o in [(90,6,0),(93.6,8.5,0.25),(97.2,11,0.5)]]
item("megaphone","face","Megafon","Megaphone",[
  P("M 66,74.5 L 64.6,80.6 L 68.2,81.2 L 69.6,75.2 Z",fill="#2A283A"),
  R(52.6,69.4,6.6,5.2,1.8,fill=lin(0,69,0,75,(0,"#5A5674"),(1,"#1A1826"))),
  P("M 58.6,69.6 L 82,61.2 C 85,60.6 86.6,63.4 86.6,70 C 86.6,76.6 85,79.4 82,78.8 L 58.6,74.4 Z",fill=lin(0,61,0,79,(0,"theme-light"),(0.5,"theme"),(1,"theme-dark"))),
  P("M 66,66.8 L 66,76 M 71.6,64.8 L 71.6,77",stroke="#FFFFFFCC",w=1.4),
  P("M 60,70.4 L 81.6,62.8",stroke="#FFFFFF55",w=0.9),
  E(84.6,70,3,9.2,fill=lin(82,61,88,79,(0,"#FFFFFF"),(1,"#B9B0CC"))),
  E(85.2,70,1.9,7.6,fill=rad(85,70,6,(0,"#3A3850"),(1,"#121119"))),
  *waves,
],ach="bigday",type="marketing")

# İpek fular: AI renginde puantiyeli, önde düğümlü
SILK=lin(26,84,74,104,(0,"theme-light"),(0.5,"theme"),(1,"theme-dark"))
tails=[P("M 48,92 C 44.6,96.6 41.6,100 38,103 L 43.6,104.6 C 45.8,100.6 48.4,96.6 50,93 Z",fill=SILK)]
item("silk","neck","İpek fular","Silk scarf",[
  E(50,95,24,2,fill=SHADOW),
  P("M 25,83.6 C 37,88.6 63,88.6 75,83.6 L 73.4,89.4 C 62,93 38,93 26.6,89.4 Z",fill=SILK),
  *tails, *mirror(tails),
  *[E(x,y,0.9,0.9,fill="#FFFFFF99") for x,y in [(31,87.4),(38,89.4),(45,90.2),(55,90.2),(62,89.4),(69,87.4),(43.4,99.6),(56.6,99.6),(46,95.4),(54,95.4)]],
  E(50,91,4.6,3.6,fill=rad(48.6,89.8,5.4,(0,"theme-light"),(0.6,"theme"),(1,"theme-dark"))),
  P("M 28,84.6 C 39,88.6 61,88.6 72,84.6",stroke="#FFFFFF55",w=0.9),
],ach="polyglot",type="marketing")

# Gizli ödül — Roket: "aya kadar" büyüme; titreyen alev, duman, parıltılar
item("rocket","side","Roket","Rocket",[
  E(107,101,9,1.5,fill="#00000020"),
  E(102.6,98.6,3.2,1.8,fill="#CFC9DCAA"), E(111.6,99,3.6,1.9,fill="#CFC9DC99"), E(107,99.8,3,1.6,fill="#E6E2EEBB"),
  A(P("M 103.8,88.4 C 103.8,92 105.4,95.6 107,98 C 108.6,95.6 110.2,92 110.2,88.4 Z",fill=rad(107,88.4,9.4,(0,"#FFF6C2"),(0.5,"#FFB02E"),(1,"#FF5A1F00"))),"beat",0.16,5,p=[107,88.4]),
  P("M 101,80 L 97.4,88.4 L 101.6,87.4 Z",fill=lin(97,80,102,88,(0,"#FF7A7A"),(1,"#B0202A"))),
  P("M 113,80 L 116.6,88.4 L 112.4,87.4 Z",fill=lin(112,80,117,88,(0,"#FF7A7A"),(1,"#B0202A"))),
  P("M 107,65.6 C 111.6,69.6 113.2,76.6 113.2,86.2 L 100.8,86.2 C 100.8,76.6 102.4,69.6 107,65.6 Z",fill=lin(100.8,0,113.2,0,(0,"#FFFFFF"),(0.55,"#E6E2EE"),(1,"#9C98AE"))),
  P("M 107,65.6 C 109.6,67.8 111,70.2 111.8,72.8 L 102.2,72.8 C 103,70.2 104.4,67.8 107,65.6 Z",fill=lin(102,66,112,73,(0,"#FF8A8A"),(0.5,"#E5262B"),(1,"#8E0E14"))),
  E(107,78.2,2.8,2.8,fill=rad(106,77.2,3.4,(0,"#BFE0FF"),(0.6,"#3E8BFF"),(1,"#163E8A")),stroke="#C9C6D6",w=0.9),
  E(106.1,77.3,0.9,0.6,fill="#FFFFFFCC"),
  R(103.4,86,7.2,2.4,0.8,fill="#3A3850"),
  P("M 102.6,74.4 L 102.6,85",stroke="#FFFFFF99",w=0.9),
  A(P(sparkle(98.6,69,2.6),fill="#FFF1B0"),"twinkle",1,0.4,p=[98.6,69]),
  A(P(sparkle(116,64.6,2),fill="#FFFFFF"),"twinkle",1,0.4,p=[116,64.6],o=0.5),
],level=21,type="marketing",legendary=True)

# =====================================================================
# SANATÇI 🎨 — ressam beresi, kedi göz gözlük, boya lekeleri, çizgili fular; gizli ödül: sihirli palet
# =====================================================================
BERET=rad(36,4,64,(0,"#F07A7A"),(0.55,"#C8323A"),(1,"#701018"))
item("beret","head","Ressam beresi","Beret",[
  E(50,31,38,2.6,fill=SHADOW),
  P("M 8,18.6 C 4,8.6 20,-0.4 46,-0.4 C 74,-0.4 96,5.6 95,14.6 C 94.4,19.6 86,22 72,22.4 L 28,22.4 C 16,22.4 9,21.6 8,18.6 Z",fill=BERET),
  P("M 14,16.4 C 30,20 70,20 90,15",stroke="#00000030",w=2),
  P("M 18,7.6 C 28,2.6 40,1.4 50,1.4",stroke="#FFFFFF55",w=2.4),
  P("M 16,20.2 C 32,22.8 68,22.8 84,20.2 L 84.4,26 C 68,28.6 32,28.6 15.6,26 Z"+SMALLHOLE,fill=lin(0,20,0,28,(0,"#A8222C"),(1,"#5A0C14"))),
  P("M 17,21.4 C 32,24 68,24 83.4,21.4",stroke="#FFFFFF33",w=0.8),
  P("M 55,0 C 55.4,-3 57,-4.6 59.2,-5",stroke="#7A141C",w=2.4),
  *grommet(),
],level=10,type="artist")

# Kedi göz gözlük: dış köşeleri kalkık kırmızı çerçeve, uçlarında parlayan taşlar
cat=[P("M 16,41.4 C 23,39.6 34,40.4 44,42 C 46.6,42.5 47.6,44 47.1,47 C 46,55 42,61 34,61 C 26,61 21.6,56.4 20.6,50.4 C 18.4,48.2 15.4,45.6 13.6,40.6 C 14.4,40.6 15.2,41 16,41.4 Z",
       fill="#FFFFFF16",stroke=lin(14,40,47,61,(0,"#FF6A80"),(0.5,"#D02A44"),(1,"#7A1022")),w=2.6),
     P("M 19,43.4 C 26,42 34,42.4 41,43.4",stroke="#FFFFFF66",w=1),
     A(P(sparkle(15,41.4,2.4),fill="#FFFFFF"),"twinkle",1,0.45,p=[15,41.4])]
item("cateye","eyes","Kedi göz gözlük","Cat-eye glasses",[
  P("M 18,46 L 6,46.6 M 82,46 L 94,46.6",stroke="#9A1A2E",w=1.8),
  *cat, *mirror(cat),
  P("M 46.8,46 C 48.6,44.4 51.4,44.4 53.2,46",stroke="#B02236",w=2.2),
],ach="night",type="artist")

# Boya lekeleri: yanaklarda renkli lekeler, parlak boya
paints=[(22,69,6.4,1,"#6AB8FF","#1E5AB0"),(31.5,77,3.2,2,"#FF8ABE","#C2185B"),(77.5,67.5,6,3,"#FFE06A","#D9940F"),(69.5,76,3.6,4,"#7CEB9A","#1E8A44"),(82,77,2.2,5,"#C49AFF","#5A2CC4"),(16,61,1.8,6,"#FF8A6A","#D0402A")]
item("paint","face","Boya lekeleri","Paint splashes",[
  *[P(blob(x,y,r,sd),fill=rad(x-r*0.4,y-r*0.4,r*1.6,(0,c1),(1,c2))) for x,y,r,sd,c1,c2 in paints],
  *[E(x-r*0.35,y-r*0.35,r*0.32,r*0.22,fill="#FFFFFFAA") for x,y,r,sd,c1,c2 in paints],
  P("M 25.6,74 C 25.8,77 25.4,79 24.8,80.6",stroke="#4FA8FF",w=1.8),
  E(24.7,81.4,1.2,1.4,fill="#4FA8FF"),
  P("M 79.4,72.6 C 79.6,74.6 79.4,76 79,77",stroke="#F2C14E",w=1.4),
],level=11,type="artist")

# Çizgili fular: lacivert-beyaz çizgili yaka, yanda düğümlü kırmızı boyunluk
item("stripes","neck","Çizgili fular","Striped neckerchief",[
  E(50,96,30,2.2,fill=SHADOW),
  P("M 20,84 C 36,90 64,90 80,84 L 81.6,92 C 64,97.6 36,97.6 18.4,92 Z",fill=lin(0,84,0,97,(0,"#FFFFFF"),(1,"#D8D2E4"))),
  P("M 19.4,86.8 C 36,92.6 64,92.6 80.6,86.8 M 18.8,89.6 C 36,95.2 64,95.2 81.2,89.6",stroke="#22377A",w=1.4),
  P("M 30,86.6 C 38,90 46,90.8 52,90.6 L 50,93.4 C 44,93.6 36,92.6 29,89.6 Z",fill=lin(29,86,52,94,(0,"#FF6A6A"),(1,"#A8202A"))),
  P("M 31,90.6 C 29,95 27.6,98.6 27,102 L 31.4,101 C 32,97.6 33,94.6 34.4,91.6 Z",fill=lin(27,90,35,102,(0,"#E5383F"),(1,"#8E1420"))),
  P("M 33.6,91.4 C 34.6,95.6 36.4,98.8 38.6,101.4 L 41,98.4 C 39.2,96.4 37.8,94 37,91.2 Z",fill=lin(33,91,41,101,(0,"#E5383F"),(1,"#8E1420"))),
  E(33,90.4,3.4,2.8,fill=rad(32,89.4,4,(0,"#FF7A7A"),(0.6,"#D0282F"),(1,"#7A1018"))),
  P("M 22,85.2 C 37,90.6 63,90.6 78,85.2",stroke="#FFFFFF88",w=0.8),
],ach="tenhours",type="artist")

# Gizli ödül — Sihirli palet: ahşap palet, gökkuşağı boyalar, sallanan fırçanın ucunda parıltı
pal_d=("M 100,84 C 104,79.5 113,79 116.5,84 C 119,88 118,95 113,98.5 C 109,101 101,100.5 98.5,96 C 97,93 99.5,91.5 101.5,92 C 103.5,92.5 104.5,90 103,88.5 C 101.5,87.2 99,87 100,84 Z")
dabs=[(106,83.6,"#FF8A8A","#D02A2A"),(111,83.4,"#FFE680","#E0A10F"),(115,87,"#9BF0B4","#22A050"),(115.2,92.6,"#9CC8FF","#2E6FE0"),(110.6,96.8,"#D2B0FF","#7A3CE0"),(104.6,96.6,"#FFFFFF","#C9C4DA")]
brush=[P("M 104,95 L 113.4,71.6",stroke=lin(104,95,113,72,(0,"#E8B07A"),(1,"#8E5A2A")),w=1.7),
       P("M 112.6,73.6 L 114.6,68.6",stroke=SILVER(112,69,115,74),w=2),
       P("M 114.4,69 C 115.2,66.6 116,65 117.2,63.4 C 116.4,65.4 116,67.2 115.4,69.4 Z",fill=lin(114,63,117,69,(0,"#FF6AD5"),(0.5,"#7A5CFF"),(1,"#3EC8FF")))]
item("palette","side","Sihirli palet","Magic palette",[
  E(107.5,101,9.5,1.5,fill="#00000024"),
  P(pal_d+circ(101.6,89.4,1.2),fill=lin(98,80,118,100,(0,"#F2CC96"),(0.5,"#D49A5C"),(1,"#9A6434"))),
  P("M 101.6,83.4 C 105,80.6 112,80.2 115.4,83.4",stroke="#FFFFFF66",w=0.9),
  *[E(x,y,2,1.6,fill=rad(x-0.6,y-0.6,2.4,(0,c1),(1,c2))) for x,y,c1,c2 in dabs],
  *[E(x-0.7,y-0.6,0.6,0.4,fill="#FFFFFFCC") for x,y,c1,c2 in dabs],
  *[A(sh,"sway",7,0.5,p=[104,95]) for sh in brush],
  A(P(sparkle(117.6,61,2.6),fill="#FFFFFF"),"twinkle",1,0.4,p=[117.6,61]),
  A(P(sparkle(112,62.4,1.6),fill="#FFE6FF"),"twinkle",1,0.4,p=[112,62.4],o=0.4),
  A(P(sparkle(118,70,1.4),fill="#CFF4FF"),"twinkle",1,0.4,p=[118,70],o=0.7),
],level=25,type="artist",legendary=True)

# =====================================================================
# KRAL 👑 — monokl, kraliyet bıyığı, kraliyet pelerini, asa; gizli ödül: taç
# =====================================================================
links=[]
for i in range(9):
    t=i/8; x=(1-t)**2*75+2*(1-t)*t*82+t*t*86; y=(1-t)**2*58+2*(1-t)*t*68+t*t*84
    links.append(E(round(x,2),round(y,2),0.9,0.7,stroke=GOLD(x-1,y-1,x+1,y+1),w=0.6))
item("monocle","eyes","Monokl","Monocle",[
  *links,
  E(64,52,11.5,11.5,fill=rad(60,47,14,(0,"#FFFFFF33"),(1,"#FFFFFF0A")),stroke=GOLDR,w=2.8),
  P("M 56,46 C 58,43.4 61,42.4 64,42.4",stroke="#FFFFFF77",w=1.4),
  gem(64,40.4,1.6,*RUBY),
  A(P(sparkle(71,45,2.2),fill="#FFFFFF"),"twinkle",1,0.35,p=[71,45]),
],level=13,type="king")

# Kraliyet bıyığı: ince, uçları yukarı kıvrık; uçlarında altın boncuk
stache=[P("M 50,67.6 C 45,65 40,66 35,67.6 C 30,69.2 26,67 25.5,63.6 C 25.2,61 27.5,59.4 29.6,60.4 C 28,61.6 28,63.6 29.6,64.4 C 31.6,65.4 34,63.6 37,63.6 C 42,63.6 46.6,64 50,65.6 Z",
          fill=lin(0,60,0,68,(0,"#E8C080"),(0.5,"#B07A3E"),(1,"#6E441E")),stroke="#FFE6B0AA",w=0.6),
        P("M 36,64.8 C 40,64.4 45,64.8 48.6,66",stroke="#FFFFFF88",w=0.8),
        gem(29.4,61,1.2,"#FFF6C8","#E8B83A","#9A6516")]
item("royalstache","face","Kraliyet bıyığı","Royal mustache",[*stache,*mirror(stache)],level=14,type="king")

# Kraliyet pelerini: kırmızı kadife omuzlar, benekli beyaz kürk yaka, altın toka
item("ermine","neck","Kraliyet pelerini","Royal cape",[
  P("M 4,106 C 8,93 20,85 34,82.6 L 66,82.6 C 80,85 92,93 96,106 Z",fill=rad(50,86,40,(0,"#E2475E"),(0.6,"#A81E36"),(1,"#4A0A12"))),
  P("M 10,101 C 14,93 22,88 30,86",stroke="#FFFFFF33",w=1.2),
  P("M 14,92.4 C 22,85.4 34,82.4 50,82.4 C 66,82.4 78,85.4 86,92.4 C 80,96.4 70,98 62,96.4 C 58,95.4 54,94.4 50,94.4 C 46,94.4 42,95.4 38,96.4 C 30,98 20,96.4 14,92.4 Z",
    fill=lin(0,82,0,98,(0,"#FFFFFF"),(1,"#DCD6E6"))),
  *[P(f"M {x},{y} L {x-0.8},{y+2.4} L {x+0.8},{y+2.4} Z",fill="#1A1826") for x,y in [(22,89.6),(31,87),(41,86),(59,86),(69,87),(78,89.6),(36,92.2),(64,92.2)]],
  P("M 40,90.6 C 44,92.6 56,92.6 60,90.6",stroke=GOLD(40,90,60,93),w=1.1),
  E(50,91.4,3,3,fill=rad(49,90.4,3.6,(0,"#FFF6C8"),(0.6,"#E8B83A"),(1,"#9A6516"))),
  gem(50,91.4,1.2,*RUBY),
  P("M 18,90 C 26,85.4 36,83.6 46,83.4",stroke="#FFFFFF",w=1),
],level=16,type="king")

# Asa: altın çubuk, tepesinde haçlı altın küre ve yakut, ara sıra parlar
item("scepter","side","Kraliyet asası","Royal scepter",[
  E(104,101.4,5,1.2,fill="#00000026"),
  P("M 103.4,100.4 L 111.4,72.6",stroke=GOLD(103,72,112,101),w=2.4),
  P("M 103.8,98.6 L 110.6,74.4",stroke="#FFFFFF66",w=0.7),
  E(107.6,86,2.2,1.2,fill=GOLD(105,85,110,87)), E(105.2,94.4,2,1.1,fill=GOLD(103,93,107,95)),
  E(103.1,101.2,1.8,1.2,fill=GOLD(101,100,105,102)),
  E(112.2,68.6,4.4,4.4,fill=rad(110.8,67,5.4,(0,"#FFF6C8"),(0.55,"#E8B83A"),(1,"#8A5A12"))),
  P("M 107.9,68.8 C 110,70.4 114.4,70.4 116.5,68.8",stroke="#9A6516",w=0.8),
  P("M 112.2,64.2 L 112.2,59.4 M 110.2,61.2 L 114.2,61.2",stroke=GOLD(110,59,114,64),w=1.5),
  gem(112.2,68.9,1.5,*RUBY),
  A(P(sparkle(116.6,63,2.4),fill="#FFFFFF"),"twinkle",1,0.35,p=[116.6,63]),
],ach="hundred",type="king")

# Gizli ödül — Taç: kadife iç, inciler, mücevherler, arkasında altın ışıltı
crown=[
  A(E(50,3,30,12,fill=rad(50,3,30,(0,"#FFE08A55"),(1,"#FFE08A00"))),"beat",0.08,0.6,p=[50,3]),
  E(50,17,23,2.5,fill=SHADOW),
  P("M 30,12 C 30,1 39,-3 50,-3 C 61,-3 70,1 70,12 Z",fill=rad(44,-1,24,(0,"#E2475E"),(0.6,"#A81E36"),(1,"#5E0F1E"))),
  P("M 28,11 L 26,-1 L 37,6 L 43.5,-4 L 50,-10 L 56.5,-4 L 63,6 L 74,-1 L 72,11 Z",fill=GOLD(28,-10,72,11),stroke="#9A6516",w=0.9),
  P("M 29.5,9 L 28.2,1.6 L 36.4,7.6 M 44.6,-2.8 L 50,-7.8",stroke="#FFFFFF80",w=1.1),
  R(27,10,46,7.5,2.5,fill=lin(0,10,0,17.5,(0,"#FFE786"),(0.5,"#E9B53A"),(1,"#B47A1C")),stroke="#9A6516",sw=0.8),
  *[E(x,10.3,1.15,1.15,fill=rad(x-0.4,9.9,1.5,(0,"#FFFFFF"),(1,"#CFC6DA"))) for x in [31,35,39,43,57,61,65,69]],
  E(50,13.8,3.4,2.8,fill=rad(49,12.8,3.8,(0,"#FFA0A8"),(0.5,"#E5484D"),(1,"#8E1424"))),
  gem(39,13.8,2.2,*SAPPH), gem(61,13.8,2.2,*SAPPH), gem(31.5,13.8,1.6,*EMER), gem(68.5,13.8,1.6,*EMER),
  E(49,12.9,1,0.8,fill="#FFFFFFDD"),
  *[E(x,y,r,r,fill=rad(x-r*0.35,y-r*0.4,r*1.3,(0,"#FFFFFF"),(0.6,"#F2EEF6"),(1,"#BDB4CC"))) for x,y,r in [(26,-1.5,2.4),(50,-10.6,2.7),(74,-1.5,2.4),(37,5.6,1.6),(63,5.6,1.6),(43.5,-4.4,1.5),(56.5,-4.4,1.5)]],
  A(P(sparkle(65,-2,3.2),fill="#FFFFFF"),"twinkle",1,0.35,p=[65,-2]),
  A(P(sparkle(33,2.7,2.4),fill="#FFFFFF"),"twinkle",1,0.35,p=[33,2.7],o=0.5),
  A(P(sparkle(50,-15.5,2),fill="#FFF6C8"),"twinkle",1,0.35,p=[50,-15.5],o=0.25),
]
item("crown","head","Taç","Crown",crown,level=30,type="king",legendary=True)

order={"coder":0,"hipster":1,"police":2,"marketing":3,"artist":4,"king":5}
items.sort(key=lambda d:(order[d["type"]],d.get("legendary",False),d.get("level",0)))
json.dump(items,open(ROOT / 'assets/outfits.json','w',encoding='utf-8'),ensure_ascii=False,indent=1)
print(len(items))
