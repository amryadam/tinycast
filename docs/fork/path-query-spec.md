# Path query: spec

Feature spec for the `path-query` feature of the [amryadam/tinycast](https://github.com/amryadam/tinycast) fork.
The implementation plan is [path-query-plan.md](path-query-plan.md).
The feature's change log is [path-query.md](path-query.md), and the fork's rules are in [README.md](README.md).
Revision 2: updated after an independent Opus review at high effort.

## Contents

- [Goal](#goal)
- [Non-goals](#non-goals)
- [Behaviour](#behaviour)
- [Accepted spellings](#accepted-spellings)
- [Design](#design)
- [Project registration](#project-registration)
- [Fork maintenance](#fork-maintenance)
- [Verified and unverified](#verified-and-unverified)
- [Risks](#risks)
- [Decisions](#decisions)
- [Acceptance criteria](#acceptance-criteria)

## Goal

Pasting the full path of a file into the launcher shows that file as a result, and pasting the path of a folder lets the user open the folder.

The user already has File Search enabled with **Show in launcher** on.
Today the launcher matches only file names, so a pasted path matches nothing.

## Non-goals

| Not in scope | Why |
|---|---|
| A new command, row type or ⌘K action | The existing Files row already opens, reveals, copies and shares. |
| Opening at `:line:col` | Tinycast has no editor setting. The parser returns the position so a later change can use it. |
| Open with… | File rows have no such action today. It would be a separate feature. |
| Relative paths and bare names | They are ambiguous without a working directory. |
| Upstreaming | The maintainer closed three similar requests ([#240](https://github.com/abue-ammar/tinycast/issues/240), [#1856](https://github.com/abue-ammar/tinycast/issues/1856), [#1858](https://github.com/abue-ammar/tinycast/issues/1858)). |

## Behaviour

| Condition | Result |
|---|---|
| File Search off, or **Show in launcher** off | Nothing changes. |
| Full Disk Access not granted to the app | Nothing changes. File Search itself indexes nothing without it. |
| The query spells an existing file | One row, shown first in the Files section. ↵ opens it in its default app. |
| The query spells an existing folder | One row, shown first in the Files section. ↵ opens it in Finder. |
| The query spells the root folder or the home folder | Nothing is added, however it is spelled (`/`, `/..`, `~`, `~/`, `~/.`). |
| The query spells a path that does not exist | Nothing is added and no error is shown. |
| The query is not shaped like a path | Nothing changes, and no filesystem call is made. |
| The same path is also a favorite or an indexed hit | It appears once, as the pasted-path row. |
| More than five rows result | The list is cut to `FileSearchQuery.launcherLimit`, keeping the pasted-path row. |

The row is an ordinary `FileSearchResult`, so ⌘↵ reveals it, ⌃⌘C copies its path, and share, copy and favorite work unchanged.
The row appears even when the path is in an ignored folder or outside the configured scopes, because an exact path states the intent.
A multi-line paste is joined with spaces by the palette, so it never names a path.
An app bundle such as `Safari.app` is a folder row that launches the app, as indexed rows already do.
↵ opens the pasted row when it is the selected one, and the Files section sits below app hits and the calculator or colour cards.

## Accepted spellings

| Input | Reads as |
|---|---|
| `/Users/me/a.txt` | An absolute path |
| `~/a.txt` | Under the home folder |
| `file:///Users/me/My%20Folder`, `FILE:///…`, `file:/Users/me/a` | A decoded file URL, with any case of the scheme |
| `file://localhost/Users/me/a` | The same as `file:///Users/me/a` |
| `file://otherhost/Users/me/a` | Not a path, because its host is not this machine |
| `"/Users/me/a.txt"`, `'…'`, `“…”` | The same path without one pair of surrounding quotes |
| `" /Users/me/a.txt "` | The same path, because whitespace is trimmed again inside the quotes |
| `/Users/me/My\ Folder` | A backslash-escaped space, where any escaped character stands for itself |
| `/Users/me//a/../b.txt` | Doubled slashes, `.` and `..` resolved by name, never through a symlink |
| `/Users/me/a.swift:42`, `:42:7`, and `:42:7:` | The file, plus a line and column that are parsed but unused, with one optional trailing colon as compilers print it |
| A leading byte order mark | Ignored |

The whole spelling is probed first, so a real file named `a:1` is never misread as line 1 of `a`.
Of two candidate suffixes, the longer is tried first, so `a:12:3` is line 12, column 3 of `a` before it is line 3 of `a:12`.

## Design

### Layers

The design follows the layering in the project's `docs/architecture.md`.
All fork code is in new files, and one upstream line changes.

| Layer | File | Responsibility |
|---|---|---|
| Model, pure | `Tinycast/Features/FileSearch/Model/FileSearchPathQuery.swift` | Spelling, quotes, escapes, `~`, `file://`, positions, the root and home rule, and the merge that puts the pasted row first. Existence is asked of an injected probe. |
| Service, effect | `Tinycast/Features/FileSearch/Service/FileSearchPathLookup.swift` | Asks `FileManager`, wraps the answer as a `FileSearchResult`. |
| UI, fork-owned | `Tinycast/Features/FileSearch/UI/FileSearchCoordinator+PastedPath.swift` | A coordinator extension that memoises the lookup per query and second, re-checks a cached row, and hands the Full Disk Access gate to the lookup. |
| Call site | `Tinycast/Features/Launcher/UI/LauncherScreen.swift:77` | One line calls the extension instead of `launcherFiles(for:)`. |

`launcherFiles(for:)` itself is not edited, because upstream changed that function on 2026-10-16 and 2026-10-27.

### Interfaces

```swift
enum FileSearchPathQuery {
    enum Kind: Equatable, Sendable { case file, directory }

    struct Location: Equatable, Sendable {
        let path: String   // absolute, normalised, no trailing slash
        let kind: Kind
        let line: Int?     // from a trailing :line or :line:col
        let column: Int?
    }

    typealias Probe = (String) -> Kind?   // nil when nothing exists at the path

    static func resolve(_ query: String, homeDirectory: String, probe: Probe) -> Location?

    static func leading(_ pasted: FileSearchResult?, before found: [FileSearchResult], limit: Int) -> [FileSearchResult]
}

enum FileSearchPathLookup {
    // isAllowed is asked once, just before the first stat, and never for text that is no path
    static func result(
        for query: String, fileManager: FileManager = .default, isAllowed: () -> Bool = { true }
    ) -> FileSearchResult?
}

extension FileSearchCoordinator {
    /// `launcherFiles(for:)` with the pasted-path row first, memoised per query.
    func launcherFilesLeadingWithPastedPath(for query: String) -> [FileSearchResult]
}
```

### The call site

```swift
// FORK(path-query): lead with a pasted path.
let files = pinned == nil ? core.fileSearchCoordinator.launcherFilesLeadingWithPastedPath(for: vm.query) : []
```

### Data flow

1. `RootPaletteView.screen` is a computed property, so one render builds `LauncherScreen` about 14 times, and each calls the Files lookup at the call site above.
2. `launcherFilesLeadingWithPastedPath` calls the unchanged `launcherFiles(for:)` for the usual favorites and indexed hits.
3. When `showsFilesInLauncher` holds, a one-slot `Memo`, keyed by the query and the current second, answers repeat calls without touching the disk.
4. On a miss it calls `FileSearchPathLookup.result` with `isAllowed: Permissions.hasFullDiskAccess`.
5. The lookup returns early without any filesystem call unless the text spells an absolute path.
6. For a path it asks `isAllowed` once, and only if that holds does it probe with `FileManager.fileExists(atPath:isDirectory:)`.
7. A cached row is checked with one `fileExists` on every call, so the row of a trashed file disappears at once.
8. `FileSearchPathQuery.leading` puts the pasted row first, removes a repeated `id`, and cuts the list to five.
9. ↵ calls the existing `FileSearchCoordinator.open`, which uses `NSWorkspace.open`.

The memo has two accepted limits.
A file created after the last lookup is seen within a second of the next render, and the palette renders only on an event, so an untouched screen can show the old state until the next keystroke or reopen.
Full Disk Access granted mid-session takes effect the same way.

## Project registration

The Xcode project is generated from `project.yml` by XcodeGen, and the generated `Tinycast.xcodeproj/project.pbxproj` is committed and lists every source file explicitly.
A new source file is not compiled until the project is regenerated, which the first Xcode build confirmed.

Decision: regenerate with XcodeGen 2.46.0, installed with Homebrew.
Regenerating a clean checkout of upstream `main` at `58168bf7` leaves the committed project unchanged, so this version matches upstream's.
Each new source adds four lines to the project file: two in hash-sorted sections, one in its group and one in the build list.
A conflict in that file is resolved by taking upstream's file and regenerating, never by merging by hand.
The helper target `FileIndexHelper` lists its files one by one in `project.yml`, so the new Model file does not reach it.

## Fork maintenance

| Rule | Detail |
|---|---|
| Branches | `main` mirrors `upstream/main`. `dev` is `main` plus the fork tooling plus finished features. Feature branches start from `dev`. |
| Tooling lives on `dev` | `docs/fork/README.md` and `Scripts/fork-check.sh` are merged into `dev` once, so every later feature has them. |
| One doc per feature | Each feature adds `docs/fork/<feature>.md`, so features never edit the same file. |
| Markers | Every hunk that edits an upstream file contains a `FORK(<feature>)` marker, in a `//` or `#` comment. |
| The check | `Scripts/fork-check.sh` reads every `docs/fork/*.md` and fails on an unlisted file, a stale entry, or a hunk without a marker. |
| Merging | Features merge into `dev` with `git merge --no-ff`. `rerere` is on. |
| Pushing | Only to `origin`. `remote.pushDefault` is `origin`. Nothing is pushed until the user approves. |
| Running the app | Run the Debug build `Tinycast Dev.app`, bundle id `com.tinycast.app.dev`, which never updates. A Release build of the fork would replace itself with upstream's release at quit. |
| GitHub Actions on the fork | Upstream's `gitlab-mirror.yml` and `website.yml` run on pushes to `main`. Disable Actions on `origin` before pushing. |

## Verified and unverified

| Claim | State |
|---|---|
| The harness of 67 assertions passes, and 12 deliberately broken copies of the parser are each caught. The existing file-search harness still passes with the new file in its glob. | Verified |
| The Xcode build fails without registering the new Service file in the project. | Verified |
| `URL` does not collapse a doubled slash, so the parser normalises by hand. | Verified |
| Builds here need `CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY=-`, because the `Tinycast Self-Signed` identity is absent. | Verified |
| XcodeGen 2.46.0 regenerates upstream `main` at `58168bf7` with an empty diff. | Verified |
| `RootPaletteView.screen` rebuilds `LauncherScreen` about 14 times per render. | Reviewer read, to confirm by a counter |
| Without Full Disk Access, probing a protected folder can show a macOS prompt. | Unverified, because it needs the GUI |
| `swiftlint` is not installed, so `Scripts/lint.sh` cannot run here. | Verified |

## Risks

| Risk | Mitigation |
|---|---|
| A protected-folder probe shows an access prompt on a keystroke. | The row is gated on `Permissions.hasFullDiskAccess()`, which never prompts. |
| A network volume stalls the main thread during the probe. | The memo limits it to one lookup per query per second, and every render re-checks a found row. Accepted beyond that. |
| Full Disk Access is not remembered across rebuilds of an unsigned build, so the row can vanish after a rebuild. | Build with the fork's own signing identity, described in [fork-identity.md](fork-identity.md). |
| A clean merge that no longer compiles. | The sync script runs the tests and the build after every merge. |
| A typed path in the wrong case, such as `/users/…`, gives a different favorite key. | Accepted, and minor. |
| A typed path and an indexed path differ by symlink, such as `/tmp` and `/private/tmp`, giving two rows. | Accepted. Paths are never resolved through symlinks. |

## Decisions

| Id | Decision | Source |
|---|---|---|
| D1 | Register the new sources by regenerating the project with XcodeGen. | Approved by the user, and recommended by the review |
| D2 | No row for the root folder or the home folder, in any spelling. | Recommended by the review, open to veto |
| D3 | Gate the row on Full Disk Access instead of probing protected folders. | Recommended by the review, open to veto |
| D4 | Fork docs live in `docs/fork/`, one file per feature. | Recommended by the review, open to veto |

## Acceptance criteria

| Check | Pass condition |
|---|---|
| `Scripts/run-tests.sh` | All harnesses pass, including `file-search-path-test`. |
| Xcode Debug and Release builds | Both succeed with `CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY=-`. |
| Format check on the fork's Swift files | `swift-format` reports no difference. |
| `Scripts/fork-check.sh` | Exits 0. |
| Probe count | Not measured, because it needs the GUI. The memo bounds it to one lookup per query per second. |
| Manual: paste the path of an existing file | One row appears first, and ↵ opens the file. |
| Manual: paste the path of an existing folder | One row appears first, and ↵ opens the folder in Finder. |
| Manual: paste a path that does not exist | No row appears and the normal results are unchanged. |
| Manual: ordinary typing, such as `safari` | Results are unchanged, and no extra row appears. |
| Manual: File Search off, or **Show in launcher** off | No pasted-path row appears. |
