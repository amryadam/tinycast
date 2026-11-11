# Feature: path-query

Pasting the full path of an existing file or folder into the launcher shows it as the first row of the Files section.
The spec is [path-query-spec.md](path-query-spec.md) and the plan is [path-query-plan.md](path-query-plan.md).
The fork's rules are in [README.md](README.md).

## Contents

- [Behaviour](#behaviour)
- [Files](#files)
- [Hooks in upstream code](#hooks-in-upstream-code)
- [Tests](#tests)
- [Not done](#not-done)
- [Removing it](#removing-it)

## Behaviour

- It applies only with File Search on, **Show in launcher** on, and Full Disk Access granted to the app.
- The row is an ordinary Files row, so ↵ opens it, ⌘↵ reveals it, and the copy, share and favorite actions all work.
- A file opens in its default app, and a folder opens in Finder.
- A path that does not exist, the root folder and the home folder add nothing.
- The row shows even for paths in ignored folders or outside the configured search scopes.
- The accepted spellings are listed in the [spec](path-query-spec.md#accepted-spellings).

## Files

| File | Change | Purpose | Conflict risk |
|---|---|---|---|
| `Tinycast/Features/FileSearch/Model/FileSearchPathQuery.swift` | New | Pure parser: spelling, quotes, escapes, `~`, `file:`, positions, root and home rule. | None |
| `Tinycast/Features/FileSearch/Service/FileSearchPathLookup.swift` | New | Probes the filesystem and builds the `FileSearchResult`. | None |
| `Tinycast/Features/FileSearch/UI/FileSearchCoordinator+PastedPath.swift` | New | Adds the row, memoises it per query, and gates it on Full Disk Access. | None |
| `Tests/file-search-path-test.swift` | New | Harness for the parser and the lookup. | None |
| `Tinycast/Features/Launcher/UI/LauncherScreen.swift` | Edited | One line at the Files call site, marked `FORK(path-query)`. | Low |
| `Scripts/run-tests.sh` | Edited | Registers `file-search-path-test`, two lines after `file-search-test`. | Low |
| `Tinycast.xcodeproj/project.pbxproj` | Regenerated | Twelve lines for the three new sources. Resolve a conflict by regenerating. | Medium |
| `docs/fork/path-query.md` | New | This file. | None |
| `docs/fork/path-query-spec.md` | New | The spec. | None |
| `docs/fork/path-query-plan.md` | New | The plan. | None |

## Hooks in upstream code

```swift
// FORK(path-query): lead with a pasted path.
let files = pinned == nil ? core.fileSearchCoordinator.launcherFilesLeadingWithPastedPath(for: vm.query) : []
```

```shell
# FORK(path-query)
run file-search-path-test  $FS/Model/*.swift $FS/Service/FileSearchPathLookup.swift
```

## Tests

```shell
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
./Scripts/run-tests.sh file-search-path-test
./Scripts/fork-check.sh
```

## Not done

| Item | Note |
|---|---|
| Opening at `:line:col` | Needs an editor setting, and Tinycast has none yet. The parser already returns the position. |
| Open with… | File rows have no such action today, so it would be a separate addition. |
| A fresh state after the query is unchanged | The row is memoised by query, so a file created or trashed shows its old state until the query changes. |
| Slow network volumes | One probe per distinct query on the main thread, so an unresponsive share can stall typing once. |
| `swiftlint` | Not installed here, so `Scripts/lint.sh` was not run. |
| Manual checks in the app | Computer use is unavailable in the session that built this, so the user runs them. |

## Removing it

1. Revert the feature's merge commit on `dev`, or delete the new files listed above.
2. Undo the two marked edits.
3. Run `xcodegen generate` so the project file drops the new sources.
