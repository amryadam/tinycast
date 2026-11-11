#!/bin/bash
# Merges upstream into dev, keeping dev's .github/ exactly as it is.
#
#   ./Scripts/fork-sync-merge.sh DEV_REF UPSTREAM_REF     # run inside the repository, on DEV_REF
#
# Exit 0 and prints the merge commit when the merge is clean. Exit 10 when it conflicts: dev is
# left untouched, the conflicted files (markers included) are saved as a commit on
# refs/fork-sync/conflicted, and the conflicted paths are printed. Exit 3 when upstream is already
# in dev.
#
# .github/ is pinned to dev's version because any workflow file on dev could name the signing
# environment and read the key. An upstream edit to a workflow, a new workflow, and even a
# conflict inside .github/ are all resolved by keeping dev's version.
# A conflict in project.pbxproj is resolved by taking upstream's file and running `xcodegen
# generate`, as docs/fork/README.md says, when xcodegen is available and project.yml is not itself
# in conflict.

set -euo pipefail

if [ $# -ne 2 ]; then
    echo "usage: fork-sync-merge.sh DEV_REF UPSTREAM_REF" >&2
    exit 2
fi

dev="$(git rev-parse --verify "$1^{commit}")"
up="$(git rev-parse --verify "$2^{commit}")"
[ "$(git rev-parse HEAD)" = "$dev" ] || {
    echo "✗ HEAD is not $1; check out dev first." >&2
    exit 2
}
[ -z "$(git status --porcelain)" ] || {
    echo "✗ the work tree is not clean." >&2
    exit 2
}

if git merge-base --is-ancestor "$up" "$dev"; then
    echo "Upstream is already merged." >&2
    exit 3
fi

unmerged() { git diff --name-only --diff-filter=U; }

git merge --no-ff --no-commit "$up" > /dev/null 2>&1 || true

# Pin .github/ to dev: restore what dev has (which also clears a conflict there), and remove what
# dev lacks.
if git ls-tree -r --name-only "$dev" -- .github | grep -q .; then
    git checkout "$dev" -- .github
fi
while IFS= read -r -d '' file; do
    if [ -z "$(git ls-tree --name-only "$dev" -- "$file")" ]; then
        git rm -q -f --ignore-unmatch -- "$file"
    fi
done < <(git ls-files -z --deduplicate -- .github)

pbx=Tinycast.xcodeproj/project.pbxproj
if unmerged | grep -qx "$pbx" && ! unmerged | grep -qx project.yml && command -v xcodegen > /dev/null; then
    git checkout --theirs -- "$pbx"
    xcodegen generate > /dev/null 2>&1 || true
    git add -- "$pbx"
fi

conflicts="$(unmerged)"
if [ -n "$conflicts" ]; then
    git add -A
    tree="$(git write-tree)"
    saved="$(git commit-tree -p "$dev" -p "$up" -m "Conflicted merge, saved for resolution" "$tree")"
    git update-ref refs/fork-sync/conflicted "$saved"
    git merge --abort
    git reset -q --hard "$dev"
    git clean -fdq
    printf '%s\n' "$conflicts"
    exit 10
fi

git commit -q -m "Merge upstream into dev" -m "Merged by the upstream sync. .github/ is kept as dev has it."
git rev-parse HEAD
