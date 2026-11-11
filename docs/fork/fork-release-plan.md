# Fork release implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A tagged commit of the fork is built and signed on GitHub, published as a release, and installable with Homebrew.

**Architecture:** Small shell scripts do each job and are tested locally, and one new workflow file strings them together on the `xcode-27` runner.
The signing identity lives in two repository secrets, uploaded once by a script that never touches the keychain.
The cask lives in the fork repository itself, on its default branch `dev`, and the workflow updates it.

**Tech Stack:** Bash, GitHub Actions, `gh`, `xcodebuild`, `codesign`, Homebrew casks.

**Spec:** [fork-release-spec.md](fork-release-spec.md)

## Contents

- [Global constraints](#global-constraints)
- [Review focus](#review-focus)
- [File structure](#file-structure)
- [Task 1: Signing secret script](#task-1-signing-secret-script)
- [Task 2: Versioned build](#task-2-versioned-build)
- [Task 3: Packaging](#task-3-packaging)
- [Task 4: Release notes](#task-4-release-notes)
- [Task 5: Cask generator](#task-5-cask-generator)
- [Task 6: Workflow](#task-6-workflow)
- [Task 7: Review](#task-7-review)
- [Task 8: Publish the branches](#task-8-publish-the-branches)
- [Task 9: Dry run](#task-9-dry-run)
- [Task 10: First release](#task-10-first-release)
- [Task 11: Final review](#task-11-final-review)

## Global constraints

- Work in `/Users/amryadam/Github/tinycast-worktrees/fork-release` on branch `feature/fork-release`.
- Never read, print, log or commit key material, passwords or tokens.
- Every script starts with `set -euo pipefail`, passes `shellcheck`, and takes input only from arguments and environment variables.
- A workflow `run:` step reads inputs and secrets from `env:`, never from an inline `${{ }}` expression.
- Actions in the workflow are pinned to a full version.
- Push only to `origin`. Each outward step in Tasks 8 to 10 waits for the user's explicit yes.
- Commit subjects are short, imperative and capitalised, with no period and no attribution lines.
- Every hunk that edits an upstream file carries a `FORK(fork-release)` marker. This feature edits none.
- Use `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` for local `xcodebuild` and `xcrun`.

## Review focus

| Input or condition | Expected behaviour | Pinned in |
|---|---|---|
| A `version` input that carries shell syntax, such as `1.0.0-fork.1; rm -rf ~` | Rejected by the regex before any other step. | Task 6 |
| A tag that already exists | The run stops before building. | Task 6 |
| `dev` moves between checkout and release | The tag is created on the built commit, not on the new tip. | Task 6 |
| A failing step after the keychain import | The temporary keychain and key file are still deleted. | Task 6 |
| A secret or password in a log | Never printed, with no `set -x` around it. | Tasks 1 and 6 |
| The cask push races with a local push to `dev` | The workflow rebases and retries, and never force-pushes. | Task 6 |
| Release notes missing a licence item | A test fails. | Task 4 |

## File structure

| Planned file | Change | Task |
|---|---|---|
| `Scripts/fork-signing-secret.sh` | New | 1 |
| `Scripts/fork-build.sh` | Edited, the fork's own file | 2 |
| `Scripts/fork-package.sh` | New | 3 |
| `Scripts/fork-release-notes.sh` | New | 4 |
| `Scripts/fork-cask.sh` | New | 5 |
| `Scripts/fork-test.sh` | New, runs every test below | 1 to 5 |
| `.github/workflows/fork-release.yml` | New | 6 |
| `docs/fork/fork-release.md`, `fork-release-spec.md`, `fork-release-plan.md` | New | 6 |

## Task 1: Signing secret script

**Files:**
- Create: `Scripts/fork-signing-secret.sh`
- Create: `Scripts/fork-test.sh`

**Interfaces:**
- Produces: `./Scripts/fork-signing-secret.sh [--dry-run] [--repo OWNER/NAME]`. It prints the certificate's SHA-256 fingerprint and, without `--dry-run`, sets the secrets `SIGNING_P12_BASE64` and `SIGNING_P12_PASSWORD` on the repository (default `amryadam/tinycast`).
- Produces: `./Scripts/fork-test.sh [name]`, which runs the named test or all of them and exits non-zero on a failure.

- [ ] **Step 1: Write the failing test** `test_secret_dry_run` in `Scripts/fork-test.sh`. It runs the script with `--dry-run`, then asserts the output contains a 64-hex-digit fingerprint, contains the words `dry run`, does not contain `BEGIN`, and that no `*.p12` or `*.pem` file remains in the temp area the script reported.
- [ ] **Step 2: Run it and see it fail** with `./Scripts/fork-test.sh test_secret_dry_run`. Expected: the script is missing.
- [ ] **Step 3: Implement the script.** Use a `mktemp -d` folder with mode 700 and a `trap` that removes it. Generate the key and certificate with `/usr/bin/openssl`, as `Scripts/fork-signing-identity.sh` does, and pack them with a random password. Verify the `.p12` opens with that password. Compute the fingerprint from the certificate. Upload both values with `gh secret set --repo`, passing the values on standard input and never on the command line.
- [ ] **Step 4: Run the test.** Expected: pass.
- [ ] **Step 5: Run `shellcheck` on both scripts.** Expected: no output.
- [ ] **Step 6: Commit.**

```shell
git add Scripts/fork-signing-secret.sh Scripts/fork-test.sh
git commit -m "Add a script that stores the signing identity as repository secrets"
```

## Task 2: Versioned build

**Files:**
- Modify: `Scripts/fork-build.sh`
- Modify: `Scripts/fork-test.sh`

**Interfaces:**
- Consumes: the existing `FORK_BUNDLE_ID`, `FORK_URL_SCHEME`, `FORK_APP_NAME`, `FORK_BUILD_DIR`.
- Produces: two more optional variables, `FORK_VERSION` (passed as `MARKETING_VERSION`) and `FORK_BUILD_NUMBER` (passed as `CURRENT_PROJECT_VERSION`), each omitted from the `xcodebuild` call when unset.

- [ ] **Step 1: Write the failing test** `test_build_version_flags`. It runs an unsigned Debug `xcodebuild` with the same overrides the script passes plus `MARKETING_VERSION=9.8.7 CURRENT_PROJECT_VERSION=42`, and asserts the built `Info.plist` reports `CFBundleShortVersionString` 9.8.7 and `CFBundleVersion` 42. Mark it slow so `fork-test.sh` skips it unless asked by name.
- [ ] **Step 2: Add the two variables to the script**, and a `--print-settings` flag that prints the build settings it would pass and exits, so the arguments can be unit-tested without building.
- [ ] **Step 3: Write `test_build_print_settings`.** It asserts the printed settings include `MARKETING_VERSION=1.2.3` when `FORK_VERSION=1.2.3` is set, and do not mention it when unset.
- [ ] **Step 4: Run both tests.** Expected: pass.
- [ ] **Step 5: Commit.**

```shell
git add Scripts/fork-build.sh Scripts/fork-test.sh
git commit -m "Let the fork build take a version and a build number"
```

## Task 3: Packaging

**Files:**
- Create: `Scripts/fork-package.sh`
- Modify: `Scripts/fork-test.sh`

**Interfaces:**
- Produces: `./Scripts/fork-package.sh APP_PATH VERSION OUT_DIR`. It verifies the bundle, writes `OUT_DIR/Tinycast-Fork-VERSION.zip` and `OUT_DIR/Tinycast-Fork-VERSION.zip.sha256`, and prints the SHA-256.

- [ ] **Step 1: Write the failing tests.**
  - `test_package_ok` builds a minimal fake `Tinycast Fork.app` with a valid `Info.plist` (bundle id `com.amryadam.tinycast`, version 1.2.3), signs it ad-hoc, runs the script, and asserts the zip and checksum exist and the checksum matches `shasum -a 256`.
  - `test_package_rejects` asserts a non-zero exit for a wrong bundle id, a wrong version, an unsigned app, and a missing app.
- [ ] **Step 2: Run them and see them fail.**
- [ ] **Step 3: Implement the script.** Check the app name, the bundle id from `Info.plist`, `CFBundleShortVersionString` equal to the base version (the part of `VERSION` before `-fork`), and `codesign --verify --deep --strict`. A `--require-authority NAME` option additionally checks the signing authority, and the workflow passes `Tinycast Self-Signed`. Zip with `ditto -c -k --keepParent`.
- [ ] **Step 4: Run the tests and `shellcheck`.** Expected: pass and no output.
- [ ] **Step 5: Commit.**

```shell
git add Scripts/fork-package.sh Scripts/fork-test.sh
git commit -m "Add a packaging script that verifies the bundle before zipping it"
```

## Task 4: Release notes

**Files:**
- Create: `Scripts/fork-release-notes.sh`
- Modify: `Scripts/fork-test.sh`

**Interfaces:**
- Produces: `./Scripts/fork-release-notes.sh VERSION UPSTREAM_SHA REPO`, which prints Markdown notes to standard output.

- [ ] **Step 1: Write the failing test** `test_notes_licence_items`. It runs the script for `0.12.11-fork.1`, an upstream sha and `amryadam/tinycast`, and asserts the output contains: the phrase `modified version of Tinycast`, `Abue Ammar`, `AGPL-3.0-or-later`, a date in `YYYY-MM-DD` form, the upstream sha, a link to `https://github.com/amryadam/tinycast/tree/v0.12.11-fork.1`, a link to the licence, every `# Feature:` title found in `docs/fork/*.md`, the line `brew tap amryadam/fork https://github.com/amryadam/tinycast`, the line `brew install --cask amryadam/fork/tinycast-fork`, and the words `Privacy & Security`.
- [ ] **Step 2: Run it and see it fail.**
- [ ] **Step 3: Implement the script** with a here-document and a loop over `docs/fork/*.md` that prints the title of each feature.
- [ ] **Step 4: Run the test and `shellcheck`.** Expected: pass and no output.
- [ ] **Step 5: Commit.**

```shell
git add Scripts/fork-release-notes.sh Scripts/fork-test.sh
git commit -m "Generate release notes that carry the licence obligations"
```

## Task 5: Cask generator

**Files:**
- Create: `Scripts/fork-cask.sh`
- Modify: `Scripts/fork-test.sh`

**Interfaces:**
- Produces: `./Scripts/fork-cask.sh VERSION SHA256 [OUTPUT]`, which writes the cask from the spec (default `Casks/tinycast-fork.rb`).

- [ ] **Step 1: Write the failing tests.**
  - `test_cask_contents` asserts the output contains the version, the checksum, the URL with `#{version}`, `depends_on macos: ">= :tahoe"`, `app "Tinycast Fork.app"`, and a `zap` entry for `com.amryadam.tinycast`.
  - `test_cask_rejects` asserts a non-zero exit for a checksum that is not 64 hex digits and a version that does not match the version pattern.
  - `test_cask_audit` creates a throwaway local tap, writes the cask into it, and runs `brew style` and `brew audit --cask --strict` on it, asserting both exit 0. Skip with a message when `brew` is missing.
- [ ] **Step 2: Run them and see them fail.**
- [ ] **Step 3: Implement the script** with a here-document and the two input checks.
- [ ] **Step 4: Run the tests and `shellcheck`.** Expected: pass and no output. A failing audit is fixed in the template, not skipped.
- [ ] **Step 5: Commit.**

```shell
git add Scripts/fork-cask.sh Scripts/fork-test.sh
git commit -m "Add a generator for the fork's Homebrew cask"
```

## Task 6: Workflow

**Files:**
- Create: `.github/workflows/fork-release.yml`
- Create: `docs/fork/fork-release.md`
- Modify: `Scripts/fork-test.sh`

**Interfaces:**
- Consumes: every script above, and the secrets `SIGNING_P12_BASE64` and `SIGNING_P12_PASSWORD`.
- Produces: the workflow `Fork release` with inputs `version` and `publish`, as in the spec.

- [ ] **Step 1: Write the failing test** `test_workflow_static`. It parses the file with `python3 -c "import yaml"`, and asserts: the only trigger is `workflow_dispatch`; the job has `if: github.ref == 'refs/heads/dev'` and `runs-on: xcode-27`; `permissions` is exactly `contents: write`; no `run:` step contains `${{ inputs.` or `${{ secrets.`; every `uses:` has a full `@vN.N.N`-style pin; and the file contains the version regex and the words `if: always()` on the cleanup step.
- [ ] **Step 2: Run it and see it fail.**
- [ ] **Step 3: Write the workflow** with the steps from the spec, in this order: validate, checkout, select Xcode, gate, import identity, build, package, upload artifact, publish release, update cask, clean up.
  - Validation reads `VERSION` from `env:`, checks the regex, and runs `git ls-remote --tags origin "v$VERSION"`, failing when it finds one.
  - The release uses `gh release create "v$VERSION" --target "$GITHUB_SHA"`.
  - The cask step regenerates the file, commits as `github-actions[bot]`, and pushes with `git pull --rebase origin dev` and up to three retries, never forcing.
  - Cleanup runs with `if: always()` and deletes the keychain from the search list and the `.p12`.
- [ ] **Step 4: Write `docs/fork/fork-release.md`** with a `| File |` table that lists every file in the File Structure table above, a how-to section, and a Not done table.
- [ ] **Step 5: Run `test_workflow_static`, `shellcheck`, and `./Scripts/fork-check.sh`.** Expected: all pass.
- [ ] **Step 6: Commit** the workflow and the feature doc as two commits.

## Task 7: Review

**Files:**
- None changed.

- [ ] **Step 1: Run the whole `./Scripts/fork-test.sh`.** Expected: every test passes.
- [ ] **Step 2: Give a fresh Opus reviewer at high effort** the diff against `dev`, the spec and this plan, with write access removed.
- [ ] **Step 3: Triage every finding** as fixed, rejected with a reason, or recorded under Not done, then re-run Step 1.

## Task 8: Publish the branches

Outward and visible on the public fork. Each step waits for the user's explicit yes.

**Files:**
- None changed.

- [ ] **Step 1: Ask the user to approve** pushing `dev`, `feature/path-query`, `feature/fork-identity` and `feature/fork-release` to `origin`, with no push to `main`.
- [ ] **Step 2: Push.**

```shell
git push origin dev feature/path-query feature/fork-identity feature/fork-release
```

- [ ] **Step 3: Ask the user to approve** making `dev` the fork's default branch, then set it.

```shell
gh repo edit amryadam/tinycast --default-branch dev
```

- [ ] **Step 4: Ask the user to approve** disabling each of upstream's workflows on the fork, then disable them.

```shell
gh workflow list --repo amryadam/tinycast
gh workflow disable "<name>" --repo amryadam/tinycast
```

- [ ] **Step 5: Confirm** with `gh workflow list` that only `Fork release` is active.

## Task 9: Dry run

**Files:**
- None changed.

- [ ] **Step 1: Ask the user to approve uploading the signing identity** as repository secrets, then run `./Scripts/fork-signing-secret.sh --dry-run` first and show only its fingerprint.
- [ ] **Step 2: Run it for real.** Expected: two secrets listed by `gh secret list`, with values never displayed.
- [ ] **Step 3: Start the workflow with `publish` off.**

```shell
gh workflow run fork-release.yml --repo amryadam/tinycast --ref dev -f version=0.12.11-fork.1 -f publish=false
```

- [ ] **Step 4: Watch it to the end.** A job that never starts means the `xcode-27` label is unavailable, and the plan stops here for a decision.
- [ ] **Step 5: Download the artifact and verify it on this Mac:** the zip's checksum, `codesign --verify --deep --strict`, the signing authority, the bundle id, and the version.

## Task 10: First release

**Files:**
- None changed.

- [ ] **Step 1: Ask the user to approve** the first public release.
- [ ] **Step 2: Start the workflow with `publish` on.**

```shell
gh workflow run fork-release.yml --repo amryadam/tinycast --ref dev -f version=0.12.11-fork.1 -f publish=true
```

- [ ] **Step 3: Verify the release page** has the zip, the checksum, the notes and the tag.
- [ ] **Step 4: Verify the cask on `dev`** names that version and the same SHA-256 as the asset.
- [ ] **Step 5: Ask the user to approve installing it here,** then tap and install.

```shell
brew tap amryadam/fork https://github.com/amryadam/tinycast
brew install --cask amryadam/fork/tinycast-fork
```

- [ ] **Step 6: Record the result** in `docs/fork/fork-release.md` and in the sync log in `docs/fork/README.md`.

## Task 11: Final review

**Files:**
- None changed.

- [ ] **Step 1: Give a fresh Opus reviewer at high effort** the finished diff, the dry-run and release evidence, and the spec.
- [ ] **Step 2: Triage the findings** and re-run `./Scripts/fork-test.sh` and `./Scripts/fork-check.sh` after any fix.
- [ ] **Step 3: Merge `feature/fork-release` into `dev`** with `git merge --no-ff`, then push `dev`.
