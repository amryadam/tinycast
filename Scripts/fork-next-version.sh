#!/bin/bash
# Prints the next fork release version.
#
#   ./Scripts/fork-next-version.sh UPSTREAM_LATEST_BASE [FORK_TAG...]
#
# UPSTREAM_LATEST_BASE is the version of upstream's latest release, like 0.12.12, and each FORK_TAG
# is an existing tag like v0.12.11-fork.4. The base used is the higher of upstream's and the
# highest base among the tags, so the result is always above every existing fork tag. The number
# is one more than the highest for that base, or 1.

set -euo pipefail

if [ $# -lt 1 ]; then
    echo "usage: fork-next-version.sh UPSTREAM_LATEST_BASE [FORK_TAG...]" >&2
    exit 2
fi

die() {
    echo "✗ $*" >&2
    exit 1
}

num='(0|[1-9][0-9]*)'
base_re="^$num\\.$num\\.$num\$"
tag_re="^v($num\\.$num\\.$num)-fork\\.([1-9][0-9]*)\$"

[[ "$1" =~ $base_re ]] || die "'$1' is not a version like 0.12.12"
upstream="$1"
shift

# greater A B: succeeds when base A is higher than base B, comparing each field as a number.
greater() {
    local a b i
    IFS=. read -r -a a <<< "$1"
    IFS=. read -r -a b <<< "$2"
    for i in 0 1 2; do
        if [ "${a[$i]}" -gt "${b[$i]}" ]; then return 0; fi
        if [ "${a[$i]}" -lt "${b[$i]}" ]; then return 1; fi
    done
    return 1
}

top="$upstream"
for tag in "$@"; do
    [[ "$tag" =~ $tag_re ]] || die "'$tag' is not a fork tag like v0.12.11-fork.4"
    if greater "${BASH_REMATCH[1]}" "$top"; then top="${BASH_REMATCH[1]}"; fi
done

highest=0
for tag in "$@"; do
    [[ "$tag" =~ $tag_re ]]
    if [ "${BASH_REMATCH[1]}" = "$top" ] && [ "${BASH_REMATCH[5]}" -gt "$highest" ]; then
        highest="${BASH_REMATCH[5]}"
    fi
done

echo "$top-fork.$((highest + 1))"
