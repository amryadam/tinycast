#!/bin/bash
# Runs the Swift harnesses the release and sync gates depend on.
#
#   ./Scripts/fork-gate-tests.sh           # run them
#   ./Scripts/fork-gate-tests.sh --list    # print their names and stop
#
# Two groups, found in Scripts/run-tests.sh by name:
#   - the harnesses the fork owns. One missing from the registry is an error, because it means a
#     merge lost the fork's own line, and a quiet pass would hide that.
#   - upstream's update harnesses, whatever they are called now (any name containing "update"), so
#     an upstream rename needs no change here. They guard the code the in-app updater is built on.
# The whole suite is not run: a few upstream harnesses depend on the fonts and locale of the machine
# and fail on a runner that has neither.

set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

owned=(file-search-path-test file-search-fragment-test fork-update-test)

names="$(sed -n 's/^run  *\([^ ]*\).*/\1/p' Scripts/run-tests.sh)"
selected=()
for name in "${owned[@]}"; do
    if ! grep -qxF "$name" <<< "$names"; then
        echo "✗ the fork's harness '$name' is not registered in Scripts/run-tests.sh" >&2
        exit 1
    fi
    selected+=("$name")
done
while IFS= read -r name; do
    [ -z "$name" ] && continue
    case " ${owned[*]} " in *" $name "*) continue ;; esac
    if [[ "$name" == *[Uu]pdate* ]]; then selected+=("$name"); fi
done <<< "$names"

if [ "${1:-}" = "--list" ]; then
    printf '%s\n' "${selected[@]}"
    exit 0
fi

failed=0
for name in "${selected[@]}"; do
    ./Scripts/run-tests.sh "$name" || failed=1
done
exit "$failed"
