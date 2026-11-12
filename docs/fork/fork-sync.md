# Feature: fork-sync

Merges each new upstream release into `dev`, lets Claude resolve conflicts in an isolated job, verifies the result, and publishes a new release that the app offers in its update pill.
The plan is [fork-update-sync-plan.md](fork-update-sync-plan.md), and the in-app channel is [fork-update.md](fork-update.md).

## Contents

- [How a sync runs](#how-a-sync-runs)
- [Scripts](#scripts)
- [One-time setup](#one-time-setup)
- [Limits](#limits)
- [Files](#files)

## How a sync runs

The workflow `Upstream sync` runs from `dev`, daily once switched on and on demand.
It merges upstream's latest published release, never the commits upstream makes between releases.
On most days the check finds nothing new and stops in a few seconds.
A prerelease or beta tag is ignored, because only upstream's latest stable release counts.

| Job | Holds | Does |
|---|---|---|
| `detect` | nothing | Looks up upstream's latest published release and the commit it points at, and checks whether `dev` already contains that commit. |
| `merge` | nothing | Merges upstream into `dev` with `fork-sync-merge.sh`. `.github/` is kept exactly as `dev` has it. |
| `resolve` | the Claude token only | Only after a conflict. Upstream's own tool configuration (`.mcp.json`, `.claude/`, `CLAUDE.md`, git hooks) is moved out of the tree first. Claude edits files with `--permission-mode acceptEdits` and file tools only. A workflow step, not the model, stages only the paths git reported as conflicted and writes the merge commit with the trailer `Resolved-by: claude`. |
| `verify` | nothing | Re-checks that the candidate is a faithful merge, then runs the gate, the tests and an unsigned build on the merged code. |
| `push` | the GitHub token only | Runs no merged code. It re-checks the candidate and fast-forwards `dev`. The fork's `main` is not touched. |
| `release` | the workflow token | Starts `Fork release` for the verified commit and waits for it, or says why not. |
| `notify` | the workflow token | Opens one issue when any job failed. |

A release starts automatically after a clean merge.
After a merge Claude resolved, the merge still lands, but the release waits and one issue says so, because a model-written resolution would otherwise be installed by the in-app updater on a Mac where the app holds Accessibility and Full Disk Access.
Start `Fork release` by hand after reading the merge.

Why the jobs are split:

- Merged code is third-party code, so the job that runs it holds no secret.
- The Claude job reads untrusted upstream text, so it can write nothing to the repository and holds no GitHub token.
- The job that holds the GitHub token runs only trusted scripts, and re-checks the candidate itself.
- Any workflow file on `dev` could name the signing environment and read the key, so upstream's `.github/` never lands.
- The fork's `main` is not mirrored from upstream, because that would copy upstream's workflow files onto a branch where they are active. Upstream is fetched directly where it is needed.
- `Fork release` runs the checks and Swift tests in a `gate` job with no secret. The job that holds the signing key first refuses a project with a script build phase, a package reference, a scheme action or a case-colliding path (`fork-check-build-inputs.sh`).

## Scripts

| Script | Job |
|---|---|
| `Scripts/fork-next-version.sh` | Chooses the next `MAJOR.MINOR.PATCH-fork.N`, always above every existing fork tag. |
| `Scripts/fork-sync-merge.sh` | Merges upstream into `dev`, keeps `.github/` exactly as `dev` has it, and saves a conflicted merge for resolution. |
| `Scripts/fork-sync-verify-tree.sh` | Refuses any candidate merge that is not exactly what git computes, apart from the conflicted files. |
| `Scripts/fork-sync-decide.sh` | Says `skip`, `hold` or `release` for the changes since the last fork tag. |
| `Scripts/fork-check-build-inputs.sh` | Refuses a tree that could run code of its own during a build, or holds paths that differ only by case. |

## One-time setup

Only you can create the two tokens.
Run these in your own terminal; each prompts for the value, which never goes into a file.

```shell
# The Claude token: run this once, and copy the token it prints.
claude setup-token
gh secret set CLAUDE_CODE_OAUTH_TOKEN --env fork-sync-claude --repo amryadam/tinycast

# The GitHub token: a fine-grained personal access token for amryadam/tinycast only,
# with Contents: Read and write and Workflows: Read and write, and nothing else. Workflows is
# needed because a merge that carries upstream's changes to its own workflow files is refused
# by GitHub without it. Those files are inert here, because `.github/` stays as `dev` has it,
# and the rulesets below keep a bad push from deleting or rewriting `dev`.
gh secret set SYNC_TOKEN --env fork-sync --repo amryadam/tinycast

# Switch the daily schedule on, after the first manual run and a look at the update pill.
gh variable set FORK_SYNC_SCHEDULE --body on --repo amryadam/tinycast
```

The environments come from `./Scripts/fork-bootstrap.sh environments`, and each is limited to the branch `dev`.
`./Scripts/fork-bootstrap.sh rulesets` protects `dev` from deletion and force pushes, and the tags `v*-fork.*` from being moved or deleted.
It demands no pull request, because the sync pushes to `dev` directly.

## Limits

- Claude runs on a GitHub-hosted runner and calls Anthropic's API with your subscription token, so runs count against your usage limits. The token is tied to your account.
- `anthropics/claude-code-action` is pinned by commit. A reported authentication problem exists for v1 with OAuth tokens, so the first real conflict may need an adjustment.
- GitHub pauses scheduled workflows after 60 days with no repository activity. Merges count as activity.
- A conflict in `project.pbxproj` is regenerated with `xcodegen` when `project.yml` is not itself in conflict. Otherwise it goes to Claude, who is told not to edit it, and the run fails into an issue.
- Upstream's own workflow changes are never taken. If upstream's release process changes, `Fork release` is not updated by the sync.
- The merge itself still carries upstream's workflow files in its history, so the first run after upstream changes one shows whether GitHub accepts the push with the token as it is.

## Files

| File | Change | Purpose | Conflict risk |
|---|---|---|---|
| `docs/fork/fork-sync.md` | New | This file. | None |
| `Scripts/fork-next-version.sh` | New | See the table above. | None |
| `Scripts/fork-sync-merge.sh` | New | See the table above. | None |
| `Scripts/fork-sync-verify-tree.sh` | New | See the table above. | None |
| `Scripts/fork-sync-decide.sh` | New | See the table above. | None |
| `Scripts/fork-check-build-inputs.sh` | New | See the table above. | None |
| `.github/workflows/fork-sync.yml` | New | The `Upstream sync` workflow described above. | None |
