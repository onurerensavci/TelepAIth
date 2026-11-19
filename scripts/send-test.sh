#!/bin/bash
# Robota elle olay gönderir. Kendi AI aracını bağlarken örnek olsun diye.
# Kullanım: scripts/send-test.sh [kaynak] [durum] [metin]
#   scripts/send-test.sh gemini running "Testleri çalıştırıyor"
#   scripts/send-test.sh gemini done "Hepsi geçti"
SOURCE="${1:-gemini}"
STATE="${2:-running}"
TEXT="${3:-Deneme olayı}"
PORT=$(cat "$HOME/.telepaith/port" 2>/dev/null || echo 19850)

curl -s -H 'Content-Type: application/json' \
  --data-binary "{\"state\": \"$STATE\", \"text\": \"$TEXT\", \"project\": \"deneme\"}" \
  "http://127.0.0.1:$PORT/event?source=$SOURCE"
echo
