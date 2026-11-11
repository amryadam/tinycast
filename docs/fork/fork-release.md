# Feature: fork-release

Builds, signs and publishes the fork from GitHub, and installs it with Homebrew.
The spec is [fork-release-spec.md](fork-release-spec.md) and the plan is [fork-release-plan.md](fork-release-plan.md).
The fork's rules are in [README.md](README.md).

## Contents

- [Status](#status)
- [Files](#files)

## Status

Done and live.
Release [v0.12.11-fork.1](https://github.com/amryadam/tinycast/releases/tag/v0.12.11-fork.1) was built and published by the workflow, and the cask is in [amryadam/homebrew-fork](https://github.com/amryadam/homebrew-fork).
Run the tests with `./Scripts/fork-test.sh`.
`Scripts/fork-build.sh` is listed in [fork-identity.md](fork-identity.md); this feature adds `FORK_VERSION`, `FORK_BUILD_NUMBER`, `--print-settings` and the arm64 pin to it.

## Results of the first runs

| Check | Result |
|---|---|
| Dry run (`publish` off) | Passed first time. The `xcode-27` runner started, the cask lint passed, and xcodebuild accepted the self-signed identity. |
| Downloaded artifact and released zip | Checksum matches, `codesign --verify --deep --strict` passes, signed by `Tinycast Self-Signed`, bundle id `com.amryadam.tinycast`, version 0.12.11, arm64 only. |
| Zip contents | The app, `LICENSE`, `NOTICE.md` and `FORK-NOTICE.md`. |
| Cask in the tap | Names the same version and the same SHA-256 as the released asset. |
| Release | Tag on the `dev` commit that was built, marked latest, with notes carrying the AGPL items. |
| Not yet checked | `brew install` from the tap, and the first launch under Gatekeeper. |

The signing identity's certificate fingerprint (SHA-256) is `E6:6E:5C:6C:D4:36:FD:02:DB:4A:C0:80:A4:7B:46:9C:E9:43:97:FE:63:89:74:A9:7C:94:BF:D3:20:80:DD:26`.
Check it with `codesign -dvvv` on an installed copy, or with `openssl`, to be sure the same identity signs every release.

## Files

| File | Change | Purpose | Conflict risk |
|---|---|---|---|
| `docs/fork/fork-release.md` | New | This file. | None |
| `docs/fork/fork-release-spec.md` | New | The spec. | None |
| `docs/fork/fork-release-plan.md` | New | The plan. | None |
| `Scripts/fork-test.sh` | New | Runs the tests of every release script, with no network or identity. | None |
| `Scripts/fork-release-validate.sh` | New | Accepts only `MAJOR.MINOR.PATCH-fork.N` and prints the base version. | None |
| `Scripts/fork-import-identity.sh` | New | CI only: imports the signing identity into a throwaway keychain, and removes it with `--cleanup`. | None |
| `Scripts/fork-package.sh` | New | Verifies the built app and zips it with the licence files and a SHA-256. | None |
| `Scripts/fork-release-notes.sh` | New | Prints release notes that carry the AGPL notice, source link and install steps. | None |
| `Scripts/fork-cask.sh` | New | Writes the Homebrew cask, or rebuilds it from a release's checksum asset. | None |
| `.github/workflows/fork-release.yml` | New | The manual workflow: a build job that holds the signing key, and a publish job that releases and updates the tap. | None |
| `Scripts/fork-bootstrap.sh` | New | One-time setup of the environments, the tap with its deploy key, and the signing identity secrets, with `--dry-run`. | None |
