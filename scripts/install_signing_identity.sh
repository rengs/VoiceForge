#!/usr/bin/env bash
set -euo pipefail

IDENTITY_NAME="VoiceForge Local Code Signing"
LOGIN_KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -p codesigning "$LOGIN_KEYCHAIN" 2>/dev/null |
    grep -Fq "\"$IDENTITY_NAME\""; then
  echo "已存在 ${IDENTITY_NAME}。"
  exit 0
fi

SIGNING_TEMP_DIR="$(mktemp -d)"
PRIVATE_KEY="$SIGNING_TEMP_DIR/private-key.pem"
CERTIFICATE="$SIGNING_TEMP_DIR/certificate.pem"
IDENTITY_BUNDLE="$SIGNING_TEMP_DIR/identity.p12"
IDENTITY_PASSWORD="$(openssl rand -hex 24)"

cleanup() {
  unlink "$PRIVATE_KEY" 2>/dev/null || true
  unlink "$CERTIFICATE" 2>/dev/null || true
  unlink "$IDENTITY_BUNDLE" 2>/dev/null || true
  rmdir "$SIGNING_TEMP_DIR" 2>/dev/null || true
}
trap cleanup EXIT

openssl req \
  -x509 \
  -newkey rsa:2048 \
  -sha256 \
  -days 3650 \
  -nodes \
  -keyout "$PRIVATE_KEY" \
  -out "$CERTIFICATE" \
  -subj "/CN=$IDENTITY_NAME/O=VoiceForge/OU=Local Development" \
  -addext "basicConstraints=critical,CA:FALSE" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=codeSigning" \
  >/dev/null 2>&1

openssl pkcs12 \
  -export \
  -out "$IDENTITY_BUNDLE" \
  -inkey "$PRIVATE_KEY" \
  -in "$CERTIFICATE" \
  -name "$IDENTITY_NAME" \
  -passout "pass:$IDENTITY_PASSWORD" \
  >/dev/null 2>&1

security import "$IDENTITY_BUNDLE" \
  -k "$LOGIN_KEYCHAIN" \
  -f pkcs12 \
  -P "$IDENTITY_PASSWORD" \
  -x \
  -T /usr/bin/codesign \
  >/dev/null

if ! security find-identity -p codesigning "$LOGIN_KEYCHAIN" 2>/dev/null |
    grep -Fq "\"$IDENTITY_NAME\""; then
  echo "本机代码签名身份创建失败。" >&2
  exit 1
fi

echo "已创建 ${IDENTITY_NAME}，用于保持 macOS 权限授权。"
