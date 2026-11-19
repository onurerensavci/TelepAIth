#!/bin/bash
# TelepAIth için kalıcı imza sertifikası oluşturur ve GitHub'a gizli değer olarak kaydeder.
# Böylece her güncelleme aynı imzayla gelir; macOS Erişilebilirlik iznini her seferinde sıfırlamaz.
# Bir kere çalıştırman yeterli. Gerekli: gh (kişisel hesabınla giriş yapılmış).
#
#   curl -fsSL https://raw.githubusercontent.com/onurerensavci/TelepAIth/main/scripts/setup-signing.sh | bash
set -euo pipefail

REPO="${TELEPAITH_REPO:-onurerensavci/TelepAIth}"
NAME="TelepAIth Self Signed"

command -v gh >/dev/null || { echo "gh gerekli: brew install gh" >&2; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "Önce GitHub'a giriş yap: gh auth login" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cd "$WORK"

cat > cert.cnf <<'EOF'
[ req ]
distinguished_name = dn
x509_extensions = ext
prompt = no
[ dn ]
CN = TelepAIth Self Signed
[ ext ]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF

# macOS'un kendi openssl'i (LibreSSL): üretilen .p12 macOS'un anahtarlığına sorunsuz girer
OPENSSL=/usr/bin/openssl
"$OPENSSL" req -x509 -newkey rsa:2048 -nodes -keyout key.pem -out cert.pem -days 3650 -config cert.cnf 2>/dev/null
PASS="$("$OPENSSL" rand -hex 16)"
"$OPENSSL" pkcs12 -export -inkey key.pem -in cert.pem -out cert.p12 -name "$NAME" \
  -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 -passout "pass:$PASS"

base64 < cert.p12 | tr -d '\n' | gh secret set MACOS_CERT_P12 -R "$REPO"
printf '%s' "$PASS" | gh secret set MACOS_CERT_PASSWORD -R "$REPO"

echo "✓ İmza sertifikası $REPO deposuna kaydedildi. Bundan sonraki sürümler bu imzayla gelecek."
