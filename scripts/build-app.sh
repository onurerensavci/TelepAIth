#!/bin/bash
# TelepAIth.app'i derler ve build/ klasörüne koyar.
# Gerekli: Xcode Command Line Tools  (xcode-select --install)
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="TelepAIth"
BUNDLE_ID="com.telepaith.app"
VERSION="${VERSION:-$(cat VERSION 2>/dev/null || echo 0.1.0)}"
BUILD_NUMBER="${GITHUB_RUN_NUMBER:-1}"

# Güncellemelerin bakacağı GitHub deposu: Actions'ta otomatik, yerelde git remote'tan
REPO="${GITHUB_REPOSITORY:-}"
if [ -z "$REPO" ]; then
  REMOTE="$(git remote get-url origin 2>/dev/null || true)"
  REPO="$(printf '%s' "$REMOTE" | sed -E 's#^(git@github\.com:|https://github\.com/)##; s#\.git$##')"
fi
if ! printf '%s' "$REPO" | grep -Eq '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'; then
  REPO=""
fi

echo "→ $APP_NAME $VERSION derleniyor… (güncelleme deposu: ${REPO:-yok})"
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

APP="build/$APP_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"

# Uygulama ikonu: hazır .icns varsa onu, yoksa assets/AppIcon.png'den üret
if [ -f "assets/AppIcon.icns" ]; then
  cp "assets/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
elif [ -f "assets/AppIcon.png" ]; then
  SET="build/AppIcon.iconset"
  rm -rf "$SET"
  mkdir -p "$SET"
  for size in 16 32 128 256 512; do
    sips -z $size $size "assets/AppIcon.png" --out "$SET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z $double $double "assets/AppIcon.png" --out "$SET/icon_${size}x${size}@2x.png" >/dev/null
  done
  iconutil -c icns "$SET" -o "$APP/Contents/Resources/AppIcon.icns"
fi

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>TelepAIthUpdateRepo</key><string>$REPO</string>
</dict>
</plist>
EOF

# Yerel imza (bildirim izni için gerekli)
codesign --force --deep --sign - "$APP"

echo "✓ Hazır: $APP"
echo "  Çalıştır: open \"$APP\""
echo "  Kalıcı kurmak için: cp -R \"$APP\" /Applications/"
