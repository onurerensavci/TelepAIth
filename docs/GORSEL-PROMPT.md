# TelepAIth görsel promptları (ChatGPT / GPT görsel üretimi)

Promptlar İngilizce, çünkü görsel modeller İngilizcede daha tutarlı. Önce turuncu tabloyu üret, sonra aynı sohbette mavi sürümü iste: karakter aynı kalır.

## 1. Karakter tablosu (turuncu, Claude)

```
Create a character sprite sheet for a cute mascot named TelepAIth: a floating robot head. No hat, no body, no arms, no legs: only the head.

Character design: a rounded, boxy off-white robot head with a wide dark glass visor and small lavender bolts on both sides. The eyes are LED dot-matrix displays: each eye is a small grid of tiny glowing dots, with only some dots lit to draw the eye shape, the unlit dots faintly visible. A small glowing status light on the forehead. The head floats in the air with a soft shadow below.

Colors: off-white head, dark charcoal visor, dot-matrix eyes glowing warm terracotta orange (#D97757), golden forehead light.

Style: soft 3D clay / vinyl toy render, smooth matte surfaces, gentle studio lighting, subtle soft shadows on the character itself, no outlines, friendly and charming. The character must look identical in every cell.

Layout: ONE image containing a strict grid of 5 columns × 2 rows with equal-sized cells. Transparent background. No grid lines, no borders, no text, no labels, no floor. Each cell shows the same floating head, centered in its cell, same scale, front view, with some empty margin around it.

Row 1, left to right:
1. idle: calm, gentle eyes, forehead light soft yellow
2. thinking: eyes looking up, faint concentric telepathic rings around the head, forehead light yellow
3. reading: eyes looking down at a small floating glowing spellbook
4. searching: a small magnifying glass floating in front of one eye
5. editing: glowing runes floating around the head

Row 2, left to right:
6. running: focused narrow eyes, small motion lines, forehead light green
7. waiting: big attentive eyes, a small exclamation sparkle, forehead light red
8. done: happy ^ ^ dot-matrix eyes, sparkles around
9. error: X-shaped dot-matrix eyes, a small puff of smoke, forehead light red
10. sleeping: eyes closed as thin lines, small "z" shapes floating

Wide canvas, high resolution (about 2560 × 1024).
```

## 2. Mavi sürüm (GPT)

Aynı sohbette:

```
Make the exact same sprite sheet with the exact same character, poses, layout and transparent background, but change only the dot-matrix eye color to bright blue (#3B82F6). Keep everything else identical.
```

## 3. Uygulama ikonu

```
A macOS app icon for an app named TelepAIth. Show the same cute floating robot head (no hat): off-white rounded head, wide dark glass visor, LED dot-matrix eyes where the left eye glows terracotta orange (#D97757) and the right eye glows bright blue (#3B82F6), a small golden light on the forehead. Centered and large, soft 3D clay / vinyl toy style. Background: a rounded square (macOS squircle) in deep indigo with faint concentric rings and a few tiny sparkles. No text, no letters. 1024 × 1024.
```

## İpuçları

- Hücreler kaymışsa: "Regenerate with a strict 5×2 grid of perfectly equal cells, characters centered in each cell" de.
- Arka plan şeffaf gelmezse: "Return it as a PNG with a fully transparent background" de.
- Tablo tutmazsa her durumu tek tek ürettir ve `idle.png`, `thinking.png`… diye kaydet (dosya adları README'de).
- Kaydettiğin yer: `~/.telepaith/skins/claude/sheet.png` ve `~/.telepaith/skins/gpt/sheet.png`
