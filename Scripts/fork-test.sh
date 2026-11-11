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
    assert_contains "$with" "ARCHS=arm64"
    assert_contains "$with" "ONLY_ACTIVE_ARCH=NO"
    without="$(env -u FORK_VERSION -u FORK_BUILD_NUMBER "$ROOT/Scripts/fork-build.sh" --print-settings)" \
        || fail "--print-settings failed without a version"
    assert_lacks "$without" "MARKETING_VERSION"
    assert_lacks "$without" "CURRENT_PROJECT_VERSION"
}

# make_fake_app DIR [BUNDLE_ID] [VERSION] [sign|nosign]: a minimal signed bundle named Tinycast Fork.app.
make_fake_app() {
    local dir="$1" id="${2:-com.amryadam.tinycast}" version="${3:-1.2.3-fork.1}" sign="${4:-sign}"
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
    local app out_dir sum listed entry notice
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
    assert_contains "$listed" "FORK-NOTICE.md"
    notice="$(unzip -p "$out_dir/Tinycast-Fork-1.2.3-fork.1.zip" FORK-NOTICE.md)"
    assert_contains "$notice" "unofficial, modified version of Tinycast"
    assert_contains "$notice" "1.2.3-fork.1"
    assert_contains "$notice" "https://github.com/amryadam/tinycast/tree/v1.2.3-fork.1"
    assert_contains "$notice" "$(date -u +%Y-%m-%d)"
    while IFS= read -r entry; do
        case "$entry" in
            "Tinycast Fork.app/"* | "Tinycast Fork.app" | LICENSE | NOTICE.md | FORK-NOTICE.md | __MACOSX/*) ;;
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
    reject unsigned "$(make_fake_app "$WORK/a3" com.amryadam.tinycast 1.2.3-fork.1 nosign)" 1.2.3-fork.1
    reject missing "$WORK/a4/Tinycast Fork.app" 1.2.3-fork.1
    app="$(make_fake_app "$WORK/a5")"
    reject bad-version "$app" "1.2.3"
    # The app must carry the full fork version, so the updater can tell revisions apart.
    reject base-version-only "$(make_fake_app "$WORK/a7" com.amryadam.tinycast 1.2.3)" 1.2.3-fork.1
    mkdir -p "$WORK/a6"
    cp -R "$app" "$WORK/a6/Other.app"
    reject wrong-name "$WORK/a6/Other.app" 1.2.3-fork.1
}

# A codesign that reports a chosen signer for -dvv and is the real one for everything else, so the
# authority check can be tested without putting a certificate in any keychain.
codesign_stub() { # codesign_stub DIR AUTHORITY
    mkdir -p "$1"
    cat > "$1/codesign" <<STUB
#!/bin/bash
case "\$*" in
    *-dvv*) echo "Authority=$2"; echo "Authority=Some Root" ;;
    *) exec /usr/bin/codesign "\$@" ;;
esac
STUB
    chmod +x "$1/codesign"
}

test_package_authority() {
    local app
    [ -x "$ROOT/Scripts/fork-package.sh" ] || {
        fail "Scripts/fork-package.sh is missing or not executable"
        return
    }
    app="$(make_fake_app "$WORK/auth")"
    # Ad-hoc signed: no authority at all.
    "$ROOT/Scripts/fork-package.sh" "$app" 1.2.3-fork.1 "$WORK/auth/out" \
        --require-authority "Tinycast Self-Signed" > /dev/null 2>&1 \
        && fail "accepted an ad-hoc signature when Tinycast Self-Signed was required"
    ls "$WORK/auth/out"/*.zip > /dev/null 2>&1 && fail "left a zip behind"
    # Signed by somebody else.
    codesign_stub "$WORK/auth/other" "Somebody Else"
    PATH="$WORK/auth/other:$PATH" "$ROOT/Scripts/fork-package.sh" "$app" 1.2.3-fork.1 "$WORK/auth/out2" \
        --require-authority "Tinycast Self-Signed" > /dev/null 2>&1 \
        && fail "accepted a different signer"
    # Signed by the right one.
    codesign_stub "$WORK/auth/right" "Tinycast Self-Signed"
    PATH="$WORK/auth/right:$PATH" "$ROOT/Scripts/fork-package.sh" "$app" 1.2.3-fork.1 "$WORK/auth/out3" \
        --require-authority "Tinycast Self-Signed" > /dev/null 2>&1 \
        || fail "refused the right signer"
    [ -f "$WORK/auth/out3/Tinycast-Fork-1.2.3-fork.1.zip" ] || fail "no zip for the right signer"
    return 0
}

test_package_relative_paths() {
    local app
    [ -x "$ROOT/Scripts/fork-package.sh" ] || {
        fail "Scripts/fork-package.sh is missing or not executable"
        return
    }
    app="$(make_fake_app "$WORK/rel")"
    (cd "$WORK/rel" && "$ROOT/Scripts/fork-package.sh" "Tinycast Fork.app" 1.2.3-fork.1 out > /dev/null) \
        || fail "relative paths failed"
    [ -f "$WORK/rel/out/Tinycast-Fork-1.2.3-fork.1.zip" ] || fail "the zip is not where the caller said"
    : "$app"
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
        "path-query" "brew tap amryadam/fork" "brew trust --cask amryadam/fork/tinycast-fork" "brew install --cask amryadam/fork/tinycast-fork" \
        "Privacy & Security"; do
        assert_contains "$out" "$needle"
    done
    while IFS= read -r title; do
        assert_contains "$out" "- [$title]("
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
        'livecheck do' 'strategy :github_latest' '-fork' 'depends_on macos: :tahoe' 'auto_updates true' \
        'depends_on arch: :arm64' 'app "Tinycast Fork.app"' 'uninstall quit: "com.amryadam.tinycast"' \
        'com.amryadam.tinycast.dictation' 'CrashReporter/Tinycast Fork_*.plist'; do
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

# bootstrap_env NAME: a fresh area with a stub gh first on PATH. The stub records every call in
# calls.log, saves what it is given on standard input, and answers reads from STUB_* variables.
bootstrap_env() {
    BS="$WORK/bs-$1"
    mkdir -p "$BS/bin" "$BS/tmp"
    : > "$BS/calls.log"
    cat > "$BS/bin/gh" <<'STUB'
#!/bin/bash
echo "$*" >> "$STUB_DIR/calls.log"
case "$1 $2" in
    "secret set") cat > "$STUB_DIR/stdin-$3" ;;
    "secret list") for n in ${STUB_EXISTING_SECRETS:-}; do echo "$n"; done ;;
    "repo view") [ "${STUB_REPO_EXISTS:-0}" = 1 ] || exit 1 ;;
    "repo deploy-key")
        if [ "$3" = list ]; then
            for n in ${STUB_DEPLOY_KEY_IDS:-}; do echo "$n"; done
            exit 0
        fi
        for a in "$@"; do [ -f "$a" ] && cp "$a" "$STUB_DIR/deploy-pub"; done
        ;;
    "api "*)
        case "$*" in
            *--input*) cat > "$STUB_DIR/api-stdin-$(wc -l < "$STUB_DIR/calls.log" | tr -d ' ')" ;;
            *-X*) ;;
            *deployment-branch-policies*) for n in ${STUB_POLICIES:-}; do echo "$n"; done ;;
        esac
        ;;
esac
exit 0
STUB
    chmod +x "$BS/bin/gh"
}

# run_bootstrap ARGS...: runs the script with the stub, in the area made by bootstrap_env.
run_bootstrap() {
    STUB_DIR="$BS" PATH="$BS/bin:$PATH" TMPDIR="$BS/tmp" "$ROOT/Scripts/fork-bootstrap.sh" "$@" 2>&1 < /dev/null
}

# bootstrap_writes: the stub calls that would change GitHub.
bootstrap_writes() {
    grep -E '^(secret set|repo create|repo deploy-key (add|delete)|api .*(-X|--method))' "$BS/calls.log" || true
}

require_bootstrap() {
    [ -x "$ROOT/Scripts/fork-bootstrap.sh" ] || {
        fail "Scripts/fork-bootstrap.sh is missing or not executable"
        return 1
    }
}

test_bootstrap_dry_run() {
    require_bootstrap || return 0
    local sub out
    for sub in environments tap identity; do
        bootstrap_env "dry-$sub"
        out="$(run_bootstrap "$sub" --dry-run)" || fail "$sub --dry-run failed: $out"
        assert_contains "$out" "dry run"
        assert_lacks "$out" "BEGIN"
        assert_lacks "$out" "PRIVATE"
        [ -z "$(bootstrap_writes)" ] || fail "$sub --dry-run changed GitHub: $(bootstrap_writes)"
        [ -z "$(ls -A "$BS/tmp")" ] || fail "$sub --dry-run left files in the temporary folder"
    done
}

test_bootstrap_environments_calls() {
    require_bootstrap || return 0
    local out env
    bootstrap_env env
    out="$(run_bootstrap environments)" || fail "environments failed: $out"
    for env in fork-build fork-publish; do
        grep -q "environments/$env" "$BS/calls.log" || fail "no call for $env"
    done
    grep -q 'deployment-branch-policies' "$BS/calls.log" || fail "no branch policy created"
    assert_contains "$(cat "$BS"/api-stdin-* 2>/dev/null)" '"name":"dev"'
    # With dev already allowed, no second policy is created.
    bootstrap_env env2
    STUB_POLICIES="dev" run_bootstrap environments > /dev/null || fail "environments failed on a rerun"
    grep -q 'POST.*deployment-branch-policies' "$BS/calls.log" && fail "created a policy that exists"
    return 0
}

test_bootstrap_identity_calls() {
    require_bootstrap || return 0
    local out pass
    bootstrap_env id
    out="$(run_bootstrap identity)" || {
        fail "identity failed: $out"
        return
    }
    assert_contains "$(cat "$BS/calls.log")" "secret set SIGNING_P12_BASE64 --env fork-build"
    assert_contains "$(cat "$BS/calls.log")" "secret set SIGNING_P12_PASSWORD --env fork-build"
    [ -s "$BS/stdin-SIGNING_P12_BASE64" ] || fail "the identity was not sent on standard input"
    [ -s "$BS/stdin-SIGNING_P12_PASSWORD" ] || fail "the password was not sent on standard input"
    pass="$(cat "$BS/stdin-SIGNING_P12_PASSWORD")"
    # The secrets never appear in an argument or in the output.
    assert_lacks "$(cat "$BS/calls.log")" "$pass"
    assert_lacks "$(cat "$BS/calls.log")" "$(head -c 40 "$BS/stdin-SIGNING_P12_BASE64")"
    assert_lacks "$out" "$pass"
    assert_lacks "$out" "BEGIN"
    # What was uploaded is a real identity: it opens with the uploaded password and is named right.
    base64 -D < "$BS/stdin-SIGNING_P12_BASE64" > "$BS/id.p12" 2> /dev/null || fail "the upload is not base64"
    /usr/bin/openssl pkcs12 -in "$BS/id.p12" -passin "pass:$pass" -nodes 2> /dev/null \
        | /usr/bin/openssl x509 -noout -subject 2> /dev/null | grep -q "Tinycast Self-Signed" \
        || fail "the uploaded identity does not open, or is not named Tinycast Self-Signed"
}

test_bootstrap_tap_calls() {
    require_bootstrap || return 0
    local out id
    bootstrap_env tap
    out="$(run_bootstrap tap)" || {
        fail "tap failed: $out"
        return
    }
    assert_contains "$(cat "$BS/calls.log")" "repo create amryadam/homebrew-fork --public"
    assert_contains "$(cat "$BS/calls.log")" "--allow-write"
    assert_contains "$(cat "$BS/calls.log")" "secret set TAP_DEPLOY_KEY --env fork-publish"
    assert_contains "$(cat "$BS/deploy-pub")" "ssh-ed25519"
    assert_contains "$(cat "$BS/stdin-TAP_DEPLOY_KEY")" "BEGIN OPENSSH PRIVATE KEY"
    assert_lacks "$(cat "$BS/calls.log")" "PRIVATE KEY"
    assert_lacks "$out" "PRIVATE KEY"
    # Replacing a key: the new key and secret come first, then the old key goes.
    bootstrap_env tap3
    STUB_REPO_EXISTS=1 STUB_DEPLOY_KEY_IDS="111 222" run_bootstrap tap > /dev/null || fail "tap failed with old keys"
    local add_line secret_line del_line
    add_line="$(grep -n '^repo deploy-key add' "$BS/calls.log" | head -1 | cut -d: -f1)"
    secret_line="$(grep -n '^secret set TAP_DEPLOY_KEY' "$BS/calls.log" | head -1 | cut -d: -f1)"
    for id in 111 222; do
        del_line="$(grep -n "^repo deploy-key delete $id" "$BS/calls.log" | head -1 | cut -d: -f1)"
        [ -n "$del_line" ] || fail "the old key $id was not deleted"
        [ -n "$del_line" ] && [ "$del_line" -gt "${secret_line:-0}" ] && [ "$del_line" -gt "${add_line:-0}" ] \
            || fail "the old key $id was deleted before the new key and secret were stored"
    done
    # An existing tap repository is kept, not created again.
    bootstrap_env tap2
    STUB_REPO_EXISTS=1 run_bootstrap tap > /dev/null || fail "tap failed when the repository exists"
    grep -q '^repo create' "$BS/calls.log" && fail "created a repository that exists"
    return 0
}

test_bootstrap_refuses_overwrite() {
    require_bootstrap || return 0
    local out
    bootstrap_env ow
    out="$(STUB_EXISTING_SECRETS="SIGNING_P12_BASE64 SIGNING_P12_PASSWORD" run_bootstrap identity)" \
        && fail "replaced an existing identity without --force"
    assert_contains "$out" "--force"
    [ -z "$(bootstrap_writes)" ] || fail "changed GitHub while refusing: $(bootstrap_writes)"
    bootstrap_env ow2
    STUB_EXISTING_SECRETS="SIGNING_P12_BASE64 SIGNING_P12_PASSWORD" run_bootstrap identity --force > /dev/null \
        || fail "--force did not let identity proceed"
    grep -q '^secret set SIGNING_P12_BASE64' "$BS/calls.log" || fail "--force did not set the identity"
    bootstrap_env ow3
    STUB_EXISTING_SECRETS="TAP_DEPLOY_KEY" run_bootstrap tap > /dev/null \
        && fail "replaced an existing deploy key without --force"
    [ -z "$(bootstrap_writes)" ] || fail "tap changed GitHub while refusing: $(bootstrap_writes)"
    return 0
}

test_bootstrap_no_leftovers() {
    require_bootstrap || return 0
    local sub
    for sub in identity tap; do
        bootstrap_env "left-$sub"
        run_bootstrap "$sub" > /dev/null || fail "$sub failed"
        [ -z "$(ls -A "$BS/tmp")" ] || fail "$sub left files behind: $(ls -A "$BS/tmp")"
    done
    # A failed upload must not leave key material either.
    bootstrap_env left-fail
    sed -i '' 's|^    "secret set") cat|    "secret set") exit 1; cat|' "$BS/bin/gh"
    run_bootstrap identity > /dev/null 2>&1 && fail "identity ignored a failed upload"
    [ -z "$(ls -A "$BS/tmp")" ] || fail "a failed upload left files behind: $(ls -A "$BS/tmp")"
    return 0
}

test_bootstrap_rejects_bad_args() {
    require_bootstrap || return 0
    bootstrap_env args
    run_bootstrap > /dev/null && fail "ran without a subcommand"
    run_bootstrap nonsense > /dev/null && fail "accepted an unknown subcommand"
    run_bootstrap identity --repo 'x/y;rm -rf ~' > /dev/null && fail "accepted a malformed --repo"
    run_bootstrap tap --tap 'no-slash' > /dev/null && fail "accepted a malformed --tap"
    run_bootstrap identity --bogus > /dev/null && fail "accepted an unknown option"
    [ -z "$(bootstrap_writes)" ] || fail "bad arguments changed GitHub: $(bootstrap_writes)"
    return 0
}

# job_block FILE NAME: the lines of one top-level job.
job_block() {
    awk -v want="  $2:" '/^  [A-Za-z0-9_-]+:/ { on = ($0 == want) } on' "$1"
}

test_workflow_static() {
    local wf="${FORK_WORKFLOW:-$ROOT/.github/workflows/fork-release.yml}" build publish bad
    [ -f "$wf" ] || {
        fail "the workflow is missing: $wf"
        return
    }
    if command -v actionlint > /dev/null; then
        # xcode-27 is a label GitHub provides but actionlint does not know.
        printf 'self-hosted-runner:\n  labels:\n    - xcode-27\n' > "$WORK/actionlint.yaml"
        actionlint -config-file "$WORK/actionlint.yaml" "$wf" || fail "actionlint found problems"
    else
        echo "  (actionlint is not installed, so its checks are skipped)"
    fi

    build="$(job_block "$wf" build)"
    publish="$(job_block "$wf" publish)"
    [ -n "$build" ] && [ -n "$publish" ] || {
        fail "the workflow needs jobs named build and publish"
        return
    }

    grep -qx 'permissions: {}' "$wf" || fail "no top-level permissions: {}"
    grep -q '^  workflow_dispatch:' "$wf" || fail "workflow_dispatch is not a trigger"
    grep -Eq '^  (push|pull_request|pull_request_target|schedule|workflow_run|release|issues|issue_comment|repository_dispatch):' "$wf" \
        && fail "the workflow has a trigger other than workflow_dispatch"
    grep -q 'default: false' "$wf" || fail "publish does not default to false"

    assert_contains "$build" "runs-on: xcode-27"
    assert_contains "$build" "environment: fork-build"
    assert_contains "$build" "contents: read"
    assert_contains "$build" "if: github.ref == 'refs/heads/dev'"
    assert_lacks "$build" ": write"
    # The build job may read the previous release, but never create one.
    assert_lacks "$build" "gh release create"
    assert_lacks "$build" "git push"
    assert_lacks "$build" "TAP_DEPLOY_KEY"
    assert_contains "$build" "SIGNING_P12_BASE64"
    assert_contains "$build" "SIGNING_P12_PASSWORD"
    assert_contains "$build" "--require-authority"
    assert_contains "$build" "fork-check-update-path.sh"
    assert_contains "$build" "EXPECTED_SHA"
    # shellcheck disable=SC2016 # literal shell text is wanted
    assert_contains "$build" 'FORK_VERSION="$VERSION"'
    grep -q 'expected_sha:' "$wf" || fail "the workflow has no expected_sha input"
    assert_contains "$build" "retention-days: 1"

    assert_contains "$publish" "environment: fork-publish"
    assert_contains "$publish" "contents: write"
    assert_contains "$publish" "if: inputs.publish"
    assert_contains "$publish" "needs: build"
    assert_contains "$publish" "--latest"
    # shellcheck disable=SC2016 # a literal $GITHUB_SHA is wanted
    assert_contains "$publish" '--target "$GITHUB_SHA"'
    assert_contains "$publish" "TAP_DEPLOY_KEY"
    assert_lacks "$publish" "SIGNING_P12"
    assert_lacks "$publish" "--force"

    # Inputs and secrets only inside an env: block, never spliced into a script or an argument.
    bad="$(awk '
        /^[[:space:]]*env:[[:space:]]*$/ { match($0, /^ */); envind = RLENGTH; inenv = 1; next }
        inenv { match($0, /^ */); if ($0 !~ /^[[:space:]]*$/ && RLENGTH <= envind) inenv = 0 }
        /\$\{\{ *(inputs|secrets|github\.event)[.[]/ && !inenv { print NR ": " $0 }
    ' "$wf")"
    [ -z "$bad" ] || fail "an input or secret is used outside env: $bad"

    # Every action is pinned to a full commit SHA.
    bad="$(grep -E '^[[:space:]]*(- )?uses:' "$wf" | grep -vE '@[0-9a-f]{40}[[:space:]]*$' || true)"
    [ -z "$bad" ] || fail "an action is not pinned to a commit: $bad"

    [ "$(grep -c 'actions/checkout@' "$wf")" = "$(grep -c 'persist-credentials: false' "$wf")" ] \
        || fail "every checkout must set persist-credentials: false"
    [ "$(grep -c 'if: always()' "$wf")" -ge 2 ] || fail "each job needs an if: always() cleanup step"
    grep -q 'concurrency:' "$wf" || fail "no concurrency group"

    # Order matters. In the build job Homebrew's lint runs before the key is imported, and the
    # keychain is removed before the artifact is uploaded. In the publish job the tap is prepared
    # before the release is made, and a release that already exists is kept rather than failing.
    step_line() { grep -n -- "- name: $2" <<< "$1" | head -1 | cut -d: -f1; }
    local lint import cleanup upload prepare release push
    lint="$(step_line "$build" 'Lint the cask')"
    import="$(step_line "$build" 'Import the signing identity')"
    cleanup="$(step_line "$build" 'Remove the signing keychain')"
    upload="$(grep -n 'actions/upload-artifact@' <<< "$build" | head -1 | cut -d: -f1)"
    [ -n "$lint" ] && [ -n "$import" ] && [ "$lint" -lt "$import" ] || fail "the cask lint must run before the key is imported"
    [ -n "$cleanup" ] && [ -n "$upload" ] && [ "$cleanup" -lt "$upload" ] || fail "the keychain must be removed before the upload"
    prepare="$(step_line "$publish" 'Prepare the tap')"
    release="$(step_line "$publish" 'Create the release')"
    push="$(step_line "$publish" 'Push the tap')"
    [ -n "$prepare" ] && [ -n "$release" ] && [ -n "$push" ] && [ "$prepare" -lt "$release" ] && [ "$release" -lt "$push" ] \
        || fail "the publish steps must be: prepare the tap, create the release, push the tap"
    assert_contains "$publish" "gh release view"
    assert_contains "$publish" "git rebase --abort"
}

# A codesign that answers -d -r- with a fixed requirement, and --verify by STUB_VERIFY (0 or 1).
requirement_stub() { # requirement_stub DIR
    mkdir -p "$1"
    cat > "$1/codesign" <<'STUB'
#!/bin/bash
case "$*" in
    *"-d -r-"*) echo 'designated => identifier "com.amryadam.tinycast" and certificate leaf = H"00aa"' ;;
    *--verify*) echo "$*" > "$STUB_LOG"; exit "${STUB_VERIFY:-0}" ;;
    *) exec /usr/bin/codesign "$@" ;;
