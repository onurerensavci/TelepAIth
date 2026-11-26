#!/usr/bin/env python3
"""assets/outfits.json → Mac ve Windows'un gömülü kopyaları (iki platform aynı gardırobu çizer).
Gardırobu değiştirince çalıştır: python3 scripts/gen-outfits.py"""
import json, pathlib

root = pathlib.Path(__file__).resolve().parent.parent
items = json.loads((root / "assets/outfits.json").read_text(encoding="utf-8"))
text = json.dumps(items, ensure_ascii=False, separators=(",", ":"))
assert '"##' not in text and '"""' not in text

swift = ("// Bu dosya scripts/gen-outfits.py ile assets/outfits.json'dan üretilir; elle değiştirme.\n\n"
         "enum OutfitData {\n    static let json = ##\"" + text + "\"##\n}\n")
(root / "Sources/TelepAIth/OutfitData.swift").write_text(swift, encoding="utf-8")

cs = ("// Bu dosya scripts/gen-outfits.py ile assets/outfits.json'dan üretilir; elle değiştirme.\n\n"
      "namespace TelepAIth.Core;\n\npublic static class OutfitData\n{\n    public const string Json = \"\"\"\n"
      + text + "\n\"\"\";\n}\n")
(root / "windows/TelepAIth.Core/OutfitData.cs").write_text(cs, encoding="utf-8")
print(f"{len(items)} parça yazıldı")
