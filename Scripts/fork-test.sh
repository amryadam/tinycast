#!/bin/bash
# Tests for the fork's release scripts. Needs no network, no GitHub and no signing identity.
#
#   ./Scripts/fork-test.sh                  # every test
#   ./Scripts/fork-test.sh validate_rejects # one test, named without the test_ prefix

set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
ROOT="$PWD"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

FAILED=0
fail() {
    echo "  ✗ $*" >&2
    FAILED=1
}
# assert_contains HAYSTACK NEEDLE
assert_contains() {
    case "$1" in *"$2"*) ;; *) fail "output lacks: $2" ;; esac
}
# assert_lacks HAYSTACK NEEDLE
assert_lacks() {
    case "$1" in *"$2"*) fail "output has: $2" ;; esac
}

test_validate_accepts() {
    local out
    out="$("$ROOT/Scripts/fork-release-validate.sh" 0.12.11-fork.1)" || fail "rejected a valid version"
    [ "$out" = "0.12.11" ] || fail "printed '$out', expected 0.12.11"
}

test_validate_rejects() {
    local bad
    # A missing script would "reject" everything, so require it first.
    [ -x "$ROOT/Scripts/fork-release-validate.sh" ] || {
        fail "Scripts/fork-release-validate.sh is missing or not executable"
        return
    }
    for bad in "1.0.0" "1.0.0-fork" "1.0.0-fork.x" "1.0.0-fork.1; rm -rf ~" $'1.0.0-fork.1\n' \
        " 1.0.0-fork.1" "" "v1.0.0-fork.1" "1.0-fork.1" "1.0.0-fork.1 "; do
        if "$ROOT/Scripts/fork-release-validate.sh" "$bad" > /dev/null 2>&1; then
            fail "accepted '$bad'"
        fi
    done
    "$ROOT/Scripts/fork-release-validate.sh" > /dev/null 2>&1 && fail "accepted no argument"
    "$ROOT/Scripts/fork-release-validate.sh" 1.0.0-fork.1 2.0.0-fork.1 > /dev/null 2>&1 \
        && fail "accepted two arguments"
}

test_build_print_settings() {
    local with without
    with="$(FORK_VERSION=1.2.3 FORK_BUILD_NUMBER=42 "$ROOT/Scripts/fork-build.sh" --print-settings)" \
        || fail "--print-settings failed (it must not need the signing identity)"
    assert_contains "$with" "MARKETING_VERSION=1.2.3"
    assert_contains "$with" "CURRENT_PROJECT_VERSION=42"
    assert_contains "$with" "TINYCAST_BUNDLE_IDENTIFIER=com.amryadam.tinycast"
    assert_contains "$with" "PRODUCT_NAME=Tinycast Fork"
    without="$(env -u FORK_VERSION -u FORK_BUILD_NUMBER "$ROOT/Scripts/fork-build.sh" --print-settings)" \
        || fail "--print-settings failed without a version"
    assert_lacks "$without" "MARKETING_VERSION"
    assert_lacks "$without" "CURRENT_PROJECT_VERSION"
}

ALL=(validate_accepts validate_rejects build_print_settings)

if [ $# -gt 0 ]; then
    names=("$@")
else
    names=("${ALL[@]}")
fi
for name in "${names[@]}"; do
    if ! declare -F "test_$name" > /dev/null; then
        echo "fork-test: no such test '$name'" >&2
        exit 2
    fi
    echo "▸ $name"
    "test_$name"
done

if [ "$FAILED" -ne 0 ]; then
    echo "fork-test: FAILED" >&2
    exit 1
fi
echo "fork-test: all passed (${#names[@]})"
