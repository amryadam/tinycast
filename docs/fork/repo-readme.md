# Feature: repo-readme

Points the repository README at the fork instead of upstream, so a reader of the fork's page installs the fork and reports problems to the fork.
The fork's rules are in [README.md](README.md).

## Contents

- [What changes](#what-changes)
- [Files](#files)

## What changes

| Part of the README | Change |
|---|---|
| Release, downloads and build badges | Read the fork's repository and its `fork-release.yml` workflow. |
| Contact line | Links to the fork's issues instead of the maintainer's email. |
| Install | The fork's tap commands, a zip download, and the one-time Open Anyway step. |

Nothing is added that labels the project, and the Support section and Discord badge are left as upstream has them.
Every changed hunk carries a `FORK(repo-readme)` marker in an HTML comment.
When upstream changes its README, keep upstream's text and re-apply these hunks.

## Files

| File | Change | Purpose | Conflict risk |
|---|---|---|---|
| `docs/fork/repo-readme.md` | New | This file. | None |
| `README.md` | Edit | The badges, contact line, install section and the table of the fork's features above. | Medium: upstream edits its README |
