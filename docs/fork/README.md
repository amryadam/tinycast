# Fork changes

This directory tracks everything [amryadam/tinycast](https://github.com/amryadam/tinycast) changes relative to [abue-ammar/tinycast](https://github.com/abue-ammar/tinycast).
Each feature has its own file here, so two features never edit the same document.
`Scripts/fork-check.sh` fails when these files and the real diff against upstream disagree.

## Contents

- [Rules](#rules)
- [Branches and remotes](#branches-and-remotes)
- [Adding a feature](#adding-a-feature)
- [Fork infrastructure](#fork-infrastructure)
- [Upstream sync log](#upstream-sync-log)

## Rules

1. Prefer a new file over an edit to an upstream file, so a merge has nothing to conflict on.
2. Every hunk that edits an upstream file contains a `FORK(<feature>)` marker, in a `//` or `#` comment.
3. Every file the fork adds or edits is listed in a table headed `| File |`, as a backticked path at the start of a row.
4. Run `./Scripts/fork-check.sh` before committing.
5. One feature per branch, merged into `dev` with `git merge --no-ff`.
6. A conflict in the generated `Tinycast.xcodeproj/project.pbxproj` is resolved by taking upstream's file and running `xcodegen generate`, never by merging by hand.

The generated project file cannot carry a marker, so the check does not ask for one there.
Find every hook in upstream code with:

```shell
grep -rn 'FORK(' Tinycast Tests Scripts
```

## Branches and remotes

| Name | Meaning |
|---|---|
| `upstream` | The maintainer's repository, read-only for us. |
| `origin` | This fork. `remote.pushDefault` is set to it, so a plain push never reaches upstream. |
| `main` | A mirror of `upstream/main`. It only fast-forwards and carries no fork commits. |
| `dev` | `main` plus this tooling plus every finished feature. The app is built from it. |
| `feature/<name>` | One feature, branched from `dev`. |
| `fork/tooling` | The tooling in this directory, merged into `dev` once. |

## Adding a feature

1. Create a worktree on `feature/<name>` from `dev`.
2. Write the code, preferring new files.
3. Add `docs/fork/<name>.md` with a `| File |` table that lists every file the feature adds or edits.
4. Run `./Scripts/fork-check.sh`.
5. Merge into `dev` with `git merge --no-ff`.

## Fork infrastructure

| File | Change | Purpose | Conflict risk |
|---|---|---|---|
| `docs/fork/README.md` | New | This file. | None |
| `Scripts/fork-check.sh` | New | Compares `docs/fork/*.md` with the real diff against `upstream/main`. | None |

## Upstream sync log

| Date | Upstream commit | Result |
|---|---|---|
| 2026-11-11 | `58168bf7` | Fork created from this commit. No conflicts. |
