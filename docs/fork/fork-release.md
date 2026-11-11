# Feature: fork-release

Builds, signs and publishes the fork from GitHub, and installs it with Homebrew.
The spec is [fork-release-spec.md](fork-release-spec.md) and the plan is [fork-release-plan.md](fork-release-plan.md).
The fork's rules are in [README.md](README.md).

## Contents

- [Status](#status)
- [Files](#files)

## Status

Spec and plan written, and Task 1 (version validation and the build's version settings) is done.
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
