#!/bin/bash
# Prints the release notes of a fork release, with what the AGPL-3.0-or-later asks of a modified copy.
#
#   ./Scripts/fork-release-notes.sh VERSION UPSTREAM_SHA REPO > notes.md
#
# VERSION is like 0.12.11-fork.1, UPSTREAM_SHA the 40-digit upstream commit this release is based on
# (the merge base with upstream's main), and REPO the fork as OWNER/NAME. Every argument is checked
# before it is put in a link or a command line.

set -euo pipefail
cd "$(dirname "$0")/.." || exit 1

if [ $# -ne 3 ]; then
    echo "usage: fork-release-notes.sh VERSION UPSTREAM_SHA REPO" >&2
    exit 2
fi
VERSION="$1"
SHA="$2"
REPO="$3"

./Scripts/fork-release-validate.sh "$VERSION" > /dev/null
[[ "$SHA" =~ ^[0-9a-f]{40}$ ]] || {
    echo "✗ '$SHA' is not a 40-digit commit id." >&2
    exit 1
}
[[ "$REPO" =~ ^([A-Za-z0-9_.-]+)/[A-Za-z0-9_.-]+$ ]] || {
    echo "✗ '$REPO' is not of the form OWNER/NAME." >&2
    exit 1
}
OWNER="${BASH_REMATCH[1]}"

TAG="v$VERSION"
UPSTREAM="https://github.com/abue-ammar/tinycast"
FORK="https://github.com/$REPO"
TODAY="$(date -u +%Y-%m-%d)"

cat <<NOTES
**This is an unofficial, modified version of Tinycast by Abue Ammar.**
It is not affiliated with, endorsed by or supported by the upstream project.
Please do not report problems with it to the upstream project.
Built on $TODAY from upstream commit [$SHA]($UPSTREAM/commit/$SHA).

## What is different

The fork carries these features on top of upstream:

NOTES

for doc in docs/fork/*.md; do
    title="$(sed -n 's/^# Feature: *//p' "$doc" | sed -n '1p')"
    [ -n "$title" ] || continue
    echo "- [$title]($FORK/blob/$TAG/$doc)"
done

cat <<NOTES

## Install

    brew tap $OWNER/fork
    brew trust --cask $OWNER/fork/tinycast-fork
    brew install --cask $OWNER/fork/tinycast-fork

Homebrew refuses to load a cask from a tap you have not trusted, so read the cask first and then trust it as above.

This build is signed with a self-signed certificate and is not notarised.
macOS may refuse the first launch.
If it does, open System Settings, then Privacy & Security, and choose Open Anyway for Tinycast Fork.

## Licence and source

This is a modified version of Tinycast, copyright Abue Ammar, and is licensed under the AGPL-3.0-or-later.
The complete source of exactly this build is at [$TAG]($FORK/tree/$TAG).
The licence text is [LICENSE]($FORK/blob/$TAG/LICENSE), and it is also inside the zip.
NOTES
