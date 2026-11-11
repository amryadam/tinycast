# Feature: fork-update

Makes the fork its own update channel in the app, so a new fork release appears in the update pill and installs at the next relaunch.
The plan is [fork-update-sync-plan.md](fork-update-sync-plan.md), and the fork's rules are in [README.md](README.md).

## Contents

- [How it works](#how-it-works)
- [Known limits](#known-limits)
- [Files](#files)

## How it works

The app's existing updater (see `docs/features/updates.md`) picks a channel from the bundle id.
The fork's bundle id, `com.amryadam.tinycast`, is now the `fork` channel instead of `development`.

| Part | Behaviour |
|---|---|
| Feed | The `fork` channel reads `https://api.github.com/repos/amryadam/tinycast/releases`. Stable and beta still read upstream's. |
| Versions | `0.12.11-fork.2` parses, is not a prerelease, and sorts above `0.12.11-fork.1` and above its plain base. The fork takes only fork revisions, and no other channel takes them. |
| Trust | A release has no `.sig`, so the downloaded bundle must satisfy the running copy's own designated requirement. All releases are signed by the same GitHub-held identity, so they do. |
| Install | The updater downloads the zip, verifies it, stages it, and swaps it in at quit, exactly as for upstream's channels. |

## Release pipeline changes

| Change | Why |
|---|---|
| The app's version string is the full `0.12.11-fork.N`. | The running app must know its fork number to compare. `fork-package.sh` checks it. |
| The cask declares `auto_updates true`. | Otherwise `brew upgrade` would fight the in-app update. |
| `Fork release` checks the new app against the previous release's designated requirement. | A changed signing identity would lock every installed copy out of updates. |
| `Fork release` takes an optional `expected_sha`. | A sync can require the release to build exactly the commit it verified. |

## Known limits

- A copy built on this Mac with a different local key refuses a GitHub update, because its signature differs. Install the GitHub build.
- The pill shows when the palette opens, and `Check for Updates` appears in the palette.
- macOS may refuse the swap into `/Applications` for a bundle with no Team ID. Only a real update on a real Mac shows whether it does.

## Files

| File | Change | Purpose | Conflict risk |
|---|---|---|---|
| `docs/fork/fork-update.md` | New | This file. | None |
| `docs/fork/fork-update-sync-plan.md` | New | The plan for this feature and for the sync. | None |
| `Tinycast/Features/Updates/Model/AppVersion.swift` | Edit | Parses and orders `-fork.N`. | Low |
| `Tinycast/Features/Updates/Model/ReleaseChannel.swift` | Edit | The `fork` channel and its repository. | Low |
| `Tinycast/Features/Updates/Model/ReleaseFeed.swift` | Edit | The per-channel releases URL, and the fork-only filter. | Low |
| `Tinycast/Features/Updates/Service/UpdateCheckStore.swift` | Edit | Builds its default request from the channel. | Low |
| `Tests/fork-update-test.swift` | New | Tests for versions, channels, the URL and the feed. | None |
| `Scripts/run-tests.sh` | Edit | Runs the new test. | Low |
| `Scripts/fork-check-update-path.sh` | New | Refuses a release that installed copies would refuse to update to. | None |