esac
STUB
    chmod +x "$1/codesign"
}

test_update_path() {
    local script="$ROOT/Scripts/fork-check-update-path.sh" prev new stub="$WORK/up/stub"
    [ -x "$script" ] || {
        fail "Scripts/fork-check-update-path.sh is missing or not executable"
        return
    }
    prev="$(make_fake_app "$WORK/up/prev")"
    mkdir -p "$WORK/up/zip"
    ditto -c -k --keepParent "$prev" "$WORK/up/zip/prev.zip"
    new="$(make_fake_app "$WORK/up/new" com.amryadam.tinycast 1.2.3-fork.2)"
    requirement_stub "$stub"
    # The new app satisfies the previous requirement.
    STUB_LOG="$WORK/up/log" STUB_VERIFY=0 PATH="$stub:$PATH" "$script" "$new" "$WORK/up/zip/prev.zip" > /dev/null 2>&1 \
        || fail "refused an app that satisfies the previous requirement"
    assert_contains "$(cat "$WORK/up/log")" 'certificate leaf = H"00aa"'
    # It does not.
    STUB_LOG="$WORK/up/log" STUB_VERIFY=1 PATH="$stub:$PATH" "$script" "$new" "$WORK/up/zip/prev.zip" > /dev/null 2>&1 \
        && fail "accepted an app that fails the previous requirement"
    # No previous zip, or one with no app in it.
    PATH="$stub:$PATH" "$script" "$new" "$WORK/up/zip/missing.zip" > /dev/null 2>&1 \
        && fail "accepted a missing previous zip"
    mkdir -p "$WORK/up/empty" && echo x > "$WORK/up/empty/x" && ditto -c -k "$WORK/up/empty" "$WORK/up/zip/empty.zip"
    PATH="$stub:$PATH" "$script" "$new" "$WORK/up/zip/empty.zip" > /dev/null 2>&1 \
        && fail "accepted a previous zip with no app"
    "$script" > /dev/null 2>&1 && fail "accepted no arguments"
    return 0
}

