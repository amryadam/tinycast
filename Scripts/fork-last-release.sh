#!/bin/bash
# Prints the tag of the fork's last complete release.
#
#   gh api "repos/OWNER/NAME/releases?per_page=100" | ./Scripts/fork-last-release.sh
#
# The release list is read from standard input as JSON. A release counts only when it is published
# (not a draft, not a prerelease), its tag is MAJOR.MINOR.PATCH-fork.N, and it carries both
# Tinycast-Fork-<version>.zip and Tinycast-Fork-<version>.zip.sha256 for that same version. A tag
# alone does not count, so a tag left behind by a failed publish cannot hide the need for a release.
# The highest by version number is printed. With none, it exits 1 and prints nothing.

set -euo pipefail

if [ $# -ne 0 ]; then
    echo "usage: gh api repos/OWNER/NAME/releases | fork-last-release.sh" >&2
    exit 2
fi

num='(0|[1-9][0-9]*)'
tag_re="^v${num}\\.${num}\\.${num}-fork\\.([1-9][0-9]*)\$"

json="$(cat)"
# Candidates, one tag per line: complete releases only.
tags="$(jq -r '
    if type != "array" then error("not a list of releases") else . end
    | .[]
    | select(.draft == false and .prerelease == false)
    | .tag_name as $tag
    | ($tag | ltrimstr("v")) as $version
    | select(([.assets[].name] | index("Tinycast-Fork-" + $version + ".zip")) != null
        and ([.assets[].name] | index("Tinycast-Fork-" + $version + ".zip.sha256")) != null)
    | $tag' <<< "$json")" || {
    echo "✗ could not read the release list" >&2
    exit 1
}

best=""
best_key=""
while IFS= read -r tag; do
    [[ "$tag" =~ $tag_re ]] || continue
    # Zero-padded fields, so a plain string comparison orders them as numbers.
    key="$(printf '%09d.%09d.%09d.%09d' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}" "${BASH_REMATCH[4]}")"
    if [ -z "$best_key" ] || [[ "$key" > "$best_key" ]]; then
        best="$tag"
        best_key="$key"
    fi
done <<< "$tags"

if [ -z "$best" ]; then
    echo "✗ there is no complete fork release" >&2
    exit 1
fi
echo "$best"
