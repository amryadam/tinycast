#!/bin/bash
# Checks docs/fork/*.md against what this fork really changes relative to upstream.
#
#   ./Scripts/fork-check.sh
#   FORK_BASE=upstream/dev ./Scripts/fork-check.sh
#
# Fails on a changed file no doc lists (UNLISTED), a listed file that is unchanged (STALE), or a
# hunk in an upstream file with no added line containing FORK( (UNMARKED).

set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

BASE="${FORK_BASE:-upstream/main}"
# Generated and data files cannot carry a comment, so a marker is not asked of them.
UNMARKED_OK="${FORK_UNMARKED_OK:-^Tinycast\.xcodeproj/|\.(xcstrings|json|plist|entitlements)$}"

docs=(docs/fork/*.md)
[ -e "${docs[0]}" ] || {
    echo "fork-check: no docs/fork/*.md" >&2
    exit 2
}
if ! git rev-parse --verify --quiet "$BASE" > /dev/null; then
    echo "fork-check: no such base '$BASE' (add the upstream remote and fetch it)" >&2
    exit 2
fi
MERGE_BASE=$(git merge-base "$BASE" HEAD) || exit 2

# Committed, staged, unstaged and untracked, so it is right before a commit as well as after.
# quotePath off, so a file name with non-ASCII characters is not quoted and never matches the docs.
changed=$({
    git -c core.quotePath=off diff --name-only --no-renames "$MERGE_BASE"
    git -c core.quotePath=off ls-files --others --exclude-standard
} | sort -u)
# The sync pins .github/ to dev's copy (see docs/fork/fork-sync.md), so after an upstream release
# that edits its own workflows or templates, every upstream-owned file there differs from BASE
# without being a fork change. Only the fork's own workflows, .github/workflows/fork-*, stay checked.
changed=$(grep -vE '^\.github/' <<< "$changed"; grep -E '^\.github/workflows/fork-' <<< "$changed")
# Rows of the tables headed `| File |`, each starting with a backticked path: | `path` | ...
listed=$(awk '
    /^\| File \|/ { inside = 1; next }
    !/^\|/ { inside = 0 }
    inside && match($0, /^\| `[^`]+`/) { print substr($0, 4, RLENGTH - 4) }
' "${docs[@]}" | sort -u)

status=0

while IFS= read -r file; do
    [ -z "$file" ] && continue
    if ! grep -qxF "$file" <<< "$listed"; then
        echo "UNLISTED  $file  (changed, but listed in no docs/fork/*.md)"
        status=1
    fi
done <<< "$changed"

while IFS= read -r file; do
    [ -z "$file" ] && continue
    if ! grep -qxF "$file" <<< "$changed"; then
        echo "STALE     $file  (listed in docs/fork, but unchanged)"
        status=1
    fi
done <<< "$listed"

# Every feature doc (a title `# Feature: name`) must be linked from the root README, so a feature
# cannot be added and left out of it. The README's own doc, repo-readme, is the one exception.
for doc in docs/fork/*.md; do
    [ "$(basename "$doc")" = "repo-readme.md" ] && continue
    grep -q '^# Feature:' "$doc" || continue
    if ! grep -qF "($doc)" README.md 2> /dev/null; then
        echo "NOREADME  $doc  (a feature, but README.md does not link it)"
        status=1
    fi
done

# Every hunk of an upstream file we edit must be findable by `grep FORK(`.
while IFS= read -r file; do
    [ -z "$file" ] && continue
    [[ "$file" =~ $UNMARKED_OK ]] && continue
    git cat-file -e "$MERGE_BASE:$file" 2> /dev/null || continue # new in the fork: nothing to mark
    [ -f "$file" ] || continue # deleted by the fork
    git diff -U0 "$MERGE_BASE" -- "$file" | awk -v f="$file" '
        /^@@/ { if (hunk != "" && !marked) { print "UNMARKED  " f "  " hunk; bad = 1 } hunk = $0; marked = 0; next }
        /^\+\+\+/ { next }
        /^\+/ && /FORK\(/ { marked = 1 }
        END { if (hunk != "" && !marked) { print "UNMARKED  " f "  " hunk; bad = 1 } exit bad }
    ' || status=1
done <<< "$changed"

if [ "$status" -eq 0 ]; then
    echo "fork-check: docs/fork matches the diff against $BASE ($(grep -c . <<< "$changed") files)"
fi
exit "$status"
