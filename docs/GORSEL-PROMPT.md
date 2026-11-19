# TelepAIth görsel promptları (ChatGPT / GPT görsel üretimi)

Promptlar İngilizce, çünkü görsel modeller İngilizcede daha tutarlı. Önce turuncu tabloyu üret, sonra aynı sohbette mavi sürümü iste: karakter aynı kalır.

## 1. Karakter tablosu (turuncu, Claude)

```
Create a character sprite sheet for a cute mascot named TelepAIth: a small robot-wizard hybrid.

Character design: chibi proportions. A rounded, boxy robot head with a dark glass visor and two glowing pale-cyan pill-shaped eyes. A tall pointed wizard hat that bends slightly to the right, with a small glowing orb at the tip and a tiny star emblem on the front. A short flowing wizard robe with a thin off-white trim at the hem. A small dark chest screen on the robe. Small mitten-like robot hands, little round feet peeking out under the robe. Small metal bolts on the sides of the head.

Colors: hat and robe in warm terracotta orange (#D97757), hands, feet and hat brim in a darker shade of the same orange, off-white trim, dark charcoal visor.

Style: soft 3D clay / vinyl toy render, smooth matte surfaces, gentle studio lighting, subtle soft shadows on the character itself, no outlines, friendly and charming. The character must look identical in every cell.

Layout: ONE image containing a strict grid of 5 columns × 2 rows with equal-sized cells. Transparent background. No grid lines, no borders, no text, no labels, no floor. Each cell shows the same character, full body, centered in its cell, same scale, feet on the same baseline, 3/4 view facing right, with some empty margin around the character.

Row 1, left to right:
1. idle: standing relaxed, slight smile, orb glowing soft white
2. thinking: looking up, one hand near the chin, faint concentric telepathic rings around the head, orb glowing yellow
3. reading: holding a small open glowing spellbook, eyes looking down at it
4. searching: peering through a small magnifying glass
5. editing: typing glowing runes in the air with both hands

Row 2, left to right:
6. running: mid-stride, robe flowing behind, a small magic spark from one hand, orb glowing green
7. waiting: waving one hand high, attentive wide eyes, orb glowing red
8. done: jumping happily with both arms up, happy arc-shaped eyes, small sparkles around
9. error: slumped shoulders, X-shaped eyes, a small puff of smoke from the hat, orb red
10. sleeping: sitting down, eyes closed as thin lines, hat drooping, small "z" shapes floating

Wide canvas, high resolution (about 2560 × 1024).
```

## 2. Mavi sürüm (GPT)

Aynı sohbette:

```
Make the exact same sprite sheet with the exact same character, poses, layout and transparent background, but change the main color of the hat and robe to bright blue (#3B82F6) and the darker parts to a deeper navy blue. Keep everything else identical.
```

## 3. Uygulama ikonu

```
A macOS app icon for an app named TelepAIth. Show the head and pointed wizard hat of the same cute robot-wizard mascot (dark glass visor, two glowing pale-cyan eyes, hat with a glowing orb at the tip), centered and large, in the same soft 3D clay / vinyl toy style. Background: a rounded square (macOS squircle) in a deep indigo color with a soft magical glow and a few tiny sparkles. The hat is half terracotta orange (#D97757) and half bright blue (#3B82F6), split diagonally. No text, no letters. 1024 × 1024.
```

## İpuçları

- Hücreler kaymışsa: "Regenerate with a strict 5×2 grid of perfectly equal cells, characters centered in each cell" de.
- Arka plan şeffaf gelmezse: "Return it as a PNG with a fully transparent background" de.
- Tablo tutmazsa her durumu tek tek ürettir ve `idle.png`, `thinking.png`… diye kaydet (dosya adları README'de).
- Kaydettiğin yer: `~/.telepaith/skins/claude/sheet.png` ve `~/.telepaith/skins/gpt/sheet.png`
