# Feature: fork-sync

Merges upstream into `dev` on a schedule, lets Claude resolve conflicts in an isolated job, verifies the result, and publishes a new release that the app offers in its update pill.
The plan is [fork-update-sync-plan.md](fork-update-sync-plan.md), and the in-app channel is [fork-update.md](fork-update.md).

## Contents

- [Scripts](#scripts)
- [Files](#files)

## Scripts

| Script | Job |
|---|---|
| `Scripts/fork-next-version.sh` | Chooses the next `MAJOR.MINOR.PATCH-fork.N`, always above every existing fork tag. |
| `Scripts/fork-sync-merge.sh` | Merges upstream into `dev`, keeps `.github/` exactly as `dev` has it, and saves a conflicted merge for resolution. |
| `Scripts/fork-sync-verify-tree.sh` | Refuses any candidate merge that is not exactly what git computes, apart from the conflicted files. |
| `Scripts/fork-sync-decide.sh` | Says `skip`, `hold` or `release` for the changes since the last fork tag. |

## Files

| File | Change | Purpose | Conflict risk |
|---|---|---|---|
| `docs/fork/fork-sync.md` | New | This file. | None |
| `Scripts/fork-next-version.sh` | New | See the table above. | None |
| `Scripts/fork-sync-merge.sh` | New | See the table above. | None |
| `Scripts/fork-sync-verify-tree.sh` | New | See the table above. | None |
| `Scripts/fork-sync-decide.sh` | New | See the table above. | None |
