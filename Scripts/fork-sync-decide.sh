#!/bin/bash
# Decides whether the fork needs a new release.
#
#   ./Scripts/fork-sync-decide.sh LAST_FORK_TAG DEV_REF      # run inside the repository
#
# Prints one word:
#   skip     nothing changed since the tag outside website/ and docs/, or no merge of upstream landed
#            on dev since the tag (the fork's own commits never start a release)
#   hold     something changed, but a commit since the tag was resolved by Claude (trailer
#            `Resolved-by: claude`) or Claude's review of a merge had concerns (trailer
#            `Review-concerns: claude`), so a person should look before the release
#   release  a merge of upstream changed something, and no commit since the tag carries either trailer
# A missing tag is an error, never a silent skip.

set -euo pipefail

if [ $# -ne 2 ]; then
    echo "usage: fork-sync-decide.sh LAST_FORK_TAG DEV_REF" >&2
    exit 2
fi
tag="$1"
dev="$2"

git rev-parse --verify --quiet "$tag^{commit}" > /dev/null || {
    echo "✗ no such tag or commit: $tag" >&2
    exit 2
}
git rev-parse --verify --quiet "$dev^{commit}" > /dev/null || {
    echo "✗ no such ref: $dev" >&2
    exit 2
}

# Any path that is not exactly under docs/ or website/ counts as code, however it is spelled.
code=0
while IFS= read -r -d '' path; do
    case "$path" in
        docs/* | website/*)
            case "$path" in
                *$'\n'* | *"/../"* | */..) code=1 ;;
            esac
            ;;
        *) code=1 ;;
    esac
done < <(git diff --name-only -z "$tag" "$dev")

if [ "$code" -eq 0 ]; then
    echo skip
    exit 0
fi

# Only a merge of upstream starts a release, never the fork's own commits (its scripts, workflows or
# features). The sync writes its merges with exactly this subject, and only dev's own line counts
# (--first-parent), so a commit on upstream's side with the same subject cannot start one.
if ! grep -qxF 'Merge upstream into dev' < <(git log --first-parent --format=%s "$tag..$dev"); then
    echo skip
    exit 0
fi

# grep reads from a process substitution, not a pipe: grep -q stops at the first match, and under
# pipefail git's resulting SIGPIPE would turn a match into "no match", releasing a held merge.
if grep -qx 'claude' < <(git log --format='%(trailers:key=Resolved-by,key=Review-concerns,valueonly,separator=%x0a)' "$tag..$dev"); then
    echo hold
else
    echo release
fi
