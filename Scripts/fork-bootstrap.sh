#!/bin/bash
# One-time setup of the fork's release machinery on GitHub, run from your Mac.
#
#   ./Scripts/fork-bootstrap.sh environments [--dry-run]
#   ./Scripts/fork-bootstrap.sh rulesets     [--dry-run]
#   ./Scripts/fork-bootstrap.sh tap          [--dry-run] [--force]
#   ./Scripts/fork-bootstrap.sh identity     [--dry-run] [--force]
#   Options: --repo OWNER/NAME (the fork, default amryadam/tinycast)
#            --tap  OWNER/NAME (the Homebrew tap, default amryadam/homebrew-fork)
#
#   environments  Creates the environments fork-build, fork-publish, fork-sync and fork-sync-claude,
#                 each usable from dev only.
#   rulesets      Protects dev from deletion and force pushes, and the release tags v*-fork.* from
#                 being moved or deleted. No pull request is demanded, because the sync pushes to dev.
#   tap           Creates the public tap repository, makes a deploy key for it, and stores the
#                 private key as TAP_DEPLOY_KEY in fork-publish.
#   identity      Makes the Tinycast Self-Signed code-signing identity and stores it as
#                 SIGNING_P12_BASE64 and SIGNING_P12_PASSWORD in fork-build.
#
# --dry-run changes nothing on GitHub. Secrets go to GitHub on standard input, never in an
# argument, and key material lives only in a private temporary folder that is deleted on exit.
# The identity is never imported into any keychain on this Mac.
# tap and identity refuse to replace a secret that exists unless given --force, because a new
# identity makes macOS forget every permission granted to the app.
# environments and rulesets are safe to repeat: they only add what is missing.

set -euo pipefail

# The system LibreSSL, whose .p12 files `security import` accepts; a Homebrew OpenSSL 3 may not.
OPENSSL=/usr/bin/openssl
IDENTITY_NAME="Tinycast Self-Signed"
DEPLOY_KEY_TITLE="tinycast-fork release publish"

die() {
    echo "✗ $*" >&2
    exit 1
}

usage() {
    echo "usage: fork-bootstrap.sh environments|rulesets|tap|identity [--dry-run] [--force] [--repo OWNER/NAME] [--tap OWNER/NAME]" >&2
    exit 2
}

[ $# -ge 1 ] || usage
SUB="$1"
shift
case "$SUB" in
    environments | rulesets | tap | identity) ;;
    *) usage ;;
esac

DRY=0
FORCE=0
REPO=amryadam/tinycast
TAP=amryadam/homebrew-fork
while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run) DRY=1 ;;
        --force) FORCE=1 ;;
        --repo)
            [ $# -ge 2 ] || usage
            REPO="$2"
            shift
            ;;
        --tap)
            [ $# -ge 2 ] || usage
            TAP="$2"
            shift
            ;;
        *) usage ;;
    esac
    shift
