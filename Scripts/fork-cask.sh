#!/bin/bash
# Writes the Homebrew cask for a fork release.
#
#   ./Scripts/fork-cask.sh VERSION SHA256 [OUTPUT]
#   ./Scripts/fork-cask.sh --from-release VERSION [OUTPUT]
#
# OUTPUT defaults to Casks/tinycast-fork.rb. --from-release reads the SHA-256 from the release's
# .zip.sha256 asset with gh, which repairs a tap whose push failed after the release was made.
# FORK_REPO (default amryadam/tinycast) names the repository that holds the release.

set -euo pipefail
# The repository root, found without changing directory, so a relative OUTPUT stays relative to the caller.
HERE="$(cd "$(dirname "$0")/.." && pwd)"

usage() {
    echo "usage: fork-cask.sh VERSION SHA256 [OUTPUT]" >&2
    echo "       fork-cask.sh --from-release VERSION [OUTPUT]" >&2
    exit 2
}

die() {
    echo "✗ $*" >&2
    exit 1
}

REPO="${FORK_REPO:-amryadam/tinycast}"
[[ "$REPO" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || die "FORK_REPO '$REPO' is not of the form OWNER/NAME"

if [ "${1:-}" = "--from-release" ]; then
    [ $# -ge 2 ] && [ $# -le 3 ] || usage
    VERSION="$2"
    OUTPUT="${3:-Casks/tinycast-fork.rb}"
    "$HERE/Scripts/fork-release-validate.sh" "$VERSION" > /dev/null
    LINE="$(gh release download "v$VERSION" --repo "$REPO" \
        --pattern "Tinycast-Fork-$VERSION.zip.sha256" --output -)"
    SHA="$(sed -n '1p' <<< "$LINE" | cut -d' ' -f1)"
else
    [ $# -ge 2 ] && [ $# -le 3 ] || usage
    VERSION="$1"
    SHA="$2"
    OUTPUT="${3:-Casks/tinycast-fork.rb}"
    "$HERE/Scripts/fork-release-validate.sh" "$VERSION" > /dev/null
fi

[[ "$SHA" =~ ^[0-9a-f]{64}$ ]] || die "'$SHA' is not a lowercase 64-digit SHA-256"

mkdir -p "$(dirname "$OUTPUT")"
cat > "$OUTPUT" <<CASK
cask "tinycast-fork" do
  version "$VERSION"
  sha256 "$SHA"

  url "https://github.com/$REPO/releases/download/v#{version}/Tinycast-Fork-#{version}.zip"
  name "Tinycast Fork"
  desc "Unofficial fork of the Tinycast launcher"
  homepage "https://github.com/$REPO"

  livecheck do
    url :url
    strategy :github_latest
    regex(/^v?(\d+(?:\.\d+)+-fork\.\d+)\$/i)
  end

  auto_updates true
  depends_on arch: :arm64
  depends_on macos: :tahoe

  app "Tinycast Fork.app"

  uninstall quit: "com.amryadam.tinycast"

  zap trash: [
    "~/.config/com.amryadam.tinycast",
    "~/Library/Application Support/com.amryadam.tinycast",
    "~/Library/Application Support/CrashReporter/Tinycast Fork_*.plist",
    "~/Library/Caches/com.amryadam.tinycast",
    "~/Library/Caches/com.amryadam.tinycast.dictation",
    "~/Library/Preferences/com.amryadam.tinycast.plist",
  ]
end
CASK
echo "✓ $OUTPUT"
