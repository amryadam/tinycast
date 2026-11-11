#!/bin/bash
# Imports the fork's signing identity into a throwaway keychain on a CI runner, and removes it again.
#
#   P12_BASE64=... P12_PASSWORD=... RUNNER_TEMP=... ./Scripts/fork-import-identity.sh
#   RUNNER_TEMP=... ./Scripts/fork-import-identity.sh --cleanup
#
# CI ONLY. It puts a keychain on the user search list, so never run the import on a personal Mac.
# Nothing secret is printed. The keychain password is random and lives only in this process.
# Unlike upstream's script it downloads no certificate: the identity is self-signed, so there is no
# chain to build.

set -euo pipefail

: "${RUNNER_TEMP:?RUNNER_TEMP must be set}"
KEYCHAIN="$RUNNER_TEMP/fork-signing.keychain-db"

# The user keychain search list, one path per line, quotes and indentation removed.
search_list() {
    security list-keychains -d user | sed -e 's/^[[:space:]]*"//' -e 's/"[[:space:]]*$//'
}

# Sets the search list to the current one without $KEYCHAIN. A no-op when it is not on the list.
remove_from_search_list() {
    local keep=() line
    while IFS= read -r line; do
        [ -n "$line" ] && [ "$line" != "$KEYCHAIN" ] && keep+=("$line")
    done < <(search_list)
    if search_list | grep -qxF "$KEYCHAIN"; then
        security list-keychains -d user -s ${keep[@]+"${keep[@]}"}
    fi
}

if [ "${1:-}" = "--cleanup" ]; then
    # Safe to run when nothing was imported, and safe to run twice.
    remove_from_search_list
    if [ -e "$KEYCHAIN" ]; then
        security delete-keychain "$KEYCHAIN" > /dev/null 2>&1 || rm -f "$KEYCHAIN"
    fi
    rm -f "$RUNNER_TEMP/fork-signing.p12"
    echo "✓ Removed the temporary signing keychain."
    exit 0
fi

: "${P12_BASE64:?P12_BASE64 must be set}"
: "${P12_PASSWORD:?P12_PASSWORD must be set}"

P12="$RUNNER_TEMP/fork-signing.p12"
KPW="$(/usr/bin/openssl rand -base64 24)"
trap 'rm -f "$P12"' EXIT

base64 --decode <<< "$P12_BASE64" > "$P12"
security create-keychain -p "$KPW" "$KEYCHAIN"
security set-keychain-settings -lut 21600 "$KEYCHAIN"
security unlock-keychain -p "$KPW" "$KEYCHAIN"
security import "$P12" -k "$KEYCHAIN" -P "$P12_PASSWORD" -A -T /usr/bin/codesign > /dev/null
# Let codesign use the key without an interactive prompt.
security set-key-partition-list -S apple-tool:,apple: -s -k "$KPW" "$KEYCHAIN" > /dev/null

# Put the new keychain first, keeping the existing ones.
existing=()
while IFS= read -r line; do
    [ -n "$line" ] && existing+=("$line")
done < <(search_list)
security list-keychains -d user -s "$KEYCHAIN" ${existing[@]+"${existing[@]}"}

echo "✓ Imported the signing identity into a temporary keychain."
