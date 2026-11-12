#!/bin/bash
# Refuses a source tree that could run code of its own while the signing key is in use.
#
#   ./Scripts/fork-check-build-inputs.sh [--paths-only] [TREEISH]     # run inside the repository
#
# TREEISH defaults to HEAD, and is read from git's objects, never from the working copy.
# The build job holds the signing key and compiles third-party sources, so anything that lets a
# build run a script or fetch a dependency is refused there, before the key is imported:
#   - a path that differs from another only by case, which lands on the same file on a Mac, so a
#     lower-case copy of a fork script could replace the checked one;
#   - a shell-script build phase, or a Swift package reference, in the Xcode project;
#   - a script, package or generation command in project.yml;
#   - an action that runs a command in a shared scheme.
# --paths-only checks the case collisions alone, which is all the upstream sync needs.

set -euo pipefail

paths_only=0
if [ "${1:-}" = "--paths-only" ]; then
    paths_only=1
    shift
fi
if [ $# -gt 1 ] || [[ "${1:-}" == -* ]]; then
    echo "usage: fork-check-build-inputs.sh [--paths-only] [TREEISH]" >&2
    exit 2
fi
tree="${1:-HEAD}"

die() {
    echo "✗ $*" >&2
    exit 1
}

collisions="$(git ls-tree -r --name-only "$tree" | sort -f | uniq -di)"
[ -z "$collisions" ] || die "paths that differ only by case: $(tr '\n' ' ' <<< "$collisions")"
[ "$paths_only" -eq 0 ] || exit 0

# The searches below read from process substitutions, not pipes: grep -q stops at its first match,
# and under pipefail the SIGPIPE that gives the producer would turn a match into "no match".
# show PATH: the committed file, or nothing when it is not in the tree.
show() { git show "$tree:$1" 2> /dev/null || true; }

pbx=Tinycast.xcodeproj/project.pbxproj
if grep -qE 'PBXShellScriptBuildPhase|XCRemoteSwiftPackageReference|XCLocalSwiftPackageReference|XCSwiftPackageProductDependency' < <(show "$pbx"); then
    die "$pbx has a shell-script build phase or a Swift package reference"
fi
if grep -qE '^[[:space:]]*(scripts|preBuildScripts|postBuildScripts|packages|buildToolPlugins|preGenCommand|postGenCommand):' < <(show project.yml); then
    die "project.yml has a script, a package or a generation command"
fi
while IFS= read -r -d '' path; do
    if grep -qiE '<ExecutionAction' < <(show "$path"); then
        die "$path runs a command"
    fi
done < <(git ls-tree -r --name-only -z "$tree" | grep -zE '\.xcscheme$' || true)

echo "✓ no build input can run code of its own"
