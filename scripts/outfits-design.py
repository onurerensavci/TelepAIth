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

item("beanie","head","Bere","Beanie",[
  E(50,26,37,3.4,fill=SHADOW),
  P("M 13,22 C 13,5 30,-3 50,-3 C 70,-3 87,5 87,22 Z",fill=THEME(36,0,52)),
  P("M 30,5 C 29,10 29,15 29,18 M 40,0 C 40,6 40,13 40,18 M 50,-1 L 50,16 M 60,0 C 60,6 60,13 60,18 M 70,5 C 71,10 71,15 71,18",stroke="#00000022",w=2.2),
  P("M 30,5 C 29,10 29,15 29,18 M 40,0 C 40,6 40,13 40,18 M 60,0 C 60,6 60,13 60,18 M 70,5 C 71,10 71,15 71,18",stroke="#FFFFFF22",w=0.8),
  P("M 22,6 C 28,1 38,-1 46,-1",stroke="#FFFFFF55",w=2.5),
  P("M 15,14 L 85,14 C 89,14 91,17 91,20.5 C 91,24 89,27 85,27 L 15,27 C 11,27 9,24 9,20.5 C 9,17 11,14 15,14 Z"+HOLE,fill=CREAM),
  P("M 14,16.5 L 86,16.5",stroke="#FFFFFFAA",w=1.2),
  P("M 18,20 L 18,25 M 24,20 L 24,25 M 30,20 L 30,25 M 36,20 L 36,25 M 64,20 L 64,25 M 70,20 L 70,25 M 76,20 L 76,25 M 82,20 L 82,25",stroke="#B9B0CC88",w=1.4),
  *eyelet(),
  E(50,-3,7,7,fill=rad(47,-6,9,(0,"#FFFFFF"),(0.6,"#F1ECF6"),(1,"#C9C0DA"))),
  E(47.5,-5.5,2,1.5,fill="#FFFFFFCC"),
],level=1)

item("cap","head","Kep","Cap",[
  E(50,29,36,3,fill=SHADOW),
  P("M 58,21 C 76,18 96,19 104,25 C 98,30.5 76,31 58,28.5 Z",fill=lin(58,19,104,30,(0,"theme-dark"),(0.5,"theme"),(1,"theme-dark"))),
  P("M 62,22.5 C 78,20.5 94,21 100,24.5",stroke="#FFFFFF44",w=1.4),
  P("M 13,28.5 C 13,7 30,-1 50,-1 C 70,-1 87,7 87,28.5 Z"+HOLE,fill=THEME(36,4,55)),
  P("M 50,1 L 50,16.5 M 30,4 C 25,11 24,20 24.5,28 M 70,4 C 75,11 76,20 75.5,28",stroke="#00000020",w=1.2),
  P("M 21,10 C 27,3 37,0 45,0",stroke="#FFFFFF60",w=2.6),
  *eyelet(),
  E(50,0.5,3.6,2.4,fill=rad(49,-0.5,4,(0,"theme-light"),(1,"theme-dark"))),
],level=3)

item("headphones","head","Kulaklık","Headphones",[
  P("M 3,44 C 3,-2 97,-2 97,44",stroke=lin(0,0,100,0,(0,"#55516E"),(0.5,"#9894B4"),(1,"#4A4766")),w=6),
  P("M 8,34 C 10,6 90,6 92,34",stroke="#FFFFFF40",w=1.3),
  R(-6,33,16,32,7,fill=lin(-6,33,10,65,(0,"#7E7A9C"),(1,"#3E3B56"))),
  R(90,33,16,32,7,fill=lin(90,33,106,65,(0,"#7E7A9C"),(1,"#3E3B56"))),
  R(-3,36,5,10,2.5,fill="#FFFFFF33"),
  R(93,36,5,10,2.5,fill="#FFFFFF33"),
  R(7,37,5,24,2.5,fill=lin(7,37,12,61,(0,"theme-light"),(1,"theme-dark"))),
  R(88,37,5,24,2.5,fill=lin(88,37,93,61,(0,"theme-light"),(1,"theme-dark"))),
],level=5)

