#!/bin/bash
# Verifies the built fork app and zips it for release.
#
#   ./Scripts/fork-package.sh APP_PATH VERSION OUT_DIR [--require-authority NAME]
#
# VERSION is the full fork version, for example 0.12.11-fork.1. Writes
# OUT_DIR/Tinycast-Fork-VERSION.zip and OUT_DIR/Tinycast-Fork-VERSION.zip.sha256 and prints the
# SHA-256 on standard output, and nothing else there. Nothing is written when a check fails.
#
# The zip holds Tinycast Fork.app, LICENSE, NOTICE.md and a FORK-NOTICE.md at its root, so the licence
# text, the notice of modification and the source link travel with the binary. FORK_BUNDLE_ID overrides the expected bundle id, as it does for fork-build.sh.

set -euo pipefail
# The repository root, found without changing directory, so a relative APP_PATH or OUT_DIR keeps
# meaning what the caller meant.
HERE="$(cd "$(dirname "$0")/.." && pwd)"

die() {
    echo "✗ $*" >&2
    exit 1
}

if [ $# -ne 3 ] && [ $# -ne 5 ]; then
    echo "usage: fork-package.sh APP_PATH VERSION OUT_DIR [--require-authority NAME]" >&2
    exit 2
fi
APP="$1"
VERSION="$2"
OUT_DIR="$3"
AUTHORITY=""
if [ $# -eq 5 ]; then
    [ "$4" = "--require-authority" ] || die "unknown option '$4'"
    AUTHORITY="$5"
fi

APP_NAME="${FORK_APP_NAME:-Tinycast Fork}"
BUNDLE_ID="${FORK_BUNDLE_ID:-com.amryadam.tinycast}"
BASE_VERSION="$("$HERE/Scripts/fork-release-validate.sh" "$VERSION")"

[ -d "$APP" ] || die "no app at $APP"
[ "$(basename "$APP")" = "$APP_NAME.app" ] || die "the app is named $(basename "$APP"), expected $APP_NAME.app"

PLIST="$APP/Contents/Info.plist"
[ -f "$PLIST" ] || die "no Info.plist in $APP"
BUILT_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$PLIST")"
[ "$BUILT_ID" = "$BUNDLE_ID" ] || die "bundle id is '$BUILT_ID', expected '$BUNDLE_ID'"
BUILT_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")"
[ "$BUILT_VERSION" = "$BASE_VERSION" ] || die "app version is '$BUILT_VERSION', expected '$BASE_VERSION'"

codesign --verify --deep --strict "$APP" 2> /dev/null || die "the signature of $APP does not verify"
if [ -n "$AUTHORITY" ]; then
    # Captured first, so no pipe closes early on codesign's output.
    INFO="$(codesign -dvv "$APP" 2>&1)"
    FIRST="$(sed -n 's/^Authority=//p' <<< "$INFO" | sed -n '1p')"
    [ "$FIRST" = "$AUTHORITY" ] || die "signed by '${FIRST:-nobody (ad-hoc or unsigned)}', expected '$AUTHORITY'"
fi

STAGE="$(mktemp -d)"
CHECK="$(mktemp -d)"
trap 'rm -rf "$STAGE" "$CHECK"' EXIT

ditto "$APP" "$STAGE/$APP_NAME.app"
cp "$HERE/LICENSE" "$HERE/NOTICE.md" "$STAGE/"

# The AGPL wants the notice of modification, and where the source is, next to the object code.
REPO="${FORK_REPO:-amryadam/tinycast}"
[[ "$REPO" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || die "FORK_REPO '$REPO' is not of the form OWNER/NAME"
UPSTREAM_COMMIT="$(git -C "$HERE" merge-base origin/main HEAD 2> /dev/null \
    || git -C "$HERE" merge-base upstream/main HEAD 2> /dev/null || echo "not recorded")"
cat > "$STAGE/FORK-NOTICE.md" <<NOTICE
# Tinycast Fork $VERSION

This is an unofficial, modified version of Tinycast by Abue Ammar.
It is not affiliated with or supported by the upstream project.
Built on $(date -u +%Y-%m-%d) from upstream commit $UPSTREAM_COMMIT.

The complete source of this build is at https://github.com/$REPO/tree/v$VERSION.
It is licensed under the AGPL-3.0-or-later; see LICENSE.
NOTICE

mkdir -p "$OUT_DIR"
ZIP_NAME="Tinycast-Fork-$VERSION.zip"
ZIP="$OUT_DIR/$ZIP_NAME"
ditto -c -k --sequesterRsrc "$STAGE" "$ZIP"

# The unpacked copy must still verify, as the user's copy will after Homebrew unpacks it.
ditto -x -k "$ZIP" "$CHECK"
if ! codesign --verify --deep --strict "$CHECK/$APP_NAME.app" 2> /dev/null; then
    rm -f "$ZIP"
    die "the signature broke in the zip"
fi

SUM="$(shasum -a 256 "$ZIP" | cut -d' ' -f1)"
echo "$SUM  $ZIP_NAME" > "$ZIP.sha256"
echo "$SUM"
