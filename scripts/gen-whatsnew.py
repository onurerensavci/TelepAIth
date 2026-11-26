#!/usr/bin/env python3
"""assets/whatsnew.json → Mac ve Windows'un gömülü kopyaları ve sürüm notları.
Her sürümde en üste yeni maddeleri ekle, sonra: python3 scripts/gen-whatsnew.py
Robot güncellemeden sonra ilk maddeyi söyler; release.yml notları buradan yazar (--notes <sürüm>)."""
import json, pathlib, sys

root = pathlib.Path(__file__).resolve().parent.parent
entries = json.loads((root / "assets/whatsnew.json").read_text(encoding="utf-8"))

if len(sys.argv) == 3 and sys.argv[1] == "--notes":
    # Sürüm notu: uygulama "<!-- tr -->" / "<!-- en -->" bölümlerini okuyup robotun balonunda gösterir
    version = sys.argv[2].lstrip("v")
    e = next((x for x in entries if x["version"] == version), None)
    if e:
        print("## Yenilikler\n<!-- tr -->\n" + "\n".join("- " + i for i in e["tr"]) +
              "\n\n## What's new\n<!-- en -->\n" + "\n".join("- " + i for i in e["en"]) + "\n<!-- end -->\n")
    sys.exit(0)

text = json.dumps(entries, ensure_ascii=False, separators=(",", ":"))
assert '"##' not in text and '"""' not in text
swift = ("// Bu dosya scripts/gen-whatsnew.py ile assets/whatsnew.json'dan üretilir; elle değiştirme.\n\n"
         "enum WhatsNewData {\n    static let json = ##\"" + text + "\"##\n}\n")
(root / "Sources/TelepAIth/WhatsNewData.swift").write_text(swift, encoding="utf-8")
cs = ("// Bu dosya scripts/gen-whatsnew.py ile assets/whatsnew.json'dan üretilir; elle değiştirme.\n\n"
      "namespace TelepAIth.Core;\n\npublic static class WhatsNewData\n{\n    public const string Json = \"\"\"\n"
      + text + "\n\"\"\";\n}\n")
(root / "windows/TelepAIth.Core/WhatsNewData.cs").write_text(cs, encoding="utf-8")
print(f"{len(entries)} sürüm yazıldı")
