#!/bin/bash
# Validates a fork release version and prints its base version.
#
#   ./Scripts/fork-release-validate.sh 0.12.11-fork.1    # prints 0.12.11
#
# The only accepted shape is MAJOR.MINOR.PATCH-fork.N. The value is later used in a tag, a file
# name and a Homebrew cask, so nothing else may pass, not even a trailing newline or space.

set -euo pipefail

if [ $# -ne 1 ]; then
    echo "usage: fork-release-validate.sh VERSION" >&2
    exit 2
fi

version="$1"
if [[ ! "$version" =~ ^([0-9]+\.[0-9]+\.[0-9]+)-fork\.[0-9]+$ ]]; then
    echo "✗ '$version' is not of the form MAJOR.MINOR.PATCH-fork.N (for example 0.12.11-fork.1)." >&2
    exit 1
fi
echo "${BASH_REMATCH[1]}"