item("tophat","head","Silindir şapka","Top hat",[
  E(50,15.5,30,3.2,fill=SHADOW),
  R(33,-24,34,38,4,fill=lin(33,0,67,0,(0,"#4A4858"),(0.3,"#2A2935"),(0.7,"#1A1922"),(1,"#33313F"))),
  E(50,-24,17,3.2,fill=rad(46,-25,16,(0,"#55536A"),(1,"#2A2935"))),
  R(33,2,34,7,0,fill=lin(33,0,67,0,(0,"theme-light"),(0.4,"theme"),(1,"theme-dark"))),
  P("M 38,-20 L 38,1",stroke="#FFFFFF2A",w=3),
  E(50,13.5,30,4,fill=rad(42,12,30,(0,"#4A4858"),(1,"#14131B"))),
  P("M 24,12.5 C 36,10.5 64,10.5 76,12.5",stroke="#FFFFFF30",w=1),
],level=10)

item("crown","head","Taç","Crown",[
  E(50,16.5,22,2.5,fill=SHADOW),
  P("M 28,16 L 25,-2 L 38,7 L 50,-9 L 62,7 L 75,-2 L 72,16 Z",fill=GOLD(30,-9,70,16),stroke="#A8701A",w=1),
  P("M 30,13 L 28.5,2 L 37,8.5",stroke="#FFFFFF77",w=1.2),
  R(27,10,46,6.5,2,fill=lin(0,10,0,16.5,(0,"#FFE27A"),(1,"#C98D1F")),stroke="#A8701A",sw=0.8),
  E(25,-2,2.8,2.8,fill=rad(24,-3,3,(0,"#FFF6C8"),(1,"#D99A22"))),
  E(50,-9,3,3,fill=rad(49,-10,3.2,(0,"#FFF6C8"),(1,"#D99A22"))),
  E(75,-2,2.8,2.8,fill=rad(74,-3,3,(0,"#FFF6C8"),(1,"#D99A22"))),
  E(50,13.2,3,2.6,fill=rad(49,12.2,3.4,(0,"#FF9AA0"),(0.5,"#E5484D"),(1,"#9E1D2A"))),
  E(38,13.2,2.2,2,fill=rad(37.4,12.5,2.6,(0,"#A8D4FF"),(0.5,"#3E9BFF"),(1,"#1F5FB8"))),
  E(62,13.2,2.2,2,fill=rad(61.4,12.5,2.6,(0,"#A8D4FF"),(0.5,"#3E9BFF"),(1,"#1F5FB8"))),
  E(49.2,12.3,0.9,0.7,fill="#FFFFFFDD"),
],level=20)

item("party","head","Parti şapkası","Party hat",[
  E(50,17,16,2.4,fill=SHADOW),
  P("M 35,16.5 L 65,16.5 L 51,-22 Z",fill=lin(35,0,65,0,(0,"#A48BFF"),(0.45,"#7C5CFF"),(1,"#4E2FC9"))),
  P("M 38.5,7 L 62.5,10 L 60.5,4.5 L 41,2 Z M 44,-6 L 57,-4 L 55,-9 L 46.5,-10 Z",fill="#FFFFFF2E"),
  E(45,11,2.3,2.3,fill=rad(44.3,10.3,2.6,(0,"#FFF3B0"),(1,"#F2B90F"))),
  E(56,2,2,2,fill=rad(55.4,1.4,2.3,(0,"#FFC4D6"),(1,"#E5487A"))),
  E(49,-12,1.7,1.7,fill=rad(48.5,-12.5,2,(0,"#B8FFE6"),(1,"#25B784"))),
  P("M 39,13 L 46,-6",stroke="#FFFFFF55",w=1.6),
  E(51,-22,5,5,fill=rad(49.5,-23.5,6,(0,"#FFF6C2"),(0.6,"#FFD34E"),(1,"#D99A10"))),
  P("M 34.5,16.5 L 65.5,16.5",stroke="#4A2CC0",w=2.2),
],ach="bigday")

item("flower","head","Çiçek","Flower",[
  P("M 73,18 C 77,11 81,7 84,3",stroke=lin(73,18,84,3,(0,"#2F8A4A"),(1,"#5BD07E")),w=2.2),
  P("M 79,11 C 74,9.5 72,6 73,3.5 C 77,3.5 79.5,7 79,11 Z",fill=lin(72,4,80,11,(0,"#7BE29B"),(1,"#2F8A4A"))),
  *[E(85+dx,2+dy,3.8,3.8,fill=rad(85+dx-1,2+dy-1,4.5,(0,"#FFE0EA"),(0.6,"#FF8FB1"),(1,"#E0507F"))) for dx,dy in [(0,-4.6),(4.4,-1.4),(2.7,3.8),(-2.7,3.8),(-4.4,-1.4)]],
  E(85,2,2.8,2.8,fill=rad(84.2,1.2,3.2,(0,"#FFF6C2"),(1,"#F2B00F"))),
  E(84.2,1,0.9,0.7,fill="#FFFFFFCC"),
],ach="streak7")