done
[[ "$REPO" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || die "--repo '$REPO' is not of the form OWNER/NAME"
[[ "$TAP" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || die "--tap '$TAP' is not of the form OWNER/NAME"

# gh_write ARGS...: runs gh, or only says so on a dry run. Standard input passes through.
gh_write() {
    if [ "$DRY" -eq 1 ]; then
        echo "dry run: would run: gh $*" >&2
    else
        gh "$@"
    fi
}

# secret_exists ENVIRONMENT NAME
secret_exists() {
    local names
    names="$(gh secret list --env "$1" --repo "$REPO" --json name --jq '.[].name')" \
        || die "cannot list the secrets of environment '$1' in $REPO (run the 'environments' step first?)"
    grep -qxF "$2" <<< "$names"
}

# refuse_existing ENVIRONMENT NAME...: stops before anything is generated when a secret exists.
refuse_existing() {
    local env="$1" name
    shift
    for name in "$@"; do
        if secret_exists "$env" "$name" && [ "$FORCE" -eq 0 ]; then
            die "the secret $name already exists in environment $env. Replacing it makes macOS forget the permissions granted to the app. Give --force if you mean it."
        fi
    done
}

# Key material goes here and nowhere else.
make_work() {
    # An explicit template, because on macOS a bare mktemp -d ignores TMPDIR.
    WORK="$(mktemp -d "${TMPDIR:-/tmp}/fork-bootstrap.XXXXXXXX")"
    chmod 700 "$WORK"
    trap 'rm -rf "$WORK"' EXIT
}

do_environments() {
    local env policies
    for env in fork-build fork-publish fork-sync fork-sync-claude; do
        gh_write api -X PUT "repos/$REPO/environments/$env" --input - \
            <<< '{"deployment_branch_policy":{"protected_branches":false,"custom_branch_policies":true}}' > /dev/null
        policies="$(gh api "repos/$REPO/environments/$env/deployment-branch-policies" \
            --jq '.branch_policies[].name' 2> /dev/null || true)"
        if grep -qxF dev <<< "$policies"; then
            echo "✓ $env already allows the branch dev"
        else
            gh_write api -X POST "repos/$REPO/environments/$env/deployment-branch-policies" --input - \
                <<< '{"name":"dev","type":"branch"}' > /dev/null
        fi
    done
    echo "✓ Environments fork-build, fork-publish, fork-sync and fork-sync-claude are limited to the branch dev in $REPO."
}

do_rulesets() {
    local existing
    existing="$(gh api "repos/$REPO/rulesets" --jq '.[].name' 2> /dev/null || true)"
    if grep -qxF protect-dev <<< "$existing"; then
        echo "✓ protect-dev already exists"
    else
        gh_write api -X POST "repos/$REPO/rulesets" --input - > /dev/null <<< '{"name":"protect-dev","target":"branch","enforcement":"active","bypass_actors":[],"conditions":{"ref_name":{"include":["refs/heads/dev"],"exclude":[]}},"rules":[{"type":"deletion"},{"type":"non_fast_forward"}]}'
    fi
    if grep -qxF protect-fork-tags <<< "$existing"; then
        echo "✓ protect-fork-tags already exists"
    else
        gh_write api -X POST "repos/$REPO/rulesets" --input - > /dev/null <<< '{"name":"protect-fork-tags","target":"tag","enforcement":"active","bypass_actors":[],"conditions":{"ref_name":{"include":["refs/tags/v*-fork.*"],"exclude":[]}},"rules":[{"type":"deletion"},{"type":"update"},{"type":"non_fast_forward"}]}'
    fi
    echo "✓ dev and the release tags are protected in $REPO."
}

do_tap() {
    local id old_ids=""
    refuse_existing fork-publish TAP_DEPLOY_KEY
    make_work
    ssh-keygen -q -t ed25519 -N "" -C "$DEPLOY_KEY_TITLE" -f "$WORK/deploy_key"

    if gh repo view "$TAP" > /dev/null 2>&1; then
        echo "✓ $TAP already exists"
        # Old keys of ours are removed only after the new key and its secret are in place, so a
        # failure part way never leaves publishing without a working key.
        old_ids="$(gh repo deploy-key list --repo "$TAP" --json id,title \
            --jq ".[] | select(.title==\"$DEPLOY_KEY_TITLE\") | .id" 2> /dev/null || true)"
    else
        gh_write repo create "$TAP" --public --add-readme --description "Homebrew tap for the Tinycast Fork"
    fi
    gh_write repo deploy-key add "$WORK/deploy_key.pub" --repo "$TAP" --title "$DEPLOY_KEY_TITLE" --allow-write
    gh_write secret set TAP_DEPLOY_KEY --env fork-publish --repo "$REPO" < "$WORK/deploy_key"
    for id in $old_ids; do
        gh_write repo deploy-key delete "$id" --repo "$TAP"
    done
    echo "✓ $TAP has a write deploy key, and its private half is the secret TAP_DEPLOY_KEY in fork-publish."
}

do_identity() {
    local pass
    refuse_existing fork-build SIGNING_P12_BASE64 SIGNING_P12_PASSWORD
    make_work
    pass="$("$OPENSSL" rand -hex 16)"

    "$OPENSSL" req -x509 -newkey rsa:2048 -nodes -days 3650 \
        -keyout "$WORK/key.pem" -out "$WORK/cert.pem" \
        -subj "/CN=$IDENTITY_NAME" \
        -addext "basicConstraints=critical,CA:false" \
        -addext "keyUsage=critical,digitalSignature" \
        -addext "extendedKeyUsage=critical,codeSigning" 2> /dev/null
    P12_PASS="$pass" "$OPENSSL" pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
        -name "$IDENTITY_NAME" -out "$WORK/identity.p12" -passout env:P12_PASS
    # It must open with that password before anything is uploaded.
    P12_PASS="$pass" "$OPENSSL" pkcs12 -in "$WORK/identity.p12" -passin env:P12_PASS -nodes 2> /dev/null \
        | "$OPENSSL" x509 -noout -subject 2> /dev/null | grep -q "$IDENTITY_NAME" \
        || die "the generated identity does not open"

    base64 < "$WORK/identity.p12" | tr -d '\n' > "$WORK/identity.b64"
    gh_write secret set SIGNING_P12_BASE64 --env fork-build --repo "$REPO" < "$WORK/identity.b64"
    printf '%s' "$pass" | gh_write secret set SIGNING_P12_PASSWORD --env fork-build --repo "$REPO"
    echo "✓ The identity '$IDENTITY_NAME' is stored in environment fork-build of $REPO."
    echo "  certificate $("$OPENSSL" x509 -in "$WORK/cert.pem" -noout -fingerprint -sha256)"
}

case "$SUB" in
    environments) do_environments ;;
    rulesets) do_rulesets ;;
    tap) do_tap ;;
    identity) do_identity ;;
esac
if [ "$DRY" -eq 1 ]; then
    echo "dry run: nothing was changed."
fi
