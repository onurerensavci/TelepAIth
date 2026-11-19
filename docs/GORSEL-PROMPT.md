# TelepAIth görsel promptları (ChatGPT / GPT görsel üretimi)

Promptlar İngilizce, çünkü görsel modeller İngilizcede daha tutarlı. Önce turuncu tabloyu üret, sonra aynı sohbette mavi sürümü iste: karakter aynı kalır.

## 1. Karakter tablosu (turuncu, Claude)

```
Create a character sprite sheet for a cute mascot named TelepAIth: a floating robot head wearing a wizard hat. No body, no arms, no legs: only the head and the hat.

Character design: a rounded, boxy off-white robot head with a dark glass visor and two glowing pill-shaped eyes, small lavender bolts on both sides. A tall pointed wizard hat with a wide brim, bending slightly to the right, with a small glowing orb at the tip and a tiny star emblem on the front. The head floats in the air with a soft shadow below.

Colors: wizard hat in purple (#6D5BD0) with a darker purple brim (#4A3CA8) and a golden star, off-white head, dark charcoal visor, eyes glowing warm terracotta orange (#D97757).

Style: soft 3D clay / vinyl toy render, smooth matte surfaces, gentle studio lighting, subtle soft shadows on the character itself, no outlines, friendly and charming. The character must look identical in every cell.

Layout: ONE image containing a strict grid of 5 columns × 2 rows with equal-sized cells. Transparent background. No grid lines, no borders, no text, no labels, no floor. Each cell shows the same floating head with its hat, centered in its cell, same scale, front view, with some empty margin around it.

Row 1, left to right:
1. idle: calm, gentle eyes, orb glowing soft yellow
2. thinking: eyes looking up, faint concentric telepathic rings around the head, orb glowing yellow
3. reading: eyes looking down at a small floating glowing spellbook
4. searching: a small magnifying glass floating in front of one eye
5. editing: glowing runes floating around the head

Row 2, left to right:
6. running: focused narrow eyes, small motion lines, orb glowing green
7. waiting: big attentive eyes, a small exclamation sparkle, orb glowing red
8. done: happy arc-shaped eyes, hat tilted joyfully, sparkles around
9. error: X-shaped eyes, a small puff of smoke from the hat, orb red
10. sleeping: eyes closed as thin lines, hat drooping over one side, small "z" shapes floating

Wide canvas, high resolution (about 2560 × 1024).
```

## 2. Mavi sürüm (GPT)

Aynı sohbette:

```
Make the exact same sprite sheet with the exact same character, poses, layout and transparent background, but change only the eye glow color to bright blue (#3B82F6). The hat stays purple. Keep everything else identical.
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