item("halo","head","Hale","Halo",[
  E(50,-1,23,5,stroke="#FFE08A40",w=7),
  E(50,-1,23,5,stroke=lin(27,0,73,0,(0,"#FFF6C8"),(0.5,"#FFD54A"),(1,"#E0A526")),w=3),
  P("M 33,-4.5 C 40,-6 50,-6.3 58,-5.6",stroke="#FFFFFFCC",w=1),
],ach="hundred")

LENS=lin(0,41,0,62,(0,"#4A4A66"),(0.5,"#16161F"),(1,"#050508"))
item("sunglasses","eyes","Güneş gözlüğü","Sunglasses",[
  P("M 20,46 L 6,46 M 80,46 L 94,46",stroke="#16161E",w=2.4),
  P("M 18.5,40.5 L 47.5,40.5 C 48.8,40.5 49.5,41.5 49.5,43 L 49.5,53 C 49.5,59.5 45.5,62.5 39,62.5 L 28,62.5 C 21.5,62.5 18.5,58.5 18.5,52 Z",fill=LENS,stroke="#000000",w=1.6),
  P("M 81.5,40.5 L 52.5,40.5 C 51.2,40.5 50.5,41.5 50.5,43 L 50.5,53 C 50.5,59.5 54.5,62.5 61,62.5 L 72,62.5 C 78.5,62.5 81.5,58.5 81.5,52 Z",fill=LENS,stroke="#000000",w=1.6),
  P("M 22,45 L 30,44 L 24,56 Z M 54,45 L 62,44 L 56,56 Z",fill="#FFFFFF26"),
  P("M 49.5,44.5 L 50.5,44.5",stroke="#000000",w=3),
  P("M 21,42.5 L 46,42.5 M 54,42.5 L 79,42.5",stroke="#FFFFFF30",w=0.8),
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
  P(heart(36),fill=HFILL(36),stroke="#A0154D",w=1.3),
  P(heart(64),fill=HFILL(64),stroke="#A0154D",w=1.3),
  E(30.5,46,3,2,fill="#FFFFFF77"), E(58.5,46,3,2,fill="#FFFFFF77"),
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
  P("M 103,81 C 101,78 105,77 103,74 M 108,81 C 106,78 110,77 108,74",stroke="#CFC9DCAA",w=1.6),
  P("M 112,87 C 117.5,87 117.5,95.5 112,95.5",stroke=lin(112,87,118,96,(0,"#FFFFFF"),(1,"#B9B0CC")),w=2.4),
  R(100,84,12.5,15.5,3.4,fill=lin(100,0,112.5,0,(0,"#FFFFFF"),(0.5,"#F2EEE8"),(1,"#C9C0D8"))),
  E(106.25,85.4,5.3,1.6,fill=rad(105,85,5,(0,"#9A6438"),(1,"#4A2A14"))),
  P("M 101.8,87.5 L 101.8,97",stroke="#FFFFFFBB",w=1.2),
  R(101.5,90.5,9.5,3,1.5,fill="theme"),
],ach="early")

item("sprout","side","Fidan","Sprout",[
  E(107,100.5,8,1.6,fill="#00000026"),
  P("M 107,88 L 107,77",stroke=lin(106,77,108,88,(0,"#5BD07E"),(1,"#2F8A4A")),w=2.2),
  P("M 107,80 C 101,80 98.5,75 99.5,72.5 C 104,72.5 107,76 107,80 Z",fill=lin(99,72,107,80,(0,"#9BF0B4"),(1,"#2F9A52"))),
  P("M 107,78 C 113,78 115.5,73 114.5,70.5 C 110,70.5 107,74 107,78 Z",fill=lin(107,70,115,78,(0,"#9BF0B4"),(1,"#2F9A52"))),
  P("M 99.5,87.5 L 114.5,87.5 L 112.2,100 L 101.8,100 Z",fill=lin(100,86,114,100,(0,"#8FAAF0"),(0.5,"#5B7DD8"),(1,"#3A55A8"))),
  R(98.5,85,17,3.6,1.4,fill=lin(0,85.5,0,89,(0,"#A4BAF5"),(1,"#4A69BF"))),
  P("M 101,89.5 L 102.5,99",stroke="#FFFFFF44",w=1),
],level=15)

json.dump(items,open(ROOT / 'assets/outfits.json','w',encoding='utf-8'),ensure_ascii=False,indent=1)
print(len(items))