# ---- sync scripts: real throwaway git repositories ----

# gitq: git with a fixed identity and no signing, for the repositories these tests build.
gitq() {
    git -c user.name=test -c user.email=test@example.invalid -c commit.gpgsign=false -c init.defaultBranch=main "$@"
}

# make_sync_repo DIR: a repository with a base commit, a `dev` branch and an `up` branch.
make_sync_repo() {
    mkdir -p "$1" && cd "$1" || return 1
    gitq init -q
    mkdir -p .github/workflows Scripts docs/fork Tinycast website
    printf 'one\ntwo\nthree\n' > Tinycast/Core.swift
    echo a > a.txt
    echo ours > .github/workflows/ours.yml
    echo up > .github/workflows/up.yml
    echo script > Scripts/fork-x.sh
    echo doc > docs/fork/x.md
    echo site > website/index.md
    gitq add -A && gitq commit -qm base
    gitq branch dev && gitq branch up
    cd - > /dev/null || return 1
}

# on_branch DIR BRANCH COMMAND...: run a command on a branch and commit what it changes.
on_branch() {
    local dir="$1" branch="$2"
    shift 2
    (cd "$dir" && gitq checkout -q "$branch" && "$@" && gitq add -A && gitq commit -qm "change on $branch")
}

test_next_version() {
    local script="$ROOT/Scripts/fork-next-version.sh" out
    [ -x "$script" ] || {
        fail "Scripts/fork-next-version.sh is missing or not executable"
        return
    }
    [ "$("$script" 0.12.12 v0.12.11-fork.4 v0.12.11-fork.5)" = "0.12.12-fork.1" ] || fail "a new base should start at 1"
    [ "$("$script" 0.12.11 v0.12.11-fork.4 v0.12.11-fork.10 v0.12.11-fork.9)" = "0.12.11-fork.11" ] || fail ".10 must beat .9"
    [ "$("$script" 0.12.11 v0.12.12-fork.1)" = "0.12.12-fork.2" ] || fail "a higher fork base must win over a lower upstream base"
    [ "$("$script" 0.12.11)" = "0.12.11-fork.1" ] || fail "no tags should start at 1"
    [ "$("$script" 0.12.11 v0.11.9-fork.30 v0.12.11-fork.2)" = "0.12.11-fork.3" ] || fail "other bases must be ignored"
    [ "$("$script" 0.13.0 v0.12.11-fork.2)" = "0.13.0-fork.1" ] || fail "a higher upstream base starts at 1"
    for bad in "0.12" "v0.12.11" "0.12.11-fork.1" "x.y.z" "" "0.12.11;ls"; do
        "$script" "$bad" > /dev/null 2>&1 && fail "accepted the base '$bad'"
    done
    for bad in "0.12.11-fork.1" "v0.12.11" "v0.12.11-fork" "v0.12.11-fork.x" "v0.12.11-beta.1"; do
        out="$("$script" 0.12.11 "$bad" 2>&1)" && fail "accepted the tag '$bad': $out"
    done
    "$script" > /dev/null 2>&1 && fail "accepted no arguments"
    return 0
}

