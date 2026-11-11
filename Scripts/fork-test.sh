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

# make_fake_app DIR [BUNDLE_ID] [VERSION] [sign|nosign]: a minimal signed bundle named Tinycast Fork.app.
make_fake_app() {
    local dir="$1" id="${2:-com.amryadam.tinycast}" version="${3:-1.2.3}" sign="${4:-sign}"
    local app="$dir/Tinycast Fork.app"
    mkdir -p "$app/Contents/MacOS"
    cp /usr/bin/true "$app/Contents/MacOS/Tinycast"
    cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Tinycast</string>
<key>CFBundleIdentifier</key><string>$id</string>
<key>CFBundleName</key><string>Tinycast Fork</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$version</string>
<key>CFBundleVersion</key><string>1</string>
</dict></plist>
PLIST
    if [ "$sign" = sign ]; then
        codesign --force --sign - "$app" > /dev/null 2>&1
    else
        codesign --remove-signature "$app/Contents/MacOS/Tinycast" > /dev/null 2>&1
    fi
    echo "$app"
}

test_import_requires_env() {
    local out
    out="$(env -u P12_BASE64 P12_PASSWORD=hunter2-secret RUNNER_TEMP="$WORK" \
        "$ROOT/Scripts/fork-import-identity.sh" 2>&1)" && fail "ran without P12_BASE64"
    assert_contains "$out" "P12_BASE64"
    assert_lacks "$out" "hunter2-secret"
    out="$(env -u P12_PASSWORD P12_BASE64=Zm9v RUNNER_TEMP="$WORK" \
        "$ROOT/Scripts/fork-import-identity.sh" 2>&1)" && fail "ran without P12_PASSWORD"
    assert_contains "$out" "P12_PASSWORD"
    assert_lacks "$out" "BEGIN"
    assert_lacks "$out" "PRIVATE"
    out="$(env -u RUNNER_TEMP P12_BASE64=Zm9v P12_PASSWORD=x \
        "$ROOT/Scripts/fork-import-identity.sh" 2>&1)" && fail "ran without RUNNER_TEMP"
    assert_contains "$out" "RUNNER_TEMP"
}

test_import_cleanup_is_safe() {
    local before after
    mkdir -p "$WORK/rt"
    before="$(security list-keychains -d user)"
    P12_BASE64=x P12_PASSWORD=x RUNNER_TEMP="$WORK/rt" "$ROOT/Scripts/fork-import-identity.sh" --cleanup \
        > /dev/null 2>&1 || fail "--cleanup failed when nothing was imported"
    after="$(security list-keychains -d user)"
    [ "$before" = "$after" ] || fail "--cleanup changed the keychain search list"
    [ -z "$(ls -A "$WORK/rt")" ] || fail "--cleanup left files in RUNNER_TEMP"
}

test_package_ok() {
    local app out_dir sum listed entry
    app="$(make_fake_app "$WORK/ok")"
    out_dir="$WORK/ok/out"
    sum="$("$ROOT/Scripts/fork-package.sh" "$app" 1.2.3-fork.1 "$out_dir")" || {
        fail "packaging a good app failed"
        return
    }
    [ -f "$out_dir/Tinycast-Fork-1.2.3-fork.1.zip" ] || fail "no zip"
    [ -f "$out_dir/Tinycast-Fork-1.2.3-fork.1.zip.sha256" ] || fail "no checksum file"
    [ "$sum" = "$(shasum -a 256 "$out_dir/Tinycast-Fork-1.2.3-fork.1.zip" | cut -d' ' -f1)" ] \
        || fail "printed checksum differs from shasum"
    (cd "$out_dir" && shasum -a 256 -c Tinycast-Fork-1.2.3-fork.1.zip.sha256 > /dev/null) \
        || fail "checksum file does not verify"
    listed="$(unzip -Z1 "$out_dir/Tinycast-Fork-1.2.3-fork.1.zip")"
    assert_contains "$listed" "Tinycast Fork.app/Contents/Info.plist"
    assert_contains "$listed" "LICENSE"
    assert_contains "$listed" "NOTICE.md"
    while IFS= read -r entry; do
        case "$entry" in
            "Tinycast Fork.app/"* | "Tinycast Fork.app" | LICENSE | NOTICE.md | __MACOSX/*) ;;
            *) fail "unexpected zip entry: $entry" ;;
        esac
    done <<< "$listed"
}

test_package_rejects() {
    local out app
    [ -x "$ROOT/Scripts/fork-package.sh" ] || {
        fail "Scripts/fork-package.sh is missing or not executable"
        return
    }
    reject() { # reject LABEL APP VERSION
        out="$WORK/rej-$1"
        if "$ROOT/Scripts/fork-package.sh" "$2" "$3" "$out" > /dev/null 2>&1; then
            fail "accepted: $1"
        fi
        ls "$out"/*.zip > /dev/null 2>&1 && fail "left a zip behind for: $1"
    }
    reject wrong-id "$(make_fake_app "$WORK/a1" com.example.other)" 1.2.3-fork.1
    reject wrong-version "$(make_fake_app "$WORK/a2" com.amryadam.tinycast 9.9.9)" 1.2.3-fork.1
    reject unsigned "$(make_fake_app "$WORK/a3" com.amryadam.tinycast 1.2.3 nosign)" 1.2.3-fork.1
    reject missing "$WORK/a4/Tinycast Fork.app" 1.2.3-fork.1
    app="$(make_fake_app "$WORK/a5")"
    reject bad-version "$app" "1.2.3"
    mkdir -p "$WORK/a6"
    cp -R "$app" "$WORK/a6/Other.app"
    reject wrong-name "$WORK/a6/Other.app" 1.2.3-fork.1
}

test_package_authority() {
    local app
    [ -x "$ROOT/Scripts/fork-package.sh" ] || {
        fail "Scripts/fork-package.sh is missing or not executable"
        return
    }
    app="$(make_fake_app "$WORK/auth")"
    "$ROOT/Scripts/fork-package.sh" "$app" 1.2.3-fork.1 "$WORK/auth/out" \
        --require-authority "Tinycast Self-Signed" > /dev/null 2>&1 \
        && fail "accepted an ad-hoc signature when Tinycast Self-Signed was required"
    ls "$WORK/auth/out"/*.zip > /dev/null 2>&1 && fail "left a zip behind"
    return 0
}

ALL=(validate_accepts validate_rejects build_print_settings import_requires_env import_cleanup_is_safe
    package_ok package_rejects package_authority)

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
