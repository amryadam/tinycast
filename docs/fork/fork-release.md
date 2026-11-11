# Feature: fork-release

Builds, signs and publishes the fork from GitHub, and installs it with Homebrew.
The spec is [fork-release-spec.md](fork-release-spec.md) and the plan is [fork-release-plan.md](fork-release-plan.md).
The fork's rules are in [README.md](README.md).

## Contents

- [Status](#status)
- [Files](#files)

## Status

Spec and plan written, and Tasks 1 to 6 (every script and the workflow, with their tests) are done, and are awaiting review.
The workflow has never run: it is checked statically and its scripts are tested, but the runner, the identity and the tap are unproven until the dry run.
`Scripts/fork-build.sh` is listed in [fork-identity.md](fork-identity.md); this feature adds `FORK_VERSION`, `FORK_BUILD_NUMBER` and `--print-settings` to it.
Run the tests with `./Scripts/fork-test.sh`.
Nothing is published, and no secret is uploaded.

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