test_sync_merge() {
    local script="$ROOT/Scripts/fork-sync-merge.sh" d="$WORK/sm" out dev up
    [ -x "$script" ] || {
        fail "Scripts/fork-sync-merge.sh is missing or not executable"
        return
    }
    # A clean merge: both sides change different files.
    make_sync_repo "$d-clean"
    on_branch "$d-clean" dev bash -c 'echo fork > fork.txt'
    on_branch "$d-clean" up bash -c 'echo newline >> Tinycast/Core.swift'
    (cd "$d-clean" && gitq checkout -q dev)
    out="$(cd "$d-clean" && GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t "$script" dev up)" \
        || fail "a clean merge failed: $out"
    [ "$out" = "$(cd "$d-clean" && git rev-parse HEAD)" ] || fail "a clean merge should print the merge commit"
    [ "$(cd "$d-clean" && git rev-list --parents -n 1 HEAD | wc -w | tr -d ' ')" = 3 ] || fail "the merge must have two parents"
    if [ ! -f "$d-clean/fork.txt" ] || ! grep -q newline "$d-clean/Tinycast/Core.swift"; then
        fail "both sides' changes must be in the merge"
    fi
    [ -z "$(cd "$d-clean" && git status --porcelain)" ] || fail "the work tree should be clean after a merge"

    # A conflict: both sides change the same line.
    make_sync_repo "$d-conf"
    on_branch "$d-conf" dev bash -c "sed -i '' 's/two/fork-two/' Tinycast/Core.swift"
    on_branch "$d-conf" up bash -c "sed -i '' 's/two/up-two/' Tinycast/Core.swift"
    (cd "$d-conf" && gitq checkout -q dev)
    dev="$(cd "$d-conf" && git rev-parse HEAD)"
    out="$(cd "$d-conf" && "$script" dev up 2>&1)"
    [ $? -eq 10 ] || fail "a conflict must exit 10"
    assert_contains "$out" "Tinycast/Core.swift"
    [ "$(cd "$d-conf" && git rev-parse HEAD)" = "$dev" ] || fail "a conflict must leave dev untouched"
    [ -z "$(cd "$d-conf" && git status --porcelain)" ] || fail "a conflict must leave a clean work tree"
    (cd "$d-conf" && git show refs/fork-sync/conflicted:Tinycast/Core.swift) | grep -q '<<<<<<<' \
        || fail "the conflicted state must be saved with its markers"

    # Workflows are pinned to dev's version: edited, added and conflicting.
    make_sync_repo "$d-wf"
    on_branch "$d-wf" dev bash -c 'echo forked > .github/workflows/up.yml; echo fork > fork.txt'
    on_branch "$d-wf" up bash -c 'echo changed > .github/workflows/up.yml; echo new > .github/workflows/new.yml;
        echo changed > .github/workflows/ours.yml; echo more >> Tinycast/Core.swift'
    (cd "$d-wf" && gitq checkout -q dev)
    dev="$(cd "$d-wf" && git rev-parse HEAD)"
    out="$(cd "$d-wf" && GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t "$script" dev up 2>&1)" \
        || fail "a merge with workflow changes failed: $out"
    [ -z "$(cd "$d-wf" && git diff --name-only "$dev" HEAD -- .github)" ] || fail ".github must equal dev's after the merge"
    [ ! -e "$d-wf/.github/workflows/new.yml" ] || fail "an upstream workflow must not land"
    grep -q more "$d-wf/Tinycast/Core.swift" || fail "the rest of upstream must still merge"

    # Already up to date.
    make_sync_repo "$d-same"
    out="$(cd "$d-same" && "$script" dev up 2>&1)"
    [ $? -eq 3 ] || fail "nothing to merge must exit 3"
    # Bad calls.
    "$script" > /dev/null 2>&1 && fail "accepted no arguments"
    make_sync_repo "$d-dirty"
    on_branch "$d-dirty" dev bash -c 'echo fork > fork.txt'
    on_branch "$d-dirty" up bash -c 'echo more >> Tinycast/Core.swift'
    (cd "$d-dirty" && gitq checkout -q dev && echo dirty > a.txt && "$script" dev up > /dev/null 2>&1)
    [ $? -eq 2 ] || fail "must refuse, with exit 2, to merge into a dirty work tree"
    [ "$(cd "$d-dirty" && git rev-parse HEAD)" = "$(cd "$d-dirty" && git rev-parse dev)" ] || fail "a refused merge must not move dev"
    return 0
}

