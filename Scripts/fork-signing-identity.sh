#!/bin/bash
# Creates the `Tinycast Self-Signed` code-signing identity in your login keychain, once.
#
# READ THIS BEFORE YOU RUN IT. It generates a private key, imports it into your login keychain,
# and lets any app use that key without a prompt (`-A`), exactly as docs/signing.md section 1 does.
# The certificate is self-signed and trusted by nothing, so the key can only sign code as this name.
# Remove it later in Keychain Access, under My Certificates, by deleting `Tinycast Self-Signed`.
#
#   ./Scripts/fork-signing-identity.sh

set -euo pipefail

NAME="Tinycast Self-Signed"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
# The system LibreSSL, whose .p12 files `security import` accepts; a Homebrew OpenSSL 3 may not.
OPENSSL=/usr/bin/openssl

if security find-identity -p codesigning | grep -q "$NAME"; then
    echo "✓ '$NAME' already exists. Nothing to do."
    exit 0
fi

WORK="$(mktemp -d)"
chmod 700 "$WORK"
trap 'rm -rf "$WORK"' EXIT
PASS="$("$OPENSSL" rand -hex 16)"

"$OPENSSL" req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "$WORK/key.pem" -out "$WORK/cert.pem" \
    -subj "/CN=$NAME" \
    -addext "basicConstraints=critical,CA:false" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning"

"$OPENSSL" pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
    -name "$NAME" -out "$WORK/identity.p12" -passout "pass:$PASS"

security import "$WORK/identity.p12" -k "$KEYCHAIN" -P "$PASS" -A -T /usr/bin/codesign

if security find-identity -p codesigning | grep "$NAME"; then
    echo "✓ Created '$NAME'. Builds from this fork now sign with it."
else
    echo "✗ The import ran, but '$NAME' is not listed. Check Keychain Access." >&2
    exit 1
fi
