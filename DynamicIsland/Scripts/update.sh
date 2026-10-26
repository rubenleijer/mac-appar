#!/bin/bash
# Updates Dynamic Island from GitHub: fetches the branch, builds it, signs it with a local
# certificate that stays the same between builds (so Accessibility stays granted), installs it
# in /Applications and relaunches it. Usage: update.sh [owner/repo] [branch]
set -euo pipefail

REPO="${1:-rubenleijer/mac-appar}"
BRANCH="${2:-main}"
SUPPORT="$HOME/Library/Application Support/Dynamic Island"
SRC="$SUPPORT/Source"
IDENTITY="Dynamic Island Local Signing"
APP="/Applications/Dynamic Island.app"
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

mkdir -p "$SUPPORT"
echo "== $(date) – updating from $REPO ($BRANCH)"

if [ -d "$SRC/.git" ]; then
    git -C "$SRC" remote set-url origin "https://github.com/$REPO.git"
    git -C "$SRC" fetch --depth 1 origin "$BRANCH"
    git -C "$SRC" reset --hard FETCH_HEAD
else
    rm -rf "$SRC"
    git clone --depth 1 --branch "$BRANCH" "https://github.com/$REPO.git" "$SRC"
fi

# A self-signed code-signing certificate, created once. macOS ties Accessibility to the
# signature, so a stable one means the permission survives every update.
NEW_IDENTITY=0
if ! security find-certificate -c "$IDENTITY" >/dev/null 2>&1; then
    echo "== creating the local signing certificate"
    TMP="$(mktemp -d)"
    cat > "$TMP/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $IDENTITY
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF
    /usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$TMP/cert.cnf" \
        -keyout "$TMP/key.pem" -out "$TMP/cert.pem" 2>/dev/null
    /usr/bin/openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -name "$IDENTITY" \
        -out "$TMP/identity.p12" -passout pass:dynamicisland
    security import "$TMP/identity.p12" -k "$HOME/Library/Keychains/login.keychain-db" \
        -P dynamicisland -T /usr/bin/codesign
    rm -rf "$TMP"
    NEW_IDENTITY=1
fi

cd "$SRC/DynamicIsland"
SIGN_IDENTITY="$IDENTITY" ./build.sh

echo "== installing"
pkill -x DynamicIsland || true
sleep 0.5
rm -rf "$APP"
ditto "build/Dynamic Island.app" "$APP"

# The first build with the stable certificate needs Accessibility granted once more.
if [ "$NEW_IDENTITY" = 1 ] || [ ! -f "$SUPPORT/.stable-signing" ]; then
    tccutil reset Accessibility com.emresunar.DynamicIsland >/dev/null 2>&1 || true
    touch "$SUPPORT/.stable-signing"
fi

open "$APP"
echo "== done: $(git -C "$SRC" rev-parse --short HEAD)"