# forge DIR CANDIDATE DEV UP COMMAND...: a new commit with the candidate's tree plus a change.
forge() {
    local dir="$1" cand="$2" dev="$3" up="$4"
    shift 4
    (cd "$dir" && gitq reset -q --hard && gitq clean -fdq && gitq checkout -q --detach "$cand" && "$@" && gitq add -A \
        && sha="$(gitq commit-tree -p "$dev" -p "$up" -m forged "$(gitq write-tree)")" \
        && gitq reset -q --hard && gitq clean -fdq && echo "$sha")
}

test_sync_verify_tree() {
    local script="$ROOT/Scripts/fork-sync-verify-tree.sh" d="$WORK/vt" dev up cand bad base
    [ -x "$script" ] || {
        fail "Scripts/fork-sync-verify-tree.sh is missing or not executable"
        return
    }
    expect_ok() { (cd "$d" && "$script" "$dev" "$up" "$1" > /dev/null 2>&1) || fail "refused: $2"; }
    expect_bad() { (cd "$d" && "$script" "$dev" "$up" "$1" > /dev/null 2>&1) && fail "accepted: $2"; return 0; }

    make_sync_repo "$d"
    on_branch "$d" dev bash -c 'echo fork > fork.txt'
    on_branch "$d" up bash -c 'echo newline >> Tinycast/Core.swift; echo changed > .github/workflows/up.yml'
    dev="$(cd "$d" && git rev-parse dev)"
    up="$(cd "$d" && git rev-parse up)"
    # The genuine result of the merge script.
    (cd "$d" && gitq checkout -q dev && GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t \
        "$ROOT/Scripts/fork-sync-merge.sh" dev up > /dev/null) || fail "setup: the merge failed"
    cand="$(cd "$d" && git rev-parse HEAD)"
    expect_ok "$cand" "the genuine clean merge"

    bad="$(forge "$d" "$cand" "$dev" "$up" bash -c 'echo evil >> a.txt')"
    expect_bad "$bad" "a change to a file that merged cleanly"
    bad="$(forge "$d" "$cand" "$dev" "$up" bash -c 'echo evil > .github/workflows/ours.yml')"
    expect_bad "$bad" "a change under .github"
    bad="$(forge "$d" "$cand" "$dev" "$up" bash -c 'echo evil > Scripts/fork-x.sh')"
    expect_bad "$bad" "an edit to a fork script"
    bad="$(forge "$d" "$cand" "$dev" "$up" bash -c 'echo evil > docs/fork/x.md')"
    expect_bad "$bad" "an edit to the fork docs"
    bad="$(forge "$d" "$cand" "$dev" "$up" bash -c 'printf "<<<<<<< HEAD\n" >> Tinycast/Core.swift')"
    expect_bad "$bad" "a leftover conflict marker"
    bad="$(cd "$d" && gitq commit-tree -p "$up" -p "$dev" -m swapped "$cand^{tree}")"
    expect_bad "$bad" "swapped parents"
    bad="$(cd "$d" && gitq commit-tree -p "$(git merge-base "$dev" "$up")" -p "$up" -m wrongfirst "$cand^{tree}")"
    expect_bad "$bad" "the wrong first parent"
    base="$(cd "$d" && git merge-base "$dev" "$up")"
    bad="$(cd "$d" && gitq commit-tree -p "$dev" -p "$up" -p "$base" -m three "$cand^{tree}")"
    expect_bad "$bad" "three parents"
    bad="$(cd "$d" && gitq commit-tree -p "$dev" -m one "$cand^{tree}")"
    expect_bad "$bad" "a single parent"
    bad="$(cd "$d" && gitq commit-tree -p "$dev" -p "$base" -m other "$cand^{tree}")"
    expect_bad "$bad" "the wrong second parent"
    (cd "$d" && "$script" > /dev/null 2>&1) && fail "accepted no arguments"

    # A conflict, resolved by changing only the conflicted file.
    make_sync_repo "$d-c"
    on_branch "$d-c" dev bash -c "sed -i '' 's/two/fork-two/' Tinycast/Core.swift"
    on_branch "$d-c" up bash -c "sed -i '' 's/two/up-two/' Tinycast/Core.swift; echo more > upstream.txt"
    dev="$(cd "$d-c" && git rev-parse dev)"
    up="$(cd "$d-c" && git rev-parse up)"
    (cd "$d-c" && gitq checkout -q dev && "$ROOT/Scripts/fork-sync-merge.sh" dev up > /dev/null 2>&1)
    cand="$(cd "$d-c" && git rev-parse refs/fork-sync/conflicted)"
    d="$d-c"
    bad="$(forge "$d" "$cand" "$dev" "$up" bash -c "printf 'one\nfork-up-two\nthree\n' > Tinycast/Core.swift")"
    expect_ok "$bad" "a resolution that changes only the conflicted file"
    bad="$(forge "$d" "$cand" "$dev" "$up" bash -c "printf 'one\nfork-up-two\nthree\n' > Tinycast/Core.swift; echo evil >> a.txt")"
    expect_bad "$bad" "a resolution that also changes another file"
    expect_bad "$cand" "the conflicted state with its markers still in"
    bad="$(forge "$d" "$cand" "$dev" "$up" bash -c "printf 'one\nx\nthree\n' > Tinycast/Core.swift; rm upstream.txt")"
    expect_bad "$bad" "a resolution that drops a file upstream added"

    # A conflict in one of the fork's own files may not be resolved by the sync at all.
    local path fx
    for path in Scripts/fork-y.sh docs/fork/y.md; do
        fx="$WORK/vt-fx-${path//\//_}"
        make_sync_repo "$fx"
        on_branch "$fx" dev bash -c "mkdir -p \"\$(dirname $path)\" && echo dev > $path"
        on_branch "$fx" up bash -c "mkdir -p \"\$(dirname $path)\" && echo up > $path"
        dev="$(cd "$fx" && git rev-parse dev)"
        up="$(cd "$fx" && git rev-parse up)"
        (cd "$fx" && gitq checkout -q dev && "$ROOT/Scripts/fork-sync-merge.sh" dev up > /dev/null 2>&1)
        cand="$(cd "$fx" && git rev-parse refs/fork-sync/conflicted)" || {
            fail "setup: no conflicted ref for $path"
            continue
        }
        bad="$(forge "$fx" "$cand" "$dev" "$up" bash -c "echo resolved > $path")"
        (cd "$fx" && "$script" "$dev" "$up" "$bad" > /dev/null 2>&1) && fail "accepted: a resolution of a conflict in $path"
    done
    return 0
}

