# Fork release implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A commit on `dev` is built and signed on GitHub, published as a release, and installable with Homebrew.

**Architecture:** Small shell scripts do each job and are tested locally, and one new workflow file strings them together in two jobs on the `xcode-27` runner.
The signing identity and a tap deploy key live in environment secrets that only `dev` can use.
The cask lives in a separate tap repository, `amryadam/homebrew-fork`.

**Tech Stack:** Bash, GitHub Actions, `gh`, `xcodebuild`, `codesign`, `actionlint`, Homebrew casks.

**Spec:** [fork-release-spec.md](fork-release-spec.md)

Revision 2: updated after an independent Opus review at high effort.

## Contents

- [Global constraints](#global-constraints)
- [Review focus](#review-focus)
- [File structure](#file-structure)
- [Task 1: Build script and validation](#task-1-build-script-and-validation)
- [Task 2: Identity import and packaging](#task-2-identity-import-and-packaging)
- [Task 3: Release notes](#task-3-release-notes)
- [Task 4: Cask generator](#task-4-cask-generator)
- [Task 5: Bootstrap script](#task-5-bootstrap-script)
- [Task 6: Workflow](#task-6-workflow)
- [Task 7: Review and merge](#task-7-review-and-merge)
- [Task 8: Publish the branches](#task-8-publish-the-branches)
- [Task 9: Bootstrap on GitHub](#task-9-bootstrap-on-github)
- [Task 10: Dry run](#task-10-dry-run)
- [Task 11: First release](#task-11-first-release)
- [Task 12: Final review](#task-12-final-review)

## Global constraints

- Work in `/Users/amryadam/Github/tinycast-worktrees/fork-release` on branch `feature/fork-release`.
- Never read, print, log or commit key material, passwords or tokens.
- Every script starts with `set -euo pipefail`, passes `shellcheck`, and takes input only from arguments and environment variables.
- A workflow `run:` step reads inputs and secrets from `env:`, never from an inline `${{ }}` expression.
- Each `uses:` in the workflow is a full commit SHA, resolved read-only with `gh api` when the workflow is written.
- Push only to `origin`, and only after the user's explicit yes in Tasks 8 to 11.
- Commit subjects are short, imperative and capitalised, with no period and no attribution lines.
- Every commit passes `./Scripts/fork-check.sh`, so a new file is listed in `docs/fork/fork-release.md` in the commit that adds it.
- This feature edits no upstream file, so it needs no `FORK(` marker.
- Use `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` for local `xcodebuild` and `xcrun`.

## Review focus

| Input or condition | Expected behaviour | Pinned in |
|---|---|---|
| A version such as `1.0.0-fork.1; rm -rf ~`, or one with a newline or a leading space | Rejected by the validation script. | Task 1 |
| A package signed by someone else, or unsigned | `fork-package.sh --require-authority` refuses it. | Task 2 |
| The notes missing a licence item | A test fails. | Task 3 |
| A checksum or version that is malformed | The cask generator refuses it. | Task 4 |
| The cask is generated for a release whose tap push failed | `--from-release` regenerates it. | Task 4 |
| Bootstrap run twice | The second run refuses to replace the identity without `--force`. | Task 5 |
| A secret, key or password in output | The bootstrap and import tests grep their own output for key markers. | Tasks 2 and 5 |
| The workflow reads an input or secret inline, uses an unpinned action, gives the build job write access, or lacks cleanup | `actionlint` and structural checks fail. | Task 6 |
| A tag that already exists, or `dev` moving during the run | The tag check fails the run, and the release uses `--target "$GITHUB_SHA"`. | Task 6 and Task 10 |

## File structure

| Planned file | Change | Task |
|---|---|---|
| `Scripts/fork-build.sh` | Edited, the fork's own file | 1 |
| `Scripts/fork-release-validate.sh` | New | 1 |
| `Scripts/fork-import-identity.sh` | New | 2 |
| `Scripts/fork-package.sh` | New | 2 |
| `Scripts/fork-release-notes.sh` | New | 3 |
| `Scripts/fork-cask.sh` | New | 4 |
| `Scripts/fork-bootstrap.sh` | New | 5 |
| `Scripts/fork-test.sh` | New, runs every test below | 1 to 6 |
| `.github/workflows/fork-release.yml` | New | 6 |
| `docs/fork/fork-release.md` and the spec and plan | New | 6 |

## Task 1: Build script and validation

**Files:**
- Modify: `Scripts/fork-build.sh`
- Create: `Scripts/fork-release-validate.sh`
- Create: `Scripts/fork-test.sh`
- Create: `docs/fork/fork-release.md`

**Interfaces:**
- Produces: `./Scripts/fork-release-validate.sh VERSION`, exit 0 and print the base version (the part before `-fork`) for an exact match of `^[0-9]+\.[0-9]+\.[0-9]+-fork\.[0-9]+$`, and exit 1 otherwise.
- Produces: in `fork-build.sh`, two optional variables `FORK_VERSION` (passed as `MARKETING_VERSION`) and `FORK_BUILD_NUMBER` (passed as `CURRENT_PROJECT_VERSION`), and a `--print-settings` flag that prints the settings it would pass and exits before the identity check.
- Produces: `./Scripts/fork-test.sh [name]`, which runs the named test or all, and exits non-zero on a failure.

- [ ] **Step 1: Write the failing tests** in `Scripts/fork-test.sh`.
  - `test_validate_accepts` asserts `0.12.11-fork.1` prints `0.12.11`.
  - `test_validate_rejects` asserts exit 1 for each of these: `1.0.0`, `1.0.0-fork`, `1.0.0-fork.x`, `1.0.0-fork.1; rm -rf ~`, `1.0.0-fork.1\n`, ` 1.0.0-fork.1`, an empty string, and `v1.0.0-fork.1`.
  - `test_build_print_settings` asserts `MARKETING_VERSION=1.2.3` appears when `FORK_VERSION=1.2.3` is set and is absent when unset, and that the command succeeds on a machine without the identity.
- [ ] **Step 2: Run them and see them fail.** Expected: the validation script is missing, and the flag is unknown.
- [ ] **Step 3: Implement `fork-release-validate.sh`** with one anchored `[[ =~ ]]` match, taking the value from `$1` only.
- [ ] **Step 4: Add the variables and `--print-settings` to `fork-build.sh`**, placing the flag's exit before the identity check.
- [ ] **Step 5: Create `docs/fork/fork-release.md`** with a Status section and a `| File |` table that lists the files this commit adds.
- [ ] **Step 6: Run the tests, `shellcheck`, and `./Scripts/fork-check.sh`.** Expected: pass, no output, exit 0.
- [ ] **Step 7: Commit.**

```shell
git add Scripts docs/fork/fork-release.md
git commit -m "Validate release versions and let the build take a version"
```

## Task 2: Identity import and packaging

**Files:**
- Create: `Scripts/fork-import-identity.sh`
- Create: `Scripts/fork-package.sh`
- Modify: `Scripts/fork-test.sh`, `docs/fork/fork-release.md`

**Interfaces:**
- Produces: `./Scripts/fork-import-identity.sh`, which reads `P12_BASE64`, `P12_PASSWORD` and `RUNNER_TEMP`, imports the identity into a new keychain under `RUNNER_TEMP`, unlocks it, sets its timeout, opens the key to `codesign` through a partition list, puts it on the user search list, and prints nothing secret. `--cleanup` removes that keychain from the list and from disk.
- Produces: `./Scripts/fork-package.sh APP_PATH VERSION OUT_DIR [--require-authority NAME]`. It verifies the bundle, builds a staging folder with the app, `LICENSE` and `NOTICE.md` at its root, writes `OUT_DIR/Tinycast-Fork-VERSION.zip` and `.zip.sha256`, and prints the SHA-256.

- [ ] **Step 1: Write the failing tests.**
  - `test_import_requires_env` asserts a non-zero exit and a message naming the missing variable, and that the output contains none of `BEGIN`, `PRIVATE` or the password.
  - `test_import_cleanup_is_safe` asserts `--cleanup` succeeds when nothing was imported.
  - `test_package_ok` builds a minimal fake `Tinycast Fork.app` with a valid `Info.plist` (bundle id `com.amryadam.tinycast`, version 1.2.3), signs it ad-hoc, runs the script, and asserts the zip and checksum exist, the checksum matches `shasum -a 256`, and the zip root holds the app, `LICENSE` and `NOTICE.md` and no parent folder.
  - `test_package_rejects` asserts a non-zero exit for a wrong bundle id, a wrong version, an unsigned app, and a missing app.
  - `test_package_authority` signs the fake app ad-hoc and asserts `--require-authority "Tinycast Self-Signed"` refuses it.
- [ ] **Step 2: Run them and see them fail.**
- [ ] **Step 3: Implement the import script** from the recipe in the spec, without downloading any certificate.
- [ ] **Step 4: Implement the packaging script.** It checks the app name, the bundle id from `Info.plist`, `CFBundleShortVersionString` equal to the base version, and `codesign --verify --deep --strict`, and with `--require-authority` also checks the first `Authority=` line. It zips the staging folder with `ditto -c -k --sequesterRsrc`.
- [ ] **Step 5: Run the tests, `shellcheck`, and `./Scripts/fork-check.sh`.** Expected: pass, no output, exit 0.
- [ ] **Step 6: Commit.**

```shell
git add Scripts docs/fork/fork-release.md
git commit -m "Add scripts to import the signing identity and package the app"
```

## Task 3: Release notes

**Files:**
- Create: `Scripts/fork-release-notes.sh`
- Modify: `Scripts/fork-test.sh`, `docs/fork/fork-release.md`

**Interfaces:**
- Produces: `./Scripts/fork-release-notes.sh VERSION UPSTREAM_SHA REPO`, which prints Markdown notes to standard output.

- [ ] **Step 1: Write the failing test** `test_notes_licence_items`. It runs the script for `0.12.11-fork.1`, a sample sha and `amryadam/tinycast`, and asserts the output contains: `unofficial`, `not affiliated`, `modified version of Tinycast`, `Abue Ammar`, `AGPL-3.0-or-later`, a date in `YYYY-MM-DD` form, the sha, `https://github.com/amryadam/tinycast/tree/v0.12.11-fork.1`, a link to the licence, every `# Feature:` title found in `docs/fork/*.md`, `brew tap amryadam/fork`, `brew trust --cask amryadam/fork/tinycast-fork`, `brew install --cask amryadam/fork/tinycast-fork`, and `Privacy & Security`.
- [ ] **Step 2: Run it and see it fail.**
- [ ] **Step 3: Implement the script** with a here-document and a loop over `docs/fork/*.md`.
- [ ] **Step 4: Run the test, `shellcheck`, and `./Scripts/fork-check.sh`.** Expected: pass, no output, exit 0.
- [ ] **Step 5: Commit.**

```shell
git add Scripts docs/fork/fork-release.md
git commit -m "Generate release notes that carry the licence obligations"
```

## Task 4: Cask generator

**Files:**
- Create: `Scripts/fork-cask.sh`
- Modify: `Scripts/fork-test.sh`, `docs/fork/fork-release.md`

**Interfaces:**
- Produces: `./Scripts/fork-cask.sh VERSION SHA256 [OUTPUT]`, which writes the cask from the spec (default `Casks/tinycast-fork.rb`).
- Produces: `./Scripts/fork-cask.sh --from-release VERSION [OUTPUT]`, which reads the SHA-256 from the release's `.zip.sha256` asset with `gh release download`.

- [ ] **Step 1: Write the failing tests.**
  - `test_cask_contents` asserts the output contains the version, the checksum, `desc "Unofficial fork`, a `livecheck` block with the `-fork` regex, `depends_on macos: :tahoe`, `depends_on arch: :arm64`, `uninstall quit: "com.amryadam.tinycast"`, `app "Tinycast Fork.app"`, and a `zap` entry for `com.amryadam.tinycast.dictation`, and does not contain `ClipboardTextHelper`.
  - `test_cask_rejects` asserts a non-zero exit for a checksum that is not 64 hex digits and for a version that fails `fork-release-validate.sh`.
  - `test_cask_style` runs `brew style` on a generated file and asserts exit 0, skipping with a message when `brew` is missing.
- [ ] **Step 2: Run them and see them fail.**
- [ ] **Step 3: Implement the script**, calling the validation script for the version and checking the checksum with a 64-hex-digit match.
- [ ] **Step 4: Run the tests, `shellcheck`, and `./Scripts/fork-check.sh`.** Expected: pass, no output, exit 0. A style failure is fixed in the template.
- [ ] **Step 5: Commit.**

```shell
git add Scripts docs/fork/fork-release.md
git commit -m "Add a generator for the fork's Homebrew cask"
```

## Task 5: Bootstrap script

**Files:**
- Create: `Scripts/fork-bootstrap.sh`
- Modify: `Scripts/fork-test.sh`, `docs/fork/fork-release.md`

**Interfaces:**
- Produces: `./Scripts/fork-bootstrap.sh SUBCOMMAND [--dry-run] [--force] [--repo OWNER/NAME] [--tap OWNER/NAME]` with subcommands `environments`, `tap` and `identity`.
  - `environments` creates `fork-build` and `fork-publish`, each limited to the branch `dev`.
  - `tap` creates the public tap repository with a README and generates an ed25519 deploy key, adds its public half with write access, and stores the private half as `TAP_DEPLOY_KEY` in `fork-publish`.
  - `identity` generates the key and certificate in a private temporary folder, checks the `.p12` opens, and stores `SIGNING_P12_BASE64` and `SIGNING_P12_PASSWORD` in `fork-build`.
  - Each subcommand refuses to replace anything that exists unless `--force` is given, and each prints what it did without printing any secret.

- [ ] **Step 1: Write the failing tests** with a stub `gh` placed first on `PATH` that records its calls to a file and never touches GitHub.
  - `test_bootstrap_dry_run` asserts `--dry-run` makes no stub call that creates or sets anything, prints `dry run`, and prints no key marker.
  - `test_bootstrap_identity_calls` asserts the stub saw a secret set for each of the two names with `--env fork-build`, with the value passed on standard input and never in the arguments.
  - `test_bootstrap_refuses_overwrite` makes the stub report existing secrets and asserts a non-zero exit, and that `--force` lets it proceed.
  - `test_bootstrap_no_leftovers` asserts no `.p12`, `.pem` or key file remains in the temporary area afterwards.
- [ ] **Step 2: Run them and see them fail.**
- [ ] **Step 3: Implement the script** with a `mktemp -d` folder of mode 700, a `trap` that removes it, `/usr/bin/openssl` for the identity, `ssh-keygen -t ed25519 -N ""` for the deploy key, and `gh api` or `gh secret set` for every GitHub call.
- [ ] **Step 4: Run the tests, `shellcheck`, and `./Scripts/fork-check.sh`.** Expected: pass, no output, exit 0.
- [ ] **Step 5: Commit.**

```shell
git add Scripts docs/fork/fork-release.md
git commit -m "Add a bootstrap script for the release environments and secrets"
```

## Task 6: Workflow

**Files:**
- Create: `.github/workflows/fork-release.yml`
- Modify: `Scripts/fork-test.sh`, `docs/fork/fork-release.md`, `docs/fork/README.md`

**Interfaces:**
- Consumes: every script above, the environments `fork-build` and `fork-publish`, and their secrets.
- Produces: the workflow `Fork release` with inputs `version` and `publish`, and the jobs `build` and `publish` from the spec.

- [ ] **Step 1: Write the failing test** `test_workflow_static`.
  - Run `actionlint` on the file and assert exit 0.
  - Assert with `grep` that the only trigger is `workflow_dispatch`, that `permissions: {}` is set at the top, that `build` has `contents: read` and `runs-on: xcode-27` and `environment: fork-build`, that `publish` has `contents: write` and `environment: fork-publish`, that the string `SIGNING_P12` appears only in the build job and `TAP_DEPLOY_KEY` only in the publish job, that no line contains `${{ inputs.` or `${{ secrets.` outside an `env:` block, that every `uses:` ends in a 40-hex-digit SHA, that `persist-credentials: false` appears on each checkout, that `retention-days: 1` is set, that `--latest` and `--target "$GITHUB_SHA"` appear, and that each cleanup step has `if: always()`.
- [ ] **Step 2: Run it and see it fail.**
- [ ] **Step 3: Resolve the action SHAs** for `actions/checkout`, `actions/upload-artifact` and `actions/download-artifact` with read-only `gh api repos/OWNER/REPO/git/ref/tags/TAG` calls, and record each tag beside its SHA in a comment.
- [ ] **Step 4: Write the workflow** following the spec's two jobs.
  - The build job validates the version, checks out, checks the tag with `gh api`, selects Xcode, runs the gate with `FORK_BASE=origin/main`, imports the identity, builds, packages with `--require-authority`, lints a generated cask with `brew style` and `brew audit --cask --strict`, uploads the artifact, and cleans up.
  - The publish job downloads the artifact, verifies the checksum, creates the release from generated notes, clones the tap with the deploy key, writes the cask, pushes with up to three rebase retries and never forces, and cleans up.
- [ ] **Step 6: Add a rule to `docs/fork/README.md`** that `gh repo sync` must always use `-b main`, and that `gh workflow list --all` is re-checked after every upstream sync.
- [ ] **Step 7: Run `test_workflow_static`, `shellcheck`, the whole `./Scripts/fork-test.sh`, and `./Scripts/fork-check.sh`.** Expected: all pass.
- [ ] **Step 8: Commit** the workflow and the docs as two commits.

## Task 7: Review and merge

**Files:**
- None changed.

- [ ] **Step 1: Give a fresh Opus reviewer at high effort** the diff against `dev`, the spec and this plan, with write access removed.
- [ ] **Step 2: Triage every finding** as fixed, rejected with a reason, or recorded under Not done, then re-run `./Scripts/fork-test.sh`.
- [ ] **Step 3: Merge `feature/fork-release` into `dev`** with `git merge --no-ff`, so the workflow file is on `dev` before anything is pushed.

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

- [ ] **Step 4: Ask the user to approve** disabling upstream's workflows on the fork, then disable each one except `Fork release`.

```shell
gh workflow list --all --repo amryadam/tinycast
gh workflow disable "<name>" --repo amryadam/tinycast
```

- [ ] **Step 5: Confirm** with `gh workflow list` that only `Fork release` is active.

## Task 9: Bootstrap on GitHub

Outward. Each step waits for the user's explicit yes.

**Files:**
- None changed.

- [ ] **Step 1: Ask the user to approve** creating the two environments, then run `./Scripts/fork-bootstrap.sh environments`, first with `--dry-run`.
- [ ] **Step 2: Ask the user to approve** creating the public repository `amryadam/homebrew-fork` and its deploy key, then run `./Scripts/fork-bootstrap.sh tap`, first with `--dry-run`.
- [ ] **Step 3: Ask the user to approve** uploading the signing identity, then run `./Scripts/fork-bootstrap.sh identity`, first with `--dry-run`.
- [ ] **Step 4: Confirm** with `gh secret list --env fork-build` and `--env fork-publish` that the three secrets exist, with their values never shown.

## Task 10: Dry run

**Files:**
- None changed.

- [ ] **Step 1: Start the workflow with `publish` off.**

```shell
gh workflow run fork-release.yml --repo amryadam/tinycast --ref dev -f version=0.12.11-fork.1 -f publish=false
```

- [ ] **Step 2: Watch it to the end.** A build job that never starts means the `xcode-27` label is unavailable to the fork, and the plan stops for a decision.
- [ ] **Step 3: Download the artifact and verify it on this Mac:** the checksum, `codesign --verify --deep --strict`, the signing authority, the bundle id, the version, and the licence files in the zip.
- [ ] **Step 4: Record the result** in `docs/fork/fork-release.md`, including any runner or signing surprise.

## Task 11: First release

**Files:**
- None changed.

- [ ] **Step 1: Ask the user to approve** the first public release, after the About-screen notice (decision D7) is done or deliberately deferred.
- [ ] **Step 2: Start the workflow with `publish` on.**

```shell
gh workflow run fork-release.yml --repo amryadam/tinycast --ref dev -f version=0.12.11-fork.1 -f publish=true
```

- [ ] **Step 3: Verify the release page** has the zip, the checksum, the notes and the tag, and is marked latest.
- [ ] **Step 4: Download the released zip, not the dry-run artifact,** and repeat the checks from Task 10 Step 3 on it.
- [ ] **Step 5: Verify the tap's cask** names that version and the same SHA-256 as the asset.
- [ ] **Step 6: Ask the user to approve installing it here,** which includes trusting that one cask in Homebrew, then tap, trust and install.

```shell
brew tap amryadam/fork
brew trust --cask amryadam/fork/tinycast-fork
brew install --cask amryadam/fork/tinycast-fork
```

- [ ] **Step 7: Record the result** in `docs/fork/fork-release.md` and in the sync log in `docs/fork/README.md`.

## Task 12: Final review

**Files:**
- None changed.

- [ ] **Step 1: Give a fresh Opus reviewer at high effort** the finished diff, the dry-run and release evidence, and the spec.
- [ ] **Step 2: Triage the findings** and re-run `./Scripts/fork-test.sh` and `./Scripts/fork-check.sh` after any fix.
- [ ] **Step 3: Push `dev`** with the final state, after the user approves.
