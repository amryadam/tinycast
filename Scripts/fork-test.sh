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
        "path-query" "brew tap amryadam/fork" "brew trust --cask amryadam/fork/tinycast-fork" "brew install --cask amryadam/fork/tinycast-fork" \
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
    local out
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
    assert_lacks "$build" "gh release"
    assert_lacks "$build" "git push"
    assert_lacks "$build" "TAP_DEPLOY_KEY"
    assert_contains "$build" "SIGNING_P12_BASE64"
    assert_contains "$build" "SIGNING_P12_PASSWORD"
    assert_contains "$build" "--require-authority"
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
}

ALL=(validate_accepts validate_rejects build_print_settings import_requires_env import_cleanup_is_safe
    package_ok package_rejects package_authority notes_licence_items notes_rejects cask_contents cask_rejects cask_from_release cask_style
    bootstrap_dry_run bootstrap_environments_calls bootstrap_identity_calls bootstrap_tap_calls
    bootstrap_refuses_overwrite bootstrap_no_leftovers bootstrap_rejects_bad_args
    workflow_static)

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
