#!/bin/bash
# Builds the fork as its own app: its own bundle id and link scheme, and the name Tinycast Fork.
#
#   ./Scripts/fork-build.sh                  # Release
#   ./Scripts/fork-build.sh Debug
#   ./Scripts/fork-build.sh --print-settings # print the build settings and stop, no build
#
# Overrides, all optional: FORK_BUNDLE_ID, FORK_URL_SCHEME, FORK_APP_NAME, FORK_BUILD_DIR,
# FORK_VERSION (the app's marketing version) and FORK_BUILD_NUMBER.
# Upstream's release workflow overrides TINYCAST_BUNDLE_IDENTIFIER and PRODUCT_NAME the same way,
# so no upstream file changes. A bundle id upstream does not know is a development channel,
# which never updates itself, so an upstream release cannot replace this build.

set -euo pipefail
cd "$(dirname "$0")/.." || exit 1
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

PRINT_SETTINGS=0
CONFIG=Release
for arg in "$@"; do
    case "$arg" in
        --print-settings) PRINT_SETTINGS=1 ;;
        *) CONFIG="$arg" ;;
    esac
done
BUNDLE_ID="${FORK_BUNDLE_ID:-com.amryadam.tinycast}"
URL_SCHEME="${FORK_URL_SCHEME:-tinycast-amryadam}"
APP_NAME="${FORK_APP_NAME:-Tinycast Fork}"
IDENTITY="Tinycast Self-Signed"
DERIVED="${FORK_BUILD_DIR:-$HOME/Library/Caches/tinycast-fork/DerivedData}"

# What the build overrides, one per line, so a test can read it without building.
SETTINGS=(
    "PRODUCT_NAME=$APP_NAME"
    "TINYCAST_BUNDLE_IDENTIFIER=$BUNDLE_ID"
    "TINYCAST_URL_SCHEME=$URL_SCHEME"
)
[ -n "${FORK_VERSION:-}" ] && SETTINGS+=("MARKETING_VERSION=$FORK_VERSION")
[ -n "${FORK_BUILD_NUMBER:-}" ] && SETTINGS+=("CURRENT_PROJECT_VERSION=$FORK_BUILD_NUMBER")

if [ "$PRINT_SETTINGS" -eq 1 ]; then
    printf '%s\n' "${SETTINGS[@]}"
    exit 0
fi

if ! security find-identity -p codesigning | grep -q "$IDENTITY"; then
    echo "✗ '$IDENTITY' code-signing identity not found. Run ./Scripts/fork-signing-identity.sh once." >&2
    exit 1
fi

echo "▸ Building $APP_NAME ($CONFIG) as $BUNDLE_ID"
xcodebuild -project Tinycast.xcodeproj -scheme Tinycast -configuration "$CONFIG" \
    -derivedDataPath "$DERIVED" \
    CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$IDENTITY" OTHER_CODE_SIGN_FLAGS="--timestamp=none" \
    "${SETTINGS[@]}" \
    build

APP="$DERIVED/Build/Products/$CONFIG/$APP_NAME.app"
BUILT_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")"
if [ "$BUILT_ID" != "$BUNDLE_ID" ]; then
    echo "✗ The build has bundle id '$BUILT_ID', expected '$BUNDLE_ID'." >&2
    exit 1
fi
codesign --verify --deep --strict "$APP"

echo "✓ $APP"
echo "  bundle id  $BUILT_ID"
echo "  signed by  $(codesign -dvv "$APP" 2>&1 | sed -n 's/^Authority=//p' | head -1)"
