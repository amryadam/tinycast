#!/bin/bash
# Checks that an installed copy of the previous release would accept the new app as an update.
#
#   ./Scripts/fork-check-update-path.sh NEW_APP PREVIOUS_ZIP
#
# The in-app updater installs a downloaded bundle only when it satisfies the running copy's own
# designated requirement, which for a self-signed build pins the certificate. If the signing
# identity changes, every installed copy would refuse the update, so a release is refused here
# first. The zip is expanded in a temporary folder and never executed.

set -euo pipefail

if [ $# -ne 2 ]; then
    echo "usage: fork-check-update-path.sh NEW_APP PREVIOUS_ZIP" >&2
    exit 2
fi
NEW_APP="$1"
PREVIOUS_ZIP="$2"

die() {
    echo "✗ $*" >&2
    exit 1
}

[ -d "$NEW_APP" ] || die "no app at $NEW_APP"
[ -f "$PREVIOUS_ZIP" ] || die "no previous zip at $PREVIOUS_ZIP"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/fork-update-path.XXXXXXXX")"
trap 'rm -rf "$WORK"' EXIT
ditto -x -k "$PREVIOUS_ZIP" "$WORK"

PREVIOUS_APP=""
for candidate in "$WORK"/*.app; do
    [ -d "$candidate" ] && PREVIOUS_APP="$candidate" && break
done
[ -n "$PREVIOUS_APP" ] || die "the previous zip holds no app"

# The requirement the installed copy enforces, read from its signature.
INFO="$(codesign -d -r- "$PREVIOUS_APP" 2>&1)"
REQUIREMENT="$(sed -n 's/^designated => //p' <<< "$INFO" | sed -n '1p')"
[ -n "$REQUIREMENT" ] || die "the previous app has no designated requirement"

if codesign --verify --strict --deep -R="$REQUIREMENT" "$NEW_APP" 2> /dev/null; then
    echo "✓ the new app satisfies the previous release's requirement"
else
    die "the new app does not satisfy the previous release's requirement ($REQUIREMENT). Installed copies would refuse this update."
fi
