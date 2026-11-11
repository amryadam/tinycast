# Path query implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A pasted absolute path that exists appears as the first row of the launcher's Files section.

**Architecture:** A pure parser in `FileSearch/Model`, a thin filesystem lookup in `FileSearch/Service`, and a fork-owned coordinator extension that adds, memoises and gates the row.
One upstream line changes, at the Files call site in `LauncherScreen.swift`.
The row is an ordinary `FileSearchResult`, so the existing Files row actions apply unchanged.

**Tech Stack:** Swift 6, SwiftUI and AppKit, Xcode 27.2, XcodeGen 2.46.0, shell test harnesses under `Tests/`.

**Spec:** [path-query-spec.md](path-query-spec.md)

Revision 2: updated after an independent Opus review at high effort.

## Contents

- [Global constraints](#global-constraints)
- [Review focus](#review-focus)
- [File structure](#file-structure)
- [Task 1: Fork tooling on dev](#task-1-fork-tooling-on-dev)
- [Task 2: Parser, lookup and project registration](#task-2-parser-lookup-and-project-registration)
- [Task 3: The row](#task-3-the-row)
- [Task 4: Feature doc](#task-4-feature-doc)
- [Task 5: Verification](#task-5-verification)
- [Task 6: Final review](#task-6-final-review)
- [Task 7: Land on dev](#task-7-land-on-dev)
- [Task 8: Sync script](#task-8-sync-script)

## Global constraints

- Work only in worktrees under `/Users/amryadam/Github/tinycast-worktrees/`, each on its own branch.
- Push only to `origin`, never to `upstream`, and push nothing until the user approves.
- Set `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` for every `xcodebuild`, `swiftc` and `xcrun`.
- Build with `CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY=-`, and never create the `Tinycast Self-Signed` identity.
- A file under `Model/` imports Foundation only, and takes every environment fact as a parameter.
- Comments in new Swift files are one line of at most 100 characters, and lines are at most 110 characters.
- Every hunk that edits an upstream file carries a `FORK(path-query)` marker in a comment.
- Commit subjects are short, imperative and capitalised, with no period, with no attribution lines.
- Every commit builds. Register a source in the project in the commit that adds it.
- Run `swift-format` only on the fork's own files, never `./Scripts/format.sh` without `--check`.

## Review focus

| Input or condition | Expected behaviour | Pinned in |
|---|---|---|
| Two pasted paths joined by a space, `/a /b` | No row, no crash. | Task 2 |
| A bare `/`, `~`, `~/`, `/..` or `~/.` | No row. | Task 2 |
| `file://otherhost/…` | No row. | Task 2 |
| A file path with a trailing slash | Reads as the file. | Task 2 |
| A path under a protected folder without Full Disk Access | No probe, so no macOS prompt. | Task 3 |
| Typing a 40-character path | At most one lookup per query per second. Not measured. | Task 5 |

## File structure

| File | Change | Task |
|---|---|---|
| `docs/fork/README.md` | New | 1 |
| `Scripts/fork-check.sh` | New | 1 |
| `Tinycast/Features/FileSearch/Model/FileSearchPathQuery.swift` | New | 2 |
| `Tinycast/Features/FileSearch/Service/FileSearchPathLookup.swift` | New | 2 |
| `Tests/file-search-path-test.swift` | New | 2 |
| `Scripts/run-tests.sh` | Edited, one marked line | 2 |
| `Tinycast.xcodeproj/project.pbxproj` | Regenerated | 2 |
| `Tinycast/Features/FileSearch/UI/FileSearchCoordinator+PastedPath.swift` | New | 3 |
| `Tinycast/Features/Launcher/UI/LauncherScreen.swift` | Edited, one marked line | 3 |
| `docs/fork/path-query.md` | New | 4 |
| `docs/fork/path-query-spec.md` | New | 4 |
| `docs/fork/path-query-plan.md` | New | 4 |

## Task 1: Fork tooling on dev

**Files:**
- Create: `docs/fork/README.md`
- Create: `Scripts/fork-check.sh`

**Interfaces:**
- Produces: `./Scripts/fork-check.sh`, which reads every `docs/fork/*.md`, takes the rows of tables headed `| File |` as the listed files, and compares them with `git diff --name-only $(git merge-base upstream/main HEAD)` plus untracked files.
- It prints `UNLISTED`, `STALE` or `UNMARKED` lines and exits 1, or exits 0 when everything matches. `UNMARKED` means a hunk of an upstream file has no added line containing `FORK(`.

- [x] **Step 1: Draft the script and the doc** as `CHANGES.md` and `fork-check.sh`. The script passes on the current tree and catches an unlisted file and an unmarked edit.
- [x] **Step 2: Rework the script** to read `docs/fork/*.md`, to check each `git diff -U0` hunk for a marker in any file type, and to skip files the fork deleted.
- [x] **Step 3: Split the doc.** `docs/fork/README.md` keeps the rules, branches, tooling table and sync log. The feature part moves to Task 4.
- [x] **Step 4: Run three negative cases.** An unlisted file, an unmarked second hunk in an already-marked file, and a deleted upstream file. Expected: `UNLISTED`, `UNMARKED`, and no error for the deletion.
- [x] **Step 5: Commit on a new branch `fork/tooling` cut from `main`.**

```shell
git switch -c fork/tooling main
git add docs/fork/README.md Scripts/fork-check.sh
git commit -m "Add fork change tracking and its check script"
```

- [x] **Step 6: Create `dev` in its own worktree and merge the tooling.**

```shell
git worktree add -b dev /Users/amryadam/Github/tinycast-worktrees/dev main
git -C /Users/amryadam/Github/tinycast-worktrees/dev merge --no-ff fork/tooling
```

- [x] **Step 7: Move the feature branch onto `dev`.** The feature branch has no commits yet, so point it at `dev` and switch back.

```shell
git branch -f feature/path-query dev
git switch feature/path-query
```

## Task 2: Parser, lookup and project registration

**Status:** parser and its harness are drafted and pass 31 assertions. The review found parser gaps, listed in Step 3.

**Files:**
- Create: `Tinycast/Features/FileSearch/Model/FileSearchPathQuery.swift`
- Create: `Tinycast/Features/FileSearch/Service/FileSearchPathLookup.swift`
- Create: `Tests/file-search-path-test.swift`
- Modify: `Scripts/run-tests.sh`
- Regenerate: `Tinycast.xcodeproj/project.pbxproj`

**Interfaces:**
- Produces:

```swift
enum FileSearchPathQuery {
    enum Kind: Equatable, Sendable { case file, directory }
    struct Location: Equatable, Sendable { let path: String; let kind: Kind; let line: Int?; let column: Int? }
    typealias Probe = (String) -> Kind?
    static func resolve(_ query: String, homeDirectory: String, probe: Probe) -> Location?
    static func leading(_ pasted: FileSearchResult?, before found: [FileSearchResult], limit: Int) -> [FileSearchResult]
}

enum FileSearchPathLookup {
    static func result(
        for query: String, fileManager: FileManager = .default, isAllowed: () -> Bool = { true }
    ) -> FileSearchResult?
}
```

- [x] **Step 1: Write the first harness and parser**, covering shapes, spellings, positions and existence.
- [x] **Step 2: Write the lookup.**
- [x] **Step 3: Write the failing tests for the review findings** in `Tests/file-search-path-test.swift`, then make them pass in the parser.

```swift
expect(resolve("/", existing: ["/"]) == nil, "a bare slash earns no row")
expect(resolve("/..", existing: ["/"]) == nil, "slash dot-dot is the root")
expect(resolve("~", existing: ["/Users/test/"]) == nil, "a bare tilde earns no row")
expect(resolve("~/.", existing: ["/Users/test/"]) == nil, "tilde dot is the home folder")
expect(resolve("file://otherhost/Users/test/a.txt", existing: files) == nil, "a foreign host is no path")
expect(resolve("file://localhost/Users/test/a.txt", existing: files)?.kind == .file, "localhost is this machine")
expect(resolve("FILE:///Users/test/a.txt", existing: files)?.kind == .file, "the scheme is case-insensitive")
expect(resolve("file:/Users/test/a.txt", existing: files)?.kind == .file, "a single-slash file URL resolves")
expect(resolve("\" /Users/test/a.txt \"", existing: files)?.kind == .file, "space inside quotes is trimmed")
expect(resolve("/Users/test/a.swift:42:7:", existing: files)?.column == 7, "one trailing colon is allowed")
expect(resolve("\u{FEFF}/Users/test/a.txt", existing: files)?.kind == .file, "a leading BOM is ignored")
expect(resolve("/Users/test/a.txt /Users/test/b.txt", existing: files) == nil, "two joined paths are no path")
expect(resolve("/Users/test/a.txt/", existing: files)?.path == "/Users/test/a.txt", "a trailing slash is dropped")
```

- [x] **Step 4: Run the harness and see the new tests fail**, then fix the parser until it prints `File search path tests passed`.

```shell
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swiftc -swift-version 6 -Onone Tinycast/Features/FileSearch/Model/*.swift \
  Tinycast/Features/FileSearch/Service/FileSearchPathLookup.swift \
  Tests/file-search-path-test.swift -o /tmp/fsp-test && /tmp/fsp-test
```

- [x] **Step 5: Add the real-filesystem tests** for the lookup, using a temporary directory with a file, a folder and a missing path.

```swift
expect(FileSearchPathLookup.result(for: file.path)?.isDirectory == false, "a real file resolves to a file row")
expect(FileSearchPathLookup.result(for: folder.path)?.isDirectory == true, "a real folder resolves to a folder row")
expect(FileSearchPathLookup.result(for: folder.path + "/missing") == nil, "a missing path earns no row")
expect(FileSearchPathLookup.result(for: "safari") == nil, "ordinary text earns no row")
expect(FileSearchPathLookup.result(for: file.path)?.id == file.path, "the row id is the path as typed")
```

- [x] **Step 6: Register the harness** with a marker line above it, so the check finds the edit.

```shell
# FORK(path-query)
run file-search-path-test  $FS/Model/*.swift $FS/Service/FileSearchPathLookup.swift
```

- [x] **Step 7: Shorten the comments** to one line of at most 100 characters, and format only the fork's files.

```shell
"$(xcrun --find swift-format)" --configuration .swift-format --in-place \
  Tinycast/Features/FileSearch/Model/FileSearchPathQuery.swift \
  Tinycast/Features/FileSearch/Service/FileSearchPathLookup.swift \
  Tests/file-search-path-test.swift
```

- [x] **Step 8: Regenerate the project and check the diff.** Expected: only entries for the two new sources.

```shell
xcodegen generate
git diff --stat Tinycast.xcodeproj
```

- [x] **Step 9: Build Debug.** Expected: `** BUILD SUCCEEDED **`. Nothing calls the new code yet.

```shell
xcodebuild -project Tinycast.xcodeproj -scheme Tinycast -configuration Debug \
  -derivedDataPath /tmp/tinycast-dd CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY=- build
```

- [x] **Step 10: Commit.**

```shell
git add Tinycast/Features/FileSearch Tests/file-search-path-test.swift Scripts/run-tests.sh Tinycast.xcodeproj
git commit -m "Add a path query parser and filesystem lookup"
```

## Task 3: The row

**Files:**
- Create: `Tinycast/Features/FileSearch/UI/FileSearchCoordinator+PastedPath.swift`
- Modify: `Tinycast/Features/Launcher/UI/LauncherScreen.swift:77`
- Regenerate: `Tinycast.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `FileSearchCoordinator.launcherFiles(for:) -> [FileSearchResult]`, `FileSearchCoordinator.showsFilesInLauncher`, `FileSearchPathLookup.result(for:fileManager:)`, `Permissions.hasFullDiskAccess() -> Bool`, `Memo<Key, Value>` in `Tinycast/Platform/Memo.swift`, `FileSearchQuery.launcherLimit`.
- Produces:

```swift
extension FileSearchCoordinator {
    func launcherFilesLeadingWithPastedPath(for query: String) -> [FileSearchResult]
}
```

- [x] **Step 1: Implement the extension.** It calls `launcherFiles(for:)`, then, when `showsFilesInLauncher` holds, looks up the pasted-path row through a one-slot `Memo` keyed by the query and the current second, on a `@MainActor` enum as `CalcMemo` does. The lookup gets `isAllowed: Permissions.hasFullDiskAccess`, and a cached row is re-checked with one `fileExists` so a trashed row vanishes. `FileSearchPathQuery.leading` puts the row first, drops the same `id` from the rest, and cuts the list to `FileSearchQuery.launcherLimit`.
- [x] **Step 2: Change the one call site** in `LauncherScreen.swift:77` to call `launcherFilesLeadingWithPastedPath(for: vm.query)`, with a `// FORK(path-query): lead with a pasted path.` comment on the line above.
- [x] **Step 3: Regenerate the project and build Debug.** Expected: only the new extension file is added, and `** BUILD SUCCEEDED **`.
- [x] **Step 4: Format the new file** with the command from Task 2 Step 7.
- [x] **Step 5: Commit.**

```shell
git add Tinycast/Features/FileSearch/UI Tinycast/Features/Launcher/UI/LauncherScreen.swift Tinycast.xcodeproj
git commit -m "Lead the launcher's Files section with a pasted path"
```

## Task 4: Feature doc

**Files:**
- Create: `docs/fork/path-query.md`
- Create: `docs/fork/path-query-spec.md` and `docs/fork/path-query-plan.md` (already written)

**Interfaces:**
- Produces: a feature change log with a `| File |` table that lists every file in the File Structure table above for this feature, including `Tinycast.xcodeproj/project.pbxproj` and the marked hooks.

- [x] **Step 1: Write `docs/fork/path-query.md`** with behaviour, spellings, the file table, the hooks, how to run the tests, what is not done, and how to remove the feature. Removal includes the project file.
- [x] **Step 2: Run `./Scripts/fork-check.sh`.** Expected: exit 0.
- [x] **Step 3: Commit.**

```shell
git add docs/fork
git commit -m "Document the path query feature"
```

## Task 5: Verification

**Files:**
- None changed. This task records evidence.

- [x] **Step 1: Run the whole suite.** Result: 111 of 114 pass. `form-input-test` and `callout-test` fail the same way on clean upstream, and `mcp-stdio-test` failed only under load and passes alone.

```shell
./Scripts/run-tests.sh
```

- [x] **Step 2: Build Release** as well as Debug, as `docs/testing.md` requires. Result: both succeed with signing off.
- [x] **Step 3: Check formatting of the fork's Swift files only.** Result: clean, and the one edited line in `LauncherScreen.swift` is format-clean.
- [x] **Step 4: Run `./Scripts/fork-check.sh`.** Result: exit 0.
- [ ] **Step 5 (skipped): Lint.** `swiftlint` is not installed, so `./Scripts/lint.sh` cannot run. Record the skip in `docs/fork/path-query.md` unless the user approves installing it.
- [ ] **Step 6 (not done, needs the GUI): Count probes.** Temporarily count calls to `FileSearchPathLookup.result`, type one 40-character path into a Debug build, and expect one call per distinct query. Remove the counter.
- [ ] **Step 7 (not done, needs the GUI): Manual checks** in the Debug app `Tinycast Dev.app`, with File Search and **Show in launcher** on. Computer use is unavailable here, so the user runs these and reports.

| Check | Pass condition |
|---|---|
| Paste the path of an existing file | One row first, and ↵ opens the file. |
| Paste the path of an existing folder | One row first, and ↵ opens it in Finder. |
| Paste `"/path/with spaces/x"` and `/path/with\ spaces/x` | The same row. |
| Paste a path that does not exist | No row, and results unchanged. |
| Type `safari` | Results unchanged. |
| Turn **Show in launcher** off, paste an existing path | No row. |
| Paste `/` and `~` | No row. |

## Task 6: Final review

**Files:**
- None changed.

- [x] **Step 1: Give a fresh Opus reviewer at high effort** the full diff against `upstream/main`, the spec and this plan, with write access removed.
- [ ] **Step 2: Triage every finding** as fixed, rejected with a reason, or deferred into `docs/fork/path-query.md` under Not done.
- [ ] **Step 3: Re-run Task 5 steps 1 to 4** after any fix.

## Task 7: Land on dev

**Files:**
- None changed.

- [ ] **Step 1: Merge the feature into `dev` with a merge commit.**

```shell
git -C /Users/amryadam/Github/tinycast-worktrees/dev merge --no-ff feature/path-query
```

- [ ] **Step 2: Record the merge** in the sync log in `docs/fork/README.md`.
- [ ] **Step 3: Ask the user before pushing.** Pushing publishes the code on a public fork. Disable GitHub Actions on `origin` first, then push `dev`.

## Task 8: Sync script

A separate plan, written after Task 7 lands, because it depends on a first real upstream merge.
Scope: fetch `upstream`, fast-forward `main`, merge into `dev` in a throwaway worktree, regenerate the project on a `project.pbxproj` conflict, run the tests and both builds, and stop with a report on any other conflict or failure.
