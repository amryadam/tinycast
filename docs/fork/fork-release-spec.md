# Fork release: spec

Feature spec for building, publishing and installing the [amryadam/tinycast](https://github.com/amryadam/tinycast) fork from GitHub.
The implementation plan is [fork-release-plan.md](fork-release-plan.md).
The feature's change log is [fork-release.md](fork-release.md), and the fork's rules are in [README.md](README.md).
It builds on [fork-identity.md](fork-identity.md), which gives the app its own bundle id and name.
Revision 2: updated after an independent Opus review at high effort.

## Contents

- [Goal](#goal)
- [Non-goals](#non-goals)
- [Overview](#overview)
- [Environments and secrets](#environments-and-secrets)
- [The workflow](#the-workflow)
- [Versions, tags and notes](#versions-tags-and-notes)
- [Packaging](#packaging)
- [The cask and the tap](#the-cask-and-the-tap)
- [Safety controls](#safety-controls)
- [Verified and unverified](#verified-and-unverified)
- [Risks](#risks)
- [Decisions](#decisions)
- [Acceptance criteria](#acceptance-criteria)

## Goal

A release of the fork is built and signed on GitHub from a commit on `dev`, published on the fork's release page, and installable and upgradable with Homebrew.
No build runs on the user's Mac, and the user's keychain is never touched.

## Non-goals

| Not in scope | Why |
|---|---|
| Apple notarisation | It needs a paid Developer ID. A self-signed app is blocked by Gatekeeper until the user approves it once. |
| In-app auto-update | The bundle id is unknown to upstream, so the app is a development build that never updates itself. Homebrew upgrades it. |
| A DMG or a universal binary | The cask installs a zip, and the runner and the user's Mac are Apple silicon. |
| Running upstream's workflows | They need upstream's secrets and tap, and are disabled on the fork. |
| A fork notice in the About screen | A separate change, listed under Risks. |
| Upstreaming | The maintainer declined the feature. |

## Overview

| Stage | Where | Result |
|---|---|---|
| 1. Bootstrap | The user's Mac, never the keychain | Two environments, a tap repository with a deploy key, and the signing identity stored as secrets. |
| 2. Dry run | GitHub, `publish` off | A signed zip as a one-day workflow artifact, with nothing published. |
| 3. Release | GitHub, `publish` on | A GitHub release with the zip, and an updated cask in the tap. |
| 4. Install | The user's Mac | `brew tap` and `brew install --cask`. |

## Environments and secrets

Repository-level secrets can be read by a workflow on any branch, so secrets live in environments that only `dev` may use.

| Environment | Branch policy | Secret | Holds | Used by |
|---|---|---|---|---|
| `fork-build` | `dev` only | `SIGNING_P12_BASE64` | The signing identity, as a base64 `.p12` | The build job |
| `fork-build` | `dev` only | `SIGNING_P12_PASSWORD` | A random password for that file | The build job |
| `fork-publish` | `dev` only | `TAP_DEPLOY_KEY` | The private half of a write deploy key for the tap repository | The publish job |

- A bootstrap script creates the environments and their branch policies, generates the identity and the deploy key in a private temporary folder, uploads them, and deletes the files on exit.
- The identity is never imported into any keychain.
- The same identity must be used for every release, because macOS remembers permissions against the signature.
- The script refuses to run when the secrets already exist, unless given `--force`, because replacing the identity makes macOS forget every permission.
- GitHub cannot return a secret's value, so losing the secret means making a new identity, after which the user grants permissions again.
- The identity made locally by `fork-signing-identity.sh` is a different key with the same name. A copy built locally and a copy built on GitHub will not share permissions, so the user installs the GitHub build and does not alternate.

## The workflow

File: `.github/workflows/fork-release.yml`, a new file, so it cannot conflict with upstream.
GitHub starts a manual run only when the file is on the default branch, so `dev` becomes the fork's default branch.

```yaml
name: Fork release
on:
  workflow_dispatch:
    inputs:
      version:   # for example 0.12.11-fork.1
        type: string
        required: true
      publish:   # false builds and uploads an artifact only
        type: boolean
        default: false
permissions: {}
concurrency:
  group: fork-release
  cancel-in-progress: false
jobs:
  build:
    if: github.ref == 'refs/heads/dev'
    runs-on: xcode-27
    environment: fork-build
    permissions:
      contents: read
  publish:
    if: inputs.publish
    needs: build
    runs-on: ubuntu-latest
    environment: fork-publish
    permissions:
      contents: write
```

### The build job

It holds the signing key and can read the repository, but cannot write to it.

| Step | Detail |
|---|---|
| Validate | `Scripts/fork-release-validate.sh` accepts only `^[0-9]+\.[0-9]+\.[0-9]+-fork\.[0-9]+$`. |
| Checkout | Full history, `persist-credentials: false`. |
| Tag check | `gh api` fails the run when `v<version>` already exists. |
| Select Xcode | The newest real `Xcode_27.x` folder, as upstream's workflow does. |
| Gate | `FORK_BASE=origin/main ./Scripts/fork-check.sh` and `./Scripts/run-tests.sh file-search-path-test`. |
| Lint the cask | Before the key is imported, so Homebrew's gems never run beside it: a throwaway local tap, `brew style` and `brew audit --cask --strict`, with a placeholder checksum. |
| Import identity | `Scripts/fork-import-identity.sh`: a temporary keychain, unlocked, with the `.p12` imported, the key opened to `codesign` through a partition list, and the keychain on the search list. |
| Build | `./Scripts/fork-build.sh Release`, with the version and the run number. |
| Package | `Scripts/fork-package.sh`, which verifies the bundle and writes the zip and its SHA-256. |
| Remove the keychain | Straight after packaging, so the key is gone before the upload runs. |
| Upload | The zip and its checksum as an artifact kept for one day. |
| Clean up | `if: always()`: the same removal again, in case an earlier step failed first. |

### The publish job

It can write releases, and never sees the signing key.

| Step | Detail |
|---|---|
| Checkout and download | The repository for its scripts, and the build job's artifact. |
| Verify | The zip's SHA-256 equals the build job's. |
| Prepare the tap | Clone the tap with the deploy key, prove it can write with `git push --dry-run`, write the cask and commit it as `github-actions[bot]`. This comes first, so a bad key fails the run while nothing is public. |
| Release | `gh release create "v$VERSION" --target "$GITHUB_SHA" --latest`, with the zip, its checksum, and generated notes. A release that already exists with the same checksum is kept, so "Re-run failed jobs" works after a tap failure. |
| Push the tap | Push, retrying a rebase up to three times, aborting a failed rebase, never forcing. On failure it prints the `--from-release` recovery command. |
| Clean up | `if: always()`: delete the key file. |

Actions are pinned to a full commit SHA, and secrets are read only from `env:`.

## Versions, tags and notes

| Item | Rule |
|---|---|
| Input | `0.12.11-fork.1`, the upstream base version plus a fork revision |
| Tag | `v0.12.11-fork.1`, created on the built commit |
| `MARKETING_VERSION` | The part before `-fork`, so `0.12.11` |
| `CURRENT_PROJECT_VERSION` | `github.run_number` |
| Release title | `Tinycast Fork 0.12.11-fork.1` |
| Notes | Generated by `Scripts/fork-release-notes.sh` |

The notes carry the licence obligations of the AGPL-3.0-or-later:

- a statement that this is an unofficial, modified version of Tinycast by Abue Ammar, not affiliated with it, with the date;
- the upstream commit it is based on, taken from the merge base with `origin/main`;
- the list of fork features, taken from the `# Feature:` titles in `docs/fork/*.md`;
- a link to the exact source at the tag, and to the licence;
- the install commands, and the one-time Gatekeeper approval.

The fork stays public, so the source at the tag is available from the same place as the binary.

## Packaging

| Check | Pass condition |
|---|---|
| App name | `Tinycast Fork.app` |
| Bundle id | `com.amryadam.tinycast` |
| Version | `CFBundleShortVersionString` equals `MARKETING_VERSION` |
| Signature | `codesign --verify --deep --strict` passes |
| Signer | With `--require-authority`, the authority is `Tinycast Self-Signed`, and a different signer is refused |

The zip is built from a staging folder that holds `Tinycast Fork.app`, `LICENSE`, `NOTICE.md` and a generated `FORK-NOTICE.md` at its root, with `ditto -c -k --sequesterRsrc`.
The licence text, the notice of modification (with the date and upstream commit) and the source link therefore travel with the binary, as AGPL sections 5(a) and 6(d) ask, and the cask still installs only the app.
It is named `Tinycast-Fork-<version>.zip`.

## The cask and the tap

The tap is a separate public repository, `amryadam/homebrew-fork`, so a plain `brew tap amryadam/fork` works.
Upstream uses the same pattern, with a personal access token where this uses a deploy key.

```ruby
cask "tinycast-fork" do
  version "0.12.11-fork.1"
  sha256 "<sha256 of the zip>"

  url "https://github.com/amryadam/tinycast/releases/download/v#{version}/Tinycast-Fork-#{version}.zip"
  name "Tinycast Fork"
  desc "Unofficial fork of the Tinycast launcher"
  homepage "https://github.com/amryadam/tinycast"

  livecheck do
    url :url
    strategy :github_latest
    regex(/^v?(\d+(?:\.\d+)+-fork\.\d+)$/i)
  end

  depends_on arch: :arm64
  depends_on macos: :tahoe

  app "Tinycast Fork.app"

  uninstall quit: "com.amryadam.tinycast"

  zap trash: [
    "~/.config/com.amryadam.tinycast",
    "~/Library/Application Support/com.amryadam.tinycast",
    "~/Library/Caches/com.amryadam.tinycast",
    "~/Library/Caches/com.amryadam.tinycast.dictation",
    "~/Library/Preferences/com.amryadam.tinycast.plist",
  ]
end
```

| Item | Detail |
|---|---|
| Install | `brew tap amryadam/fork`, then `brew trust --cask amryadam/fork/tinycast-fork`, then `brew install --cask amryadam/fork/tinycast-fork`. Homebrew 7 refuses to load a cask from an untrusted tap, and the trust list is `~/.homebrew/trust.json`. |
| Upgrade | `brew upgrade --cask tinycast-fork` |
| Coexistence | The token and the app name differ from the official `tinycast` cask, so both can be installed. |
| Shared folders | The cask does not zap `~/Library/Caches/ClipboardTextHelper`, which both apps use. |
| Gatekeeper | The cask does not remove the quarantine. The first launch needs a one-time approval in System Settings, Privacy and Security. Homebrew carries that approval across upgrades while the signature stays the same. |
| Recovery | If the release exists but the tap push failed, `Scripts/fork-cask.sh --from-release VERSION` regenerates the cask and the user pushes it by hand. A run for an existing tag fails by design. |

## Safety controls

| Control | Effect |
|---|---|
| Dispatch only | No push, pull request or schedule can start it. |
| `dev` only | The job refuses other branches, and the environments reject them too, so another branch's workflow cannot read the secrets. |
| Two jobs | The job that holds the signing key cannot write, and the job that can write has no signing key. |
| `publish` defaults to off | A first run proves the build without publishing anything. |
| Tag collision | An existing tag stops the run before anything is built. |
| Input validation | A tested script rejects any version that is not the exact pattern, and the value is read from `env:`, never from an inline expression. |
| Pinned actions | Each `uses:` is a full commit SHA. |
| No stored git credentials | `persist-credentials: false` on every checkout. |
| Cleanup | The keychain, the `.p12` and the deploy key file are deleted even when a step fails. |
| Upstream workflows | Each is disabled on the fork with `gh workflow disable`, and the user re-checks `gh workflow list --all` after every upstream sync. |
| Syncing | Always `gh repo sync -b main`. The default branch is `dev`, and a sync without `-b` would act on it. |
| Short artifact life | The artifact is kept one day, since anyone signed in to GitHub can download a public repository's artifacts. |
| Logs | GitHub masks secrets, and the scripts never print key material. |

## Verified and unverified

| Claim | State |
|---|---|
| `xcode-27` is a standard GitHub-hosted label with Xcode 27.2, and `macos-26` has only Xcode 26. | Verified by the review from the runner-images repository |
| Upstream's release job runs on `xcode-27`. | Verified |
| `:tahoe` is a valid macOS symbol, and the app needs macOS 26.0. | Verified |
| The user's `gh` token has the `workflow` scope. | Verified |
| A self-signed signature keeps a stable designated requirement while the certificate is the same. | Verified from a signed sample app |
| The system LibreSSL makes `.p12` files that `security import` accepts. | Verified |
| `brew style` rejects `depends_on macos: ">= :tahoe"` and wants `:tahoe`. | Verified by the review |
| A job on the `xcode-27` runner starts for this fork. | Unverified. The dry run answers it. |
| `xcodebuild` accepts the untrusted identity on that runner. | Unverified. The dry run answers it. |
| The cask passes `brew audit --cask --strict`. | Unverified until the build job's lint step runs |
| The nested `Tinycast Dictation.app` needs no second Gatekeeper approval. | Unverified, because it needs a Mac with the build |
| Scheduled upstream workflows run on a fork. | Unverified. They are disabled either way. |

## Risks

| Risk | Mitigation |
|---|---|
| The `xcode-27` runner queues for a long time, as a preview image. | The dry run shows it. The fallback is a local build with a keychain identity. |
| The key is exposed to anyone who can push to `dev`. | The certificate is trusted by nothing, the environments allow only `dev`, and deleting the secrets revokes it. |
| The identity is lost or replaced. | The script refuses to overwrite, and a new identity means granting permissions again. |
| A published release cannot be fully retracted from caches. | `publish` is off by default, and the first release is a deliberate step. |
| A user installs a build that macOS has not notarised. | The notes say so, and the cask leaves the approval to the user. |
| The About screen says "© Abue Ammar, AGPL-3.0" and links to upstream's GitHub, email and Discord, with no modification notice, and fork users would report bugs to a maintainer who declined the feature. | A small follow-up change with a `FORK(fork-release)` hook. Section 5(a) of the AGPL wants the notice in the work itself, so this should be done before the release is shared widely. |
| Making `dev` the default branch changes what "Sync fork" does. | The rule above, and the README says it. |
| `identity` uploads two secrets one after the other, and the second upload can fail, leaving a password that does not match the file. | GitHub has no atomic write for two secrets. Re-run with `--force`; the release fails at the import step, not silently. |
| With `cancel-in-progress: false`, GitHub keeps one pending run, so a third dispatch cancels the second while the first runs. | Dispatch one release at a time. |
| The `.p12` password is passed to `security import -P` on a command line, and the keychain password with `-p`. | The runner is a single-tenant VM that is destroyed afterwards, the keychain password is random, and upstream's release does the same. |

## Decisions

| Id | Decision | State |
|---|---|---|
| D1 | The tap is a separate public repository `amryadam/homebrew-fork`, pushed to with a deploy key, and `dev` is the fork's default branch. | Recommended by the review, awaiting the user |
| D2 | The cask does not remove the quarantine. | Recommended, awaiting the user |
| D3 | The identity is uploaded as environment secrets by a script that never uses the keychain, and never overwrites without `--force`. | Approved as the GitHub route |
| D4 | Upstream's workflows are disabled individually. | Recommended, awaiting the user |
| D5 | The first run has `publish` off. | Recommended |
| D6 | Cask `tinycast-fork`, tag `v0.12.11-fork.1`, release title `Tinycast Fork 0.12.11-fork.1`. | Recommended |
| D7 | Do the About-screen fork notice before sharing the release widely. | Recommended, awaiting the user |

## Acceptance criteria

| Check | Pass condition |
|---|---|
| Script tests | `./Scripts/fork-test.sh` passes, and `shellcheck` is clean. |
| Workflow | `actionlint` is clean, and structural checks pass. |
| Notes | The generated notes contain every item in the licence list above. |
| Dry run | The workflow succeeds with `publish` off, and the artifact's signature, signer, bundle id and version verify on the user's Mac. |
| Release | The release has the zip, its checksum and the notes, and the tap's cask names the same version and SHA-256. |
| Install | `brew install --cask amryadam/fork/tinycast-fork` installs `Tinycast Fork.app` beside the official app. |
| `fork-check` | Exits 0. |
