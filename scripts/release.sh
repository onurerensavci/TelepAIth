#!/bin/bash
# Yeni sürüm yayınlar: VERSION'ı günceller, commit + etiket atar, GitHub'a gönderir.
# GitHub Actions uygulamayı derleyip Releases'a .zip olarak koyar; açık TelepAIth'ler güncellemeyi görür.
# Kullanım: scripts/release.sh 0.2.0
set -euo pipefail
cd "$(dirname "$0")/.."

NEW="${1:?Kullanım: scripts/release.sh 0.2.0}"
if ! printf '%s' "$NEW" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
  echo "Sürüm 1.2.3 biçiminde olmalı" >&2
  exit 1
fi
if [ -n "$(git status --porcelain)" ]; then
  echo "Önce bekleyen değişiklikleri commit'le (git status temiz olmalı)." >&2
  exit 1
fi

echo "$NEW" > VERSION
git add VERSION
git diff --cached --quiet || git commit -m "Sürüm $NEW"
git tag "v$NEW"
git push origin HEAD
git push origin "v$NEW"

echo "✓ v$NEW gönderildi. Derleme durumu: GitHub'da Actions sekmesi."