test_sync_decide() {
    local script="$ROOT/Scripts/fork-sync-decide.sh" d="$WORK/sd"
    [ -x "$script" ] || {
        fail "Scripts/fork-sync-decide.sh is missing or not executable"
        return
    }
    decide() { (cd "$d" && "$script" last dev 2> /dev/null); }
    make_sync_repo "$d"
    (cd "$d" && gitq checkout -q dev && gitq tag last)
    [ "$(decide)" = skip ] || fail "no new commits should be skip"
    on_branch "$d" dev bash -c 'echo x >> docs/fork/x.md; echo y >> website/index.md; mkdir -p docs && echo z > docs/new.md'
    [ "$(decide)" = skip ] || fail "docs and website only should be skip"
    on_branch "$d" dev bash -c 'echo x >> Tinycast/Core.swift'
    [ "$(decide)" = release ] || fail "an app change should be release"
    (cd "$d" && gitq commit --allow-empty -qm "Merge" -m "Resolved-by: claude")
    [ "$(decide)" = hold ] || fail "a Claude-resolved merge should be hold"
    # A look-alike directory counts as code.
    make_sync_repo "$d-2"
    (cd "$d-2" && gitq checkout -q dev && gitq tag last)
    on_branch "$d-2" dev bash -c 'mkdir -p docs-evil && echo x > docs-evil/x'
    (cd "$d-2" && [ "$("$script" last dev)" = release ]) || fail "docs-evil/ must count as code"
    make_sync_repo "$d-3"
    (cd "$d-3" && gitq checkout -q dev && gitq tag last)
    on_branch "$d-3" dev bash -c 'mkdir -p website2 && echo x > website2/x'
    (cd "$d-3" && [ "$("$script" last dev)" = release ]) || fail "website2/ must count as code"
    # A path with a newline in it, and a docs/.. trick, count as code.
    make_sync_repo "$d-4"
    (cd "$d-4" && gitq checkout -q dev && gitq tag last)
    on_branch "$d-4" dev bash -c "printf x > \$'docs/a\nb'"
    (cd "$d-4" && [ "$("$script" last dev)" != skip ]) || fail "a docs path with a newline must not hide a change"
    # A missing tag is an error, never a silent skip.
    (cd "$d" && "$script" nosuchtag dev > /dev/null 2>&1) && fail "accepted a missing tag"
    "$script" > /dev/null 2>&1 && fail "accepted no arguments"
    return 0
}

ALL=(validate_accepts validate_rejects build_print_settings import_requires_env import_cleanup_is_safe
    package_ok package_rejects package_authority package_relative_paths notes_licence_items notes_rejects cask_contents cask_rejects cask_from_release cask_style
    bootstrap_dry_run bootstrap_environments_calls bootstrap_identity_calls bootstrap_tap_calls
    bootstrap_refuses_overwrite bootstrap_no_leftovers bootstrap_rejects_bad_args
    workflow_static update_path
    next_version sync_merge sync_verify_tree sync_decide)

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
