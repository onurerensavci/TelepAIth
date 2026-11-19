#!/bin/bash
# GPT'nin çizdiği 1024×1024 PNG'den macOS uygulama ikonu üretir.
# Kullanım: scripts/make-icon.sh ikon.png   → assets/AppIcon.icns
set -euo pipefail
cd "$(dirname "$0")/.."

SRC="${1:?Kullanım: scripts/make-icon.sh ikon.png}"
SET="build/AppIcon.iconset"
rm -rf "$SET"
mkdir -p "$SET" assets

for size in 16 32 128 256 512; do
  sips -z $size $size "$SRC" --out "$SET/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z $double $double "$SRC" --out "$SET/icon_${size}x${size}@2x.png" >/dev/null
done

iconutil -c icns "$SET" -o assets/AppIcon.icns
echo "✓ assets/AppIcon.icns hazır. Şimdi scripts/build-app.sh çalıştır."
