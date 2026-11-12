# Feature: path-suffix

Typing part of a path, such as `dev/Tinycast/Features/Updates/UI/UpdatePill.swift`, finds the file that path ends at.
It works in the launcher's Files section and in the Search Files screen.
The related feature for a full absolute path is [path-query.md](path-query.md).
The fork's rules are in [README.md](README.md).

## Contents

- [Behaviour](#behaviour)
- [Files](#files)
- [Hook in upstream code](#hook-in-upstream-code)
- [Tests](#tests)
- [Not done](#not-done)
- [Removing it](#removing-it)

## Behaviour

- A query is a partial path when it has at least two parts separated by `/` and is not absolute, not `~`, and not a `file:` URL.
- Every part before the last must equal a whole folder name, ignoring case and accents.
  `Updates/UI/UpdatePill.swift` finds the file, and `Update/UI/UpdatePill.swift` does not.
- The last part must be contained in the file name, so a half-typed name such as `UI/UpdateP` already finds it.
- The match is anchored at the end of the path, so a short tail such as `UI/UpdatePill.swift` finds every file that ends that way, and a longer one narrows it to one folder tree.
- A path that fits nothing finds nothing, rather than falling back to a name search.
- The last part needs at least three characters, as the launcher's own searches do.
- Leading `./`, doubled slashes, a trailing slash and one pair of quotes are ignored. A `..` anywhere makes it no partial path.
- It uses the same index as ordinary search, so it needs File Search on and follows the same scopes and ignore rules.
  A file in an ignored folder or outside the scopes is not found, unlike a full pasted path.
- Rows are ordinary Files rows, ranked as the index ranks the name.

## Files

| File | Change | Purpose | Conflict risk |
|---|---|---|---|
| `Tinycast/Features/FileSearch/Model/FileSearchPathFragment.swift` | New | Pure parser and matcher, and the wrapper that searches by the last part and keeps the matches. | None |
| `Tests/file-search-path-test.swift` | Edited | Unit tests for the parser, the matcher and the wrapper, added to the path-query harness. | None |
| `Tests/file-search-fragment-test.swift` | New | A real index on disk and the real session, asked with partial paths. | None |
| `Tinycast/Features/FileSearch/Service/FileSearchSession.swift` | Edited | One marked hunk in the default search operation. | Low |
| `Tinycast/Features/FileSearch/Service/FileIndex.swift` | Edited | `search` takes a `limit`, defaulting to the ordinary 200, so a partial path can ask for more candidates. | Low |
| `Scripts/run-tests.sh` | Edited | Registers `file-search-fragment-test`, two lines after `file-search-path-test`. | Low |
| `Tinycast.xcodeproj/project.pbxproj` | Regenerated | Four lines for the new source. Resolve a conflict by regenerating. | Medium |
| `docs/fork/path-suffix.md` | New | This file. | None |

## Hooks in upstream code

```swift
// FORK(path-suffix): a partial path is searched by its file name, then narrowed to the path.
if let found = FileSearchPathFragment.results(
    for: query, search: { index.search($0, filter: filter, limit: $1) })
{
    return found
}
```

```swift
// FORK(path-suffix): a partial path asks for more candidates, because it narrows them afterwards.
func search(
    _ query: FileSearchQuery.Prepared, filter: FileSearchFilter,
    limit: Int = FileSearchQuery.resultLimit
) -> [FileSearchResult]
```

```shell
# FORK(path-suffix)
run file-search-fragment-test $FS/Model/*.swift $FS/Service/FileSearchSession.swift $FILE_INDEX
```

## Tests

```shell
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
./Scripts/run-tests.sh file-search-path-test
./Scripts/run-tests.sh file-search-fragment-test
./Scripts/fork-check.sh
```

## Not done

| Item | Note |
|---|---|
| Extremely common file names | A partial path fetches up to 20,000 name matches before the path is checked, so a name in a few hundred places still finds the typed path. A name in more than 20,000 places can miss. |
| Middle of a path | The match is anchored at the end. `Features/Updates` alone, without the file, finds a folder only when it ends the query. |
| `a/` and `b/` prefixes | A path copied from a git diff keeps its `a/` or `b/`, which is then a folder that does not exist. |
| Search Files from the launcher | The fallback row seeds the screen with the query, which then searches the same way. Not checked by hand. |
| Manual checks in the app | The index and session are tested on a real temporary index. The rows in the app are for the user to check. |

## Removing it

1. Revert the feature's merge commit on `dev`, or delete the new files listed above.
2. Undo the marked edits.
3. Run `xcodegen generate` so the project file drops the new source.
