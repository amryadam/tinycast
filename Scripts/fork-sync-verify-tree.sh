#!/bin/bash
# Checks that a candidate merge commit is exactly the merge it claims to be.
#
#   ./Scripts/fork-sync-verify-tree.sh DEV UPSTREAM CANDIDATE     # run inside the repository
#
# The candidate may have been written by a model that read untrusted upstream text, so nothing is
# taken on trust. It must:
#   - have exactly two parents, DEV first and UPSTREAM second;
#   - leave .github/ exactly as DEV has it;
#   - leave Scripts/fork-* and docs/fork/ exactly as DEV has them;
#   - differ from git's own computed merge (git merge-tree) only in the paths that conflicted,
#     so a clean merge must equal git's result outside .github/, and a resolution may change only
#     what conflicted;
#   - carry no conflict marker in any file it changes;
#   - have no two paths that differ only by case;
#   - hold no symlink or submodule where git's own merge has none.

set -euo pipefail

if [ $# -ne 3 ]; then
    echo "usage: fork-sync-verify-tree.sh DEV UPSTREAM CANDIDATE" >&2
    exit 2
fi

die() {
    echo "✗ $*" >&2
    exit 1
}

dev="$(git rev-parse --verify "$1^{commit}")"
up="$(git rev-parse --verify "$2^{commit}")"
cand="$(git rev-parse --verify "$3^{commit}")"

# shellcheck disable=SC2046 # the line is "commit parent parent ...", and word splitting is wanted
set -- $(git rev-list --parents -n 1 "$cand")
[ $# -eq 3 ] || die "the candidate has $(($# - 1)) parents, not 2"
[ "$2" = "$dev" ] || die "the first parent is not dev"
[ "$3" = "$up" ] || die "the second parent is not upstream"

# On a Mac, two paths that differ only by case are one file, so one could replace a fork script
# that the checks below compare by exact name.
"$(dirname "$0")/fork-check-build-inputs.sh" --paths-only "$cand" > /dev/null || die "the candidate has paths that differ only by case"

[ -z "$(git diff --name-only "$dev" "$cand" -- .github)" ] || die "the candidate changes .github/"
[ -z "$(git diff --name-only "$dev" "$cand" -- 'Scripts/fork-*' docs/fork)" ] \
    || die "the candidate changes the fork's own scripts or docs"

# What git itself makes of the merge. A conflict exits 1, and lists the conflicted paths after the
# tree id, up to a blank line.
if out="$(git merge-tree --write-tree --name-only "$dev" "$up")"; then
    status=0
else
    status=$?
fi
[ "$status" -le 1 ] || die "git could not compute the merge"
baseline="$(sed -n '1p' <<< "$out")"
conflicted="$(sed -n '2,/^$/p' <<< "$out" | sed '/^$/d')"
[ "$status" -eq 1 ] || conflicted=""

while IFS= read -r -d '' path; do
    case "$path" in .github/*) continue ;; esac
    if ! grep -qxF -- "$path" <<< "$conflicted"; then
        die "the candidate differs from git's merge in $path, which did not conflict"
    fi
done < <(git diff --name-only -z "$baseline" "$cand")

# A resolved file stays a plain file: no link out of the repository and no submodule.
if git diff --raw --no-renames "$baseline" "$cand" | awk '{ print $2 }' | grep -qE '^(120000|160000)$'; then
    die "the candidate has a symlink or a submodule where git's merge has none"
fi

# No conflict markers in anything the candidate changed.
while IFS= read -r -d '' path; do
    if git show "$cand:$path" 2> /dev/null | grep -qE '^(<<<<<<<|>>>>>>>) '; then
        die "$path still has a conflict marker"
    fi
done < <(git diff --name-only -z "$dev" "$cand")

echo "✓ the candidate is a faithful merge of upstream into dev"
