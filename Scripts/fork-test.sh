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

test_notes_licence_items() {
    local sha=0123456789abcdef0123456789abcdef01234567 out title today
    [ -x "$ROOT/Scripts/fork-release-notes.sh" ] || {
        fail "Scripts/fork-release-notes.sh is missing or not executable"
        return
    }
    out="$("$ROOT/Scripts/fork-release-notes.sh" 0.12.11-fork.1 "$sha" amryadam/tinycast)" || {
        fail "the notes script failed"
        return
    }
    today="$(date -u +%Y-%m-%d)"
    for needle in "unofficial" "not affiliated" "modified version of Tinycast" "Abue Ammar" \
        "AGPL-3.0-or-later" "$today" "$sha" \
        "https://github.com/abue-ammar/tinycast/commit/$sha" \
        "https://github.com/amryadam/tinycast/tree/v0.12.11-fork.1" \
        "https://github.com/amryadam/tinycast/blob/v0.12.11-fork.1/LICENSE" \
        "path-query" "brew tap amryadam/fork" "brew install --cask amryadam/fork/tinycast-fork" \
        "Privacy & Security"; do
        assert_contains "$out" "$needle"
    done
    while IFS= read -r title; do
        assert_contains "$out" "$title"
    done < <(sed -n 's/^# Feature: *//p' "$ROOT"/docs/fork/*.md)
}

test_notes_rejects() {
    local sha=0123456789abcdef0123456789abcdef01234567
    [ -x "$ROOT/Scripts/fork-release-notes.sh" ] || {
        fail "Scripts/fork-release-notes.sh is missing or not executable"
        return
    }
    "$ROOT/Scripts/fork-release-notes.sh" 1.0.0 "$sha" amryadam/tinycast > /dev/null 2>&1 \
        && fail "accepted a version without -fork.N"
    "$ROOT/Scripts/fork-release-notes.sh" 0.12.11-fork.1 notasha amryadam/tinycast > /dev/null 2>&1 \
        && fail "accepted a malformed sha"
    "$ROOT/Scripts/fork-release-notes.sh" 0.12.11-fork.1 "$sha" 'amryadam/tinycast;x' > /dev/null 2>&1 \
        && fail "accepted a malformed repository"
    "$ROOT/Scripts/fork-release-notes.sh" 0.12.11-fork.1 "$sha" > /dev/null 2>&1 \
        && fail "accepted a missing repository"
    return 0
}

SHA64=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa

test_cask_contents() {
    local out
    [ -x "$ROOT/Scripts/fork-cask.sh" ] || {
        fail "Scripts/fork-cask.sh is missing or not executable"
        return
    }
    "$ROOT/Scripts/fork-cask.sh" 0.12.11-fork.1 "$SHA64" "$WORK/cask/Casks/tinycast-fork.rb" \
        || fail "the cask script failed"
    out="$(cat "$WORK/cask/Casks/tinycast-fork.rb")"
    for needle in 'cask "tinycast-fork" do' 'version "0.12.11-fork.1"' "sha256 \"$SHA64\"" \
        'url "https://github.com/amryadam/tinycast/releases/download/v#{version}/Tinycast-Fork-#{version}.zip"' \
        'name "Tinycast Fork"' 'desc "Unofficial fork' 'homepage "https://github.com/amryadam/tinycast"' \
        'livecheck do' 'strategy :github_latest' '-fork' 'depends_on macos: :tahoe' \
        'depends_on arch: :arm64' 'app "Tinycast Fork.app"' 'uninstall quit: "com.amryadam.tinycast"' \
        'com.amryadam.tinycast.dictation'; do
        assert_contains "$out" "$needle"
    done
    assert_lacks "$out" "ClipboardTextHelper"
}

test_cask_rejects() {
    [ -x "$ROOT/Scripts/fork-cask.sh" ] || {
        fail "Scripts/fork-cask.sh is missing or not executable"
        return
    }
    local bad out="$WORK/cask-rej/x.rb"
    for bad in "abc" "${SHA64}0" "${SHA64%a}" "${SHA64%a}G" "$(echo "$SHA64" | tr a A)" ""; do
        "$ROOT/Scripts/fork-cask.sh" 0.12.11-fork.1 "$bad" "$out" > /dev/null 2>&1 \
            && fail "accepted checksum '$bad'"
    done
    "$ROOT/Scripts/fork-cask.sh" 0.12.11 "$SHA64" "$out" > /dev/null 2>&1 \
        && fail "accepted a version without -fork.N"
    "$ROOT/Scripts/fork-cask.sh" > /dev/null 2>&1 && fail "accepted no arguments"
    [ -e "$out" ] && fail "wrote a cask after a rejection"
    return 0
}

test_cask_from_release() {
    local out="$WORK/cask-fr/tinycast-fork.rb" stub="$WORK/cask-fr/bin"
    [ -x "$ROOT/Scripts/fork-cask.sh" ] || {
        fail "Scripts/fork-cask.sh is missing or not executable"
        return
    }
    mkdir -p "$stub"
    cat > "$stub/gh" <<STUB
#!/bin/bash
# Stub: records its arguments and prints a checksum file, as gh release download --output - would.
echo "\$*" > "$WORK/cask-fr/gh-args"
echo "$SHA64  Tinycast-Fork-0.12.11-fork.1.zip"
STUB
    chmod +x "$stub/gh"
    PATH="$stub:$PATH" "$ROOT/Scripts/fork-cask.sh" --from-release 0.12.11-fork.1 "$out" \
        || fail "--from-release failed"
    assert_contains "$(cat "$out")" "sha256 \"$SHA64\""
    assert_contains "$(cat "$WORK/cask-fr/gh-args")" "v0.12.11-fork.1"
    # A release whose checksum file is garbage must not produce a cask.
    cat > "$stub/gh" <<'STUB'
#!/bin/bash
echo "not a checksum"
STUB
    rm -f "$out"
    PATH="$stub:$PATH" "$ROOT/Scripts/fork-cask.sh" --from-release 0.12.11-fork.1 "$out" > /dev/null 2>&1 \
        && fail "--from-release accepted a garbage checksum file"
    [ -e "$out" ] && fail "--from-release wrote a cask from a garbage checksum file"
    return 0
}

test_cask_style() {
    local dir="$WORK/cask-style/Casks"
    command -v brew > /dev/null || {
        echo "  (skipped: brew is not installed)"
        return
    }
    [ -x "$ROOT/Scripts/fork-cask.sh" ] || {
        fail "Scripts/fork-cask.sh is missing or not executable"
        return
    }
    "$ROOT/Scripts/fork-cask.sh" 0.12.11-fork.1 "$SHA64" "$dir/tinycast-fork.rb" > /dev/null \
        || fail "the cask script failed"
    brew style "$dir/tinycast-fork.rb" > "$WORK/cask-style/out" 2>&1 \
        || fail "brew style failed: $(head -20 "$WORK/cask-style/out")"
}

ALL=(validate_accepts validate_rejects build_print_settings import_requires_env import_cleanup_is_safe
    package_ok package_rejects package_authority notes_licence_items notes_rejects cask_contents cask_rejects cask_from_release cask_style)

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
