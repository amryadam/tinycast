# Fork update channel, upstream sync and automatic release: plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The fork is its own update channel in the app, and a scheduled job merges upstream into `dev`, resolves conflicts with Claude, and publishes a new release that the app offers in its update pill.

**Architecture:** The app's existing updater gets a `fork` channel that reads the fork's releases, so no new updater is written.
A scheduled workflow detects new upstream commits, merges them, lets Claude resolve conflicts in an isolated job, verifies the result, pushes `dev`, and dispatches the existing `Fork release` workflow.
Each stage is a small shell script with tests, and the workflows only call them.

**Tech Stack:** Swift 6 (the updater), Bash, GitHub Actions, `gh`, `anthropics/claude-code-action`.

Revision 3, written without a separate spec at the user's request. Revision 2 followed an independent Opus review at high effort, and revision 3 followed a second one of the implementation (decisions 10, 13 and 14, the leading-zero and modify/delete fixes, slower release polling and issue titles matched only when the workflow's own bot opened them).

## Contents

- [Decisions](#decisions)
- [Global constraints](#global-constraints)
- [Review focus](#review-focus)
- [File structure](#file-structure)
- [Part A: the fork update channel](#part-a-the-fork-update-channel)
- [Part B: sync and automatic release](#part-b-sync-and-automatic-release)
- [Part C: run it](#part-c-run-it)

## Decisions

| # | Decision | Reason |
|---|---|---|
| 1 | The app's version string is the full `0.12.11-fork.2`. | The running app must know its fork number to compare with a newer release. |
| 2 | A new build is trusted through the running copy's own designated requirement. No release key. | Every release is signed by the same GitHub-held identity, and upstream's updater already accepts that path. |
| 3 | The cask declares `auto_updates true`. | Otherwise `brew upgrade` fights the in-app update. |
| 4 | Merges reach `dev` automatically after the checks pass. A conflict is resolved by Claude in a job with no write access. | The user chose automatic merging. |
| 5 | The release version is the higher of upstream's latest release and the fork's highest base, plus `-fork.N`. | The version must always exceed every existing fork tag. |
| 6 | A release is automatic after a clean merge. After a Claude-resolved merge the merge still lands, but the release waits for the user. | A model-written resolution would otherwise be installed by the in-app updater on a Mac where the app holds Accessibility and Full Disk Access. |
| 7 | Any failure opens one issue (or comments on the open one). `dev` never holds a half-merge. | The user finds out, once. |
| 8 | Secrets are split by job: `fork-sync-claude` holds only the Claude token, and `fork-sync` holds the GitHub token. The job that runs merged code holds no secret, and the job that holds the token runs no repository code. | Merged code is third-party code, and the Claude job reads untrusted text. |
| 9 | `.github/` is pinned to the `dev` version on every merge. Upstream workflows never land. | Any workflow file on `dev` could name the `fork-build` environment and read the signing key. |
| 10 | The fork's `main` is not updated by the sync at all. Upstream is fetched directly as `upstream/main` wherever the gate, the notes or the notice need it. `SYNC_TOKEN` has Contents and Workflows write, and rulesets protect `dev` and the `v*-fork.*` tags. | Mirroring `main` would copy upstream's workflow files onto a branch where they are active, and a new upstream workflow could then push to `dev` and start a release with the signing key. |
| 13 | `Fork release` runs the checks and Swift tests in a `gate` job with no secret. The signing job first runs `fork-check-build-inputs.sh`, which refuses a script build phase, a package reference, a scheme action and a case-colliding path. | The signing job otherwise compiled and ran upstream code beside the key, and a path such as `scripts/fork-build.sh` replaced a fork script on a case-insensitive disk. |
| 14 | The Claude job runs with `--permission-mode acceptEdits` and `--strict-mcp-config`, with upstream's tool configuration moved out of the tree. A workflow step stages only the paths git reported as conflicted, with hooks and fsmonitor off and `.git/config` restored, and writes the `Resolved-by: claude` trailer. | An edit tool listed as allowed is still denied in agent mode, so no conflict could be resolved. The model must not be able to load upstream's configuration, run a git hook, or drop the trailer that holds back the release. |
| 11 | A new release must satisfy the previous release's designated requirement before it is published. | A regenerated signing identity would otherwise lock every installed copy out of updates. |
| 15 | Only an upstream release is merged: the commit of upstream's latest published release, found with the releases API. The commits between releases are ignored. | The user wants to follow releases, not every commit. A release is also the commit upstream's own checks and tests covered. |
| 16 | Every merge candidate, clean or resolved, is read by a read-only Claude review. Anything but a clear `ok` adds the trailer `Review-concerns: claude` in the push job, which holds the release exactly as `Resolved-by: claude` does. | A merge git calls clean can still break the fork: an API a fork hook calls was renamed, or upstream changed the updater, signing or build. The review's own failure must not let a release through. |
| 12 | The daily schedule starts only when the repository variable `FORK_SYNC_SCHEDULE` is `on`. | It is switched on after the first manual run and the user's check of the pill. |

## Global constraints

- Work in a worktree on its own branch: `feature/fork-update` for Part A and `feature/fork-sync` for Part B, merged into `dev` with `git merge --no-ff`.
- Never read, print, log or commit a token, key or password. The user creates the two tokens and sets them with `gh secret set`.
- Edits to upstream files are small hunks that carry a `FORK(<feature>)` marker, and every file is listed in a `docs/fork/*.md` table.
- Every script starts with `set -euo pipefail`, passes `shellcheck`, and is covered by `./Scripts/fork-test.sh`.
- Workflow `run:` steps read inputs and secrets from `env:` only, and every `uses:` is a full commit SHA.
- Every commit passes `./Scripts/fork-check.sh`, and the Swift tests pass with `./Scripts/run-tests.sh updates-test`, `update-check-test` and `fork-update-test`.
- Commit subjects are short, imperative and capitalised, with no period and no attribution lines.
- Use `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` for local Swift builds.

## Review focus

| Input or condition | Expected behaviour | Pinned in |
|---|---|---|
| A fork tag such as `v0.12.11-fork.10` against `-fork.9` | `.10` is newer. | Task 1 |
| A plain upstream tag `v0.12.12`, or a beta, in the fork's feed | Never offered to the fork channel. | Task 1 |
| A release that is a draft, a prerelease, or has no zip | Not offered. | Task 1 |
| The official app (`com.tinycast.app`) and beta | Behave exactly as before. | Task 1 |
| Upstream publishes `0.12.12` while the fork is on `0.12.11-fork.4` | Next version is `0.12.12-fork.1`. | Task 4 |
| Two syncs overlap, or `dev` moves during a sync | The push is refused, and the result becomes an issue. | Task 5 |
| The upstream diff touches only `website/` and `docs/` | Merged, but no release. | Task 4 |
| Upstream adds a new workflow | It is disabled right after the merge. | Task 4 |
| Claude's output is wrong or hostile | The tree is recomputed and compared, then the gate and an unsigned build run in a job with no secrets, before the push job sees it. | Task 5 |
| A locally built copy with a different key | Refuses a GitHub update and says so, because the signature differs. | Task 1 |
| The app's release URL | Is the fork's repository for the fork channel and upstream's for the others. | Task 1 |
| `0.12.11` against `0.12.11-fork.1`, and the cache round trip | The fork version is newer, and survives `update-check.json`. | Task 1 |
| A new release signed by a different identity than the last | `Fork release` refuses to publish it. | Task 2 |
| The fork's base is higher than upstream's latest release | The next version still exceeds every fork tag. | Task 4 |
| Upstream edits or adds a workflow | The merge keeps `dev`'s `.github/`, so nothing lands. | Task 4 |
| Claude's resolution changes a file that did not conflict, edits `.github/`, or leaves markers | The tree check refuses it. | Task 4 |
| A merge Claude resolved | Lands on `dev` but is not released automatically. | Task 4 |
| A failed release | The next scheduled run notices that `dev` is ahead of the last release and tries again. | Task 4 |

## File structure

| Planned file | Change | Task |
|---|---|---|
| `Tinycast/Features/Updates/Model/AppVersion.swift` | Edit (marked) | 1 |
| `Tinycast/Features/Updates/Model/ReleaseChannel.swift` | Edit (marked) | 1 |
| `Tinycast/Features/Updates/Model/ReleaseFeed.swift` | Edit (marked) | 1 |
| `Tinycast/Features/Updates/Service/UpdateCheckStore.swift` | Edit (marked) | 1 |
| `Tests/fork-update-test.swift` | New | 1 |
| `Scripts/run-tests.sh` | Edit (marked) | 1 |
| `Scripts/fork-build.sh`, `Scripts/fork-package.sh`, `Scripts/fork-cask.sh`, `.github/workflows/fork-release.yml` | Edit | 2 |
| `Scripts/fork-next-version.sh`, `Scripts/fork-sync-decide.sh`, `Scripts/fork-disable-upstream-workflows.sh` | New | 4 |
| `.github/workflows/fork-sync.yml` | New | 5 |
| `Scripts/fork-bootstrap.sh` | Edit | 6 |
| `docs/fork/fork-update.md`, `docs/fork/fork-sync.md`, this plan | New | 3, 5 |

## Part A: the fork update channel

### Task 1: The channel and the version

**Files:**
- Modify: `Tinycast/Features/Updates/Model/AppVersion.swift`, `ReleaseChannel.swift`, `ReleaseFeed.swift`, `Tinycast/Features/Updates/Service/UpdateCheckStore.swift`, `Scripts/run-tests.sh`
- Create: `Tests/fork-update-test.swift`

**Interfaces:**
- Produces: `AppVersion.fork: Int?`, parsed from `MAJOR.MINOR.PATCH-fork.N`, never a prerelease, ordered by the triple and then by `fork`.
- Produces: `ReleaseChannel.fork`, chosen for the bundle id `com.amryadam.tinycast`, with `updatesItself == true` and `repository: String` (`abue-ammar/tinycast` for stable and beta, `amryadam/tinycast` for fork).
- Produces: `ReleaseFeed` accepts, for the fork channel, only versions whose `fork` is non-nil, and every other channel only versions whose `fork` is nil.

```swift
struct AppVersion { let fork: Int?  /* nil unless the text ends -fork.N */ }
extension ReleaseChannel { var repository: String { get } }
extension ReleaseFeed { static func releasesURL(for channel: ReleaseChannel) -> URL }
```

`UpdateCheckStore` builds its request from `ReleaseFeed.releasesURL(for:)` instead of a static URL.

- [ ] **Step 1: Write the failing tests** in `Tests/fork-update-test.swift`, with a `run fork-update-test` line in `Scripts/run-tests.sh` marked `# FORK(fork-update)`.
  - Versions: `0.12.11-fork.2` parses and prints back unchanged, `0.12.11-fork.10` is greater than `-fork.9`, `0.12.12-fork.1` is greater than `0.12.11-fork.9`, and the fork version is not a prerelease.
  - Rejections: `0.12.11-fork`, `-fork.x`, `-fork.-1`, `-fork.1.2`, `-beta.1-fork.1`.
  - Channels: `com.amryadam.tinycast` is `.fork`; `com.tinycast.app` and `com.tinycast.app.beta` are unchanged; any other id is still `.development`.
  - Feed: a feed with `v0.12.11-fork.1`, `v0.12.11-fork.2`, a draft `-fork.3`, a plain `v0.12.12`, and a `-beta.1` returns `-fork.2` for the fork channel and, for stable, returns only `v0.12.12`.
  - Feed: a release with no zip is skipped, and `offer` returns nil when the running version is equal or newer.
  - Feed: the real shape of `https://api.github.com/repos/amryadam/tinycast/releases`, saved as a fixture string in the test.
  - URL: `releasesURL(for: .fork)` names `amryadam/tinycast`, and stable and beta name `abue-ammar/tinycast`.
  - Order: `0.12.11` is older than `0.12.11-fork.1`, and `-fork.N` combined with `-beta.N` is rejected.
  - Cache: an `AvailableRelease` with a fork version encodes and decodes to an equal value.
- [ ] **Step 2: Run them and see them fail.** Expected: a compile error for `fork`.
- [ ] **Step 3: Implement** the four edits, each hunk carrying a `FORK(fork-update)` comment, and the existing updater tests unchanged.
- [ ] **Step 4: Run** `./Scripts/run-tests.sh fork-update-test`, `updates-test` and `update-check-test`. Expected: all pass.
- [ ] **Step 5: Build** with `xcodebuild -project Tinycast.xcodeproj -scheme Tinycast -configuration Debug CODE_SIGNING_ALLOWED=NO build`. Expected: BUILD SUCCEEDED.
- [ ] **Step 6: Commit** `Add the fork as an update channel`.

### Task 2: Pipeline changes for the new version string

**Files:**
- Modify: `Scripts/fork-build.sh`, `Scripts/fork-package.sh`, `Scripts/fork-cask.sh`, `.github/workflows/fork-release.yml`, `Scripts/fork-test.sh`
- Create: `Scripts/fork-check-update-path.sh`

**Interfaces:**
- Consumes: `fork-release-validate.sh VERSION` (unchanged).
- Produces: the built app has `CFBundleShortVersionString == VERSION`, the full fork version, and the cask carries `auto_updates true`.
- Produces: `./Scripts/fork-check-update-path.sh NEW_APP PREVIOUS_ZIP`, which reads the previous app's designated requirement with `codesign -d -r-` and fails unless `codesign --verify --strict --deep -R` accepts the new app against it.
- Produces: the `Fork release` workflow takes an optional input `expected_sha`, and the build job fails when `GITHUB_SHA` differs from it.

- [ ] **Step 1: Update the tests first.** `test_update_path` uses a stub `codesign` (as `test_package_authority` does) to cover the plumbing: a requirement that the new app satisfies passes, one it does not satisfy fails, and a missing previous zip is a clear error. `test_workflow_static` also checks that the build job runs the update-path check when a previous release exists, and that `expected_sha` is compared with `GITHUB_SHA`. `test_package_ok` and `test_package_rejects` build the fake app with the full version, and a fake app with only the base version is rejected. `test_cask_contents` asserts `auto_updates true`. A new `test_workflow_static` assertion checks that the build step passes the full `$VERSION` as `FORK_VERSION`.
- [ ] **Step 2: Run and see them fail.**
- [ ] **Step 3: Implement.** The workflow's Build step sets `FORK_VERSION="$VERSION"`, and `fork-package.sh` compares against the full version. The build job downloads the previous release's zip with `gh release download` (skipped when there is no previous release) and runs the path check on the new app before it uploads anything.
- [ ] **Step 4: Run** `./Scripts/fork-test.sh`, `shellcheck`, and `actionlint`. Expected: pass.
- [ ] **Step 5: Commit** `Version the app with its full fork version`.

### Task 3: Docs and merge of Part A

**Files:**
- Create: `docs/fork/fork-update.md`
- Modify: `docs/fork/README.md` (a pointer to the update channel)

- [ ] **Step 1: Write `docs/fork/fork-update.md`** with a `# Feature: fork-update` title, a `| File |` table of every file Tasks 1 and 2 touch, and the known limits (a locally built copy refuses a GitHub update; the in-app pill shows on opening the palette).
- [ ] **Step 2: Run** `./Scripts/fork-check.sh` and the whole `./Scripts/fork-test.sh`. Expected: pass.
- [ ] **Step 3: Commit,** then merge `feature/fork-update` into `dev` with `git merge --no-ff` once Part C's review has passed.

## Part B: sync and automatic release

### Task 4: The scripts

**Files:**
- Create: `Scripts/fork-next-version.sh`, `Scripts/fork-sync-merge.sh`, `Scripts/fork-sync-verify-tree.sh`, `Scripts/fork-sync-decide.sh`
- Modify: `Scripts/fork-test.sh`

**Interfaces:**
- Produces: `./Scripts/fork-next-version.sh UPSTREAM_LATEST_BASE TAG...`, printing the next `MAJOR.MINOR.PATCH-fork.N`. The base is the higher of the upstream base and the highest base among the `v<base>-fork.N` tags, and N is one more than the highest N for that base, or 1.
- Produces: `./Scripts/fork-sync-merge.sh DEV_REF UPSTREAM_REF`, run in a repository on `DEV_REF`. It merges `UPSTREAM_REF` with `--no-ff` and pins `.github/` to `DEV_REF`'s version, taking ours in any `.github/` conflict and deleting any `.github/` file `DEV_REF` lacks. It exits 0 with a merge commit when clean, and exits 10 with the conflicted tree committed on a temporary ref `refs/fork-sync/conflicted` when not. A conflict in `Tinycast.xcodeproj/project.pbxproj` is resolved by taking upstream's file and running `xcodegen generate` when `xcodegen` is on `PATH`.
- Produces: `./Scripts/fork-sync-verify-tree.sh DEV UPSTREAM CANDIDATE`, which exits non-zero unless `CANDIDATE` has exactly the parents `DEV` and `UPSTREAM`; its tree equals `git merge-tree --write-tree` for a clean merge (after pinning `.github/`), or, for a conflicted merge, differs from the conflicted baseline only in the conflicted paths; nothing under `.github/` differs from `DEV`; no `Scripts/fork-*.sh` differs from `DEV` unless upstream changed it; and no file contains a conflict marker line.
- Produces: `./Scripts/fork-sync-decide.sh LAST_FORK_TAG DEV_REF`, printing `release` when `DEV_REF` differs from the tag outside `website/` and `docs/` and no commit since the tag carries the trailer `Resolved-by: claude`, `hold` when such a commit exists, and `skip` otherwise.

```shell
./Scripts/fork-next-version.sh 0.12.12 v0.12.11-fork.4 v0.12.11-fork.5   # 0.12.12-fork.1
./Scripts/fork-next-version.sh 0.12.11 v0.12.12-fork.1                    # 0.12.12-fork.2
```

- [ ] **Step 1: Write the failing tests,** with real throwaway git repositories under a temporary folder.
  - Next version: a new base starts at 1; `.10` beats `.9`; a higher fork base wins over a lower upstream base; other bases are ignored; a malformed base, tag or no argument is rejected.
  - Merge: a clean merge makes a merge commit with the two parents; a conflict exits 10 and leaves `dev` untouched; an upstream edit to an existing workflow, an added workflow, and an edit to `.github/` that conflicts all leave `.github/` identical to `dev`; the merge is otherwise complete.
  - Verify tree: accepts the genuine clean merge and a resolution that changes only conflicted files; rejects a candidate with a third parent, a changed unconflicted file, a changed `.github/` file, an edited `Scripts/fork-*.sh`, a leftover conflict marker, and a candidate whose parents are swapped for other commits.
  - Decide: `docs/`-only or `website/`-only changes give `skip`; a change in `Tinycast/` gives `release`; a `Resolved-by: claude` commit gives `hold`; `docs-evil/x` and `website2/x` count as code; no new commits give `skip`.
- [ ] **Step 2: Run them and see them fail.**
- [ ] **Step 3: Implement the four scripts** with anchored regexes and `git` plumbing (`merge-tree`, `commit-tree`, `rev-parse`), never `eval`.
- [ ] **Step 4: Run** the tests, `shellcheck`, `./Scripts/fork-check.sh`, and mutation checks on each script's key conditions. Expected: pass, and each mutant fails a test.
- [ ] **Step 5: Commit** `Add the scripts that merge upstream and choose the next version`.

### Task 5: The sync workflow

**Files:**
- Create: `.github/workflows/fork-sync.yml`, `docs/fork/fork-sync.md`
- Modify: `Scripts/fork-test.sh`

**Interfaces:**
- Consumes: Tasks 1 to 4, the existing `Fork release` workflow (with `expected_sha`), and the secrets `SYNC_TOKEN` (environment `fork-sync`) and `CLAUDE_CODE_OAUTH_TOKEN` (environment `fork-sync-claude`).
- Produces: the workflow `Upstream sync`, triggered by `workflow_dispatch` and a daily `schedule` that runs only when `vars.FORK_SYNC_SCHEDULE == 'on'`, always run from `dev`.

| Job | Runs on | Secrets | Purpose |
|---|---|---|---|
| `detect` | ubuntu | none | Fetch upstream. Output whether `dev..upstream/main` has commits, and the result of `fork-sync-decide.sh` against the last fork tag. |
| `merge` | macOS | none | Install `xcodegen`, run `fork-sync-merge.sh`, and upload a git bundle of the merge commit, or of the conflicted ref. |
| `resolve` | ubuntu | Claude token only, `contents: read` | Only after exit 10. Check out the conflicted ref and let Claude edit the files, with file tools only. A workflow step then builds the merge commit with `git commit-tree -p dev -p upstream`, adds the trailer `Resolved-by: claude`, and uploads it as a bundle. |
| `verify` | macOS `xcode-27` | none, `permissions: {}`, `persist-credentials: false` | Run `fork-sync-verify-tree.sh`, then `fork-check` (with `FORK_BASE` set to the upstream commit), `fork-test`, the fork's Swift tests and an unsigned build. Output the candidate commit id. |
| `push` | ubuntu | `SYNC_TOKEN` only here | Run no repository code beyond trusted scripts from the checkout of `dev` at the workflow's commit. Re-fetch upstream's exact commit, re-run `fork-sync-verify-tree.sh`, then `git push` the candidate to `dev` as a fast-forward. `main` is left alone. |
| `release` | ubuntu | `github.token` with `actions: write` | When the decision is `release`, compute the version, dispatch `Fork release` with `publish=true` and `expected_sha`, find the run by its head commit, and `gh run watch --exit-status` it. When the decision is `hold`, open or update one issue that says why. |
| `notify` | ubuntu | `github.token` with `issues: write` | On any failure, open one issue that links the run, or comment on the open one. |

- [ ] **Step 1: Extend `test_workflow_static`** to cover this file: only `schedule` and `workflow_dispatch` triggers, and the schedule job condition names `FORK_SYNC_SCHEDULE`; `permissions: {}` at the top; `resolve` has `contents: read` and no `SYNC_TOKEN`; `SYNC_TOKEN` appears only in `push`; the Claude token only in `resolve`; `verify` has no `secrets.` at all and sets `persist-credentials: false`; inputs and secrets only inside `env:`; every action pinned to a commit; a concurrency group; `if: failure()` on `notify`; the Claude step passes `github_token`, `--model`, `--effort`, `--max-turns`, `--tools Read,Edit,Write,Glob,Grep` and `--setting-sources user` (so a repository `.claude/settings.json` from upstream is never loaded); and the push job runs `fork-sync-verify-tree.sh` before `git push`.
- [ ] **Step 2: Run and see it fail.** Expected: the workflow is missing.
- [ ] **Step 3: Resolve the action SHAs** read-only with `gh api`, and write the workflow.
- [ ] **Step 4: Run** `actionlint`, `shellcheck` and the whole `./Scripts/fork-test.sh`. Expected: pass, and mutation checks fail the static test.
- [ ] **Step 5: Write `docs/fork/fork-sync.md`** with a `# Feature: fork-sync` title, a `| File |` table, the secret setup commands, and the limits.
- [ ] **Step 6: Commit** `Add the upstream sync workflow`.

### Task 6: Environments

**Files:**
- Modify: `Scripts/fork-bootstrap.sh`, `Scripts/fork-test.sh`

- [ ] **Step 1: Extend `test_bootstrap_environments_calls`** to expect `fork-sync` and `fork-sync-claude` too, each limited to `dev`.
- [ ] **Step 2: Run and see it fail, implement, run again.**
- [ ] **Step 3: Commit** `Create the sync environments in the bootstrap script`.

## Part C: run it

### Task 7: Review, merge, publish

- [ ] **Step 1: Implement Parts A and B** task by task as above.
- [ ] **Step 2: Review the implementation** with a fresh Opus reviewer at high effort, and fix what it finds.
- [ ] **Step 3: Merge both branches** into `dev` with `git merge --no-ff`, and push `dev`.
- [ ] **Step 4: Create the sync environments** with `./Scripts/fork-bootstrap.sh environments`.
- [ ] **Step 5: Release `0.12.11-fork.2`** with `Fork release` (`publish=true`), so it is the first build with the fork channel. Its update-path check runs against `fork.1`.
- [ ] **Step 6: Verify the feed headlessly** with a script that uses the real `ReleaseFeed` and `releasesURL` against the live API response for `amryadam/tinycast`, downloads the zip it picks, expands it with `ditto -x -k`, and checks the bundle id, the version against the tag, and `codesign -R` against an installed copy. Check that the cask has `auto_updates true`.
- [ ] **Step 7: Release a deliberate `0.12.11-fork.3`** so a copy of `fork.2` has something to be offered, and ask the user to confirm the pill, the install at relaunch, and the "Updated to" message.
- [ ] **Step 8: Verify the sync.** Dispatch `Upstream sync` once the user has set the two secrets. Until then `detect` and `merge` can be exercised, and the rest is verified by its scripts' tests and the static test. The schedule stays off until the user confirms Step 7 and the variable `FORK_SYNC_SCHEDULE` is set to `on`.

## Known gaps

- The pill, the installer and the swap at quit cannot be exercised without a GUI session, and computer use is not available here, so the user confirms them. macOS App Management may also refuse a swap into `/Applications` for a bundle with no Team ID, and only the user's Mac can show that.
- The Claude resolution job cannot be exercised until the user creates the Claude token, and a deliberate conflict is then needed to test it.
- `claude-code-action` is pinned by commit, and the first real run may need adjustment (a reported authentication issue exists for v1 with OAuth tokens).
