import Foundation

@main
struct FileSearchPathTests {
    nonisolated(unsafe) static var failures = 0
    static let home = "/Users/test"

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    // A tiny filesystem: every listed path exists, folders marked by a trailing slash.
    static func resolve(_ query: String, existing: [String]) -> FileSearchPathQuery.Location? {
        var kinds: [String: FileSearchPathQuery.Kind] = [:]
        for entry in existing {
            let isFolder = entry.hasSuffix("/")
            kinds[isFolder && entry.count > 1 ? String(entry.dropLast()) : entry] =
                isFolder ? .directory : .file
        }
        return FileSearchPathQuery.resolve(query, homeDirectory: home) { kinds[$0] }
    }

    static func main() {
        shapes()
        spelling()
        fileURLs()
        excluded()
        positions()
        existence()
        lookup()
        leading()
        fragments()
        fragmentMatching()
        fragmentSearch()

        print(failures == 0 ? "File search path tests passed" : "\(failures) file search path tests failed")
        exit(failures == 0 ? 0 : 1)
    }

    static func shapes() {
        let files = ["/Users/test/a.txt", "/Users/test/Docs/"]
        expect(resolve("/Users/test/a.txt", existing: files)?.kind == .file, "an absolute file path resolves")
        expect(resolve("/Users/test/Docs", existing: files)?.kind == .directory, "a folder path resolves")
        expect(
            resolve("/Users/test/Docs/", existing: files)?.path == "/Users/test/Docs",
            "a trailing slash is dropped")
        expect(
            resolve("/Users/test/a.txt/", existing: files)?.path == "/Users/test/a.txt",
            "a trailing slash on a file is dropped")
        expect(resolve("a.txt", existing: files) == nil, "a bare name is no path")
        expect(resolve("Users/test/a.txt", existing: files) == nil, "a relative path is no path")
        expect(resolve("", existing: files) == nil, "an empty query is no path")
        expect(
            resolve("/Users/test/a.txt /Users/test/b.txt", existing: files) == nil,
            "two joined paths are no path")
    }

    static func spelling() {
        let files = ["/Users/test/a.txt", "/Users/test/My Folder/", "/Users/test/My Folder/x.txt"]
        expect(resolve("~/a.txt", existing: files)?.path == "/Users/test/a.txt", "~/ expands to home")
        expect(resolve("~a.txt", existing: files) == nil, "~name is not the home folder")
        expect(resolve("\\~/a.txt", existing: files) == nil, "an escaped tilde is not the home folder")
        expect(
            resolve("~/My\\ Folder/x.txt", existing: files)?.path == "/Users/test/My Folder/x.txt",
            "an escaped space after ~/ is unescaped")
        expect(
            resolve("  /Users/test/a.txt \n", existing: files)?.path == "/Users/test/a.txt",
            "whitespace is trimmed")
        expect(resolve("\"/Users/test/a.txt\"", existing: files)?.kind == .file, "double quotes are stripped")
        expect(resolve("'/Users/test/a.txt'", existing: files)?.kind == .file, "single quotes are stripped")
        expect(resolve("“/Users/test/a.txt”", existing: files)?.kind == .file, "curly quotes are stripped")
        expect(resolve("\" /Users/test/a.txt \"", existing: files)?.kind == .file, "space inside quotes goes")
        expect(resolve("\"/Users/test/a.txt", existing: files) == nil, "an unmatched quote is no path")
        expect(
            resolve("/Users/test/My\\ Folder/x.txt", existing: files)?.path == "/Users/test/My Folder/x.txt",
            "a backslash-escaped space is unescaped")
        expect(
            resolve("'~/My Folder'", existing: files)?.path == "/Users/test/My Folder",
            "a quoted path keeps its spaces and expands ~")
        expect(
            resolve("/Users/test/Docs/../a.txt", existing: files)?.path == "/Users/test/a.txt",
            "dot-dot segments are resolved")
        expect(
            resolve("//Users/test/a.txt", existing: files)?.path == "/Users/test/a.txt",
            "a doubled slash is one")
        expect(
            resolve("\u{FEFF}/Users/test/a.txt", existing: files)?.kind == .file, "a leading BOM is ignored")
    }

    static func fileURLs() {
        let files = ["/Users/test/a.txt", "/Users/test/My Folder/x.txt"]
        expect(
            resolve("file:///Users/test/My%20Folder/x.txt", existing: files)?.path
                == "/Users/test/My Folder/x.txt",
            "a file URL is decoded")
        expect(
            resolve("FILE:///Users/test/a.txt", existing: files)?.kind == .file,
            "the scheme is case-insensitive")
        expect(
            resolve("file:/Users/test/a.txt", existing: files)?.kind == .file,
            "a single-slash file URL resolves")
        expect(
            resolve("file://localhost/Users/test/a.txt", existing: files)?.kind == .file,
            "localhost is this machine")
        expect(
            resolve("file://otherhost/Users/test/a.txt", existing: files) == nil,
            "a foreign host is no path")
        expect(resolve("https://example.com/a", existing: files) == nil, "a web address is no path")
    }

    static func excluded() {
        let everything = ["/", "/Users/test/", "/Users/test/a.txt"]
        expect(resolve("/", existing: everything) == nil, "a bare slash earns no row")
        expect(resolve("/..", existing: everything) == nil, "slash dot-dot is the root")
        expect(resolve("~", existing: everything) == nil, "a bare tilde earns no row")
        expect(resolve("~/", existing: everything) == nil, "tilde slash is the home folder")
        expect(resolve("~/.", existing: everything) == nil, "tilde dot is the home folder")
        expect(
            resolve("/Users/test", existing: everything) == nil, "the home folder spelled out earns no row")
        expect(resolve("/:7", existing: everything) == nil, "a position never rescues the root")
        expect(
            resolve("/Users/test/a.txt", existing: everything)?.kind == .file, "a file in home still resolves"
        )
    }

    static func positions() {
        let files = ["/Users/test/a.swift", "/Users/test/b:7"]
        let line = resolve("/Users/test/a.swift:42", existing: files)
        expect(
            line?.path == "/Users/test/a.swift" && line?.line == 42 && line?.column == nil,
            ":line is peeled off")
        let both = resolve("/Users/test/a.swift:42:7", existing: files)
        expect(both?.line == 42 && both?.column == 7, ":line:col is peeled off")
        expect(
            resolve("/Users/test/a.swift:42:7:", existing: files)?.column == 7,
            "one trailing colon is allowed")
        let real = resolve("/Users/test/b:7", existing: files)
        expect(
            real?.path == "/Users/test/b:7" && real?.line == nil, "a real file named b:7 is not a position")
        let inside = resolve("/Users/test/b:7:3", existing: files)
        expect(
            inside?.path == "/Users/test/b:7" && inside?.line == 3 && inside?.column == nil,
            "a shorter suffix is used when the longer one names nothing")
        let ambiguous = resolve("/Users/test/b:7:3", existing: ["/Users/test/b", "/Users/test/b:7"])
        expect(
            ambiguous?.path == "/Users/test/b" && ambiguous?.line == 7 && ambiguous?.column == 3,
            "when both exist the longer suffix is read first")
        expect(
            resolve("/Users/test/a.swift:x", existing: files) == nil, "a non-numeric suffix is not a position"
        )
        expect(
            resolve("/Users/test/a.swift:", existing: files)?.line == nil,
            "a bare trailing colon is no position")
        expect(
            resolve("/Users/test/missing:42", existing: files) == nil,
            "a position never rescues a missing file")
        expect(
            resolve("/Users/test/a.swift:99999999999999999999", existing: files) == nil,
            "an overflowing number is not a position")
    }

    static func row(_ name: String) -> FileSearchResult {
        FileSearchResult(
            url: URL(filePath: "/Users/test/\(name)"), isDirectory: false,
            homeDirectory: URL(filePath: home))
    }

    static func leading() {
        let (a, b, c, d, e, pasted) = (row("a"), row("b"), row("c"), row("d"), row("e"), row("p"))
        expect(
            FileSearchPathQuery.leading(nil, before: [a, b], limit: 5) == [a, b],
            "no pasted row leaves the list")
        expect(
            FileSearchPathQuery.leading(pasted, before: [a, b], limit: 5) == [pasted, a, b],
            "the pasted row leads")
        expect(
            FileSearchPathQuery.leading(pasted, before: [], limit: 5) == [pasted],
            "an empty list still shows it")
        expect(
            FileSearchPathQuery.leading(a, before: [b, a], limit: 5) == [a, b], "a repeated path appears once"
        )
        expect(
            FileSearchPathQuery.leading(pasted, before: [a, b, c, d, e], limit: 5) == [pasted, a, b, c, d],
            "the cut keeps the pasted row and drops the tail")
        expect(
            FileSearchPathQuery.leading(pasted, before: [a, b], limit: 1) == [pasted],
            "a limit of one keeps it")
    }

    // MARK: - Partial paths

    static func fragment(_ query: String) -> FileSearchPathFragment.Fragment? {
        FileSearchPathFragment.parse(query)
    }

    static func fragments() {
        let full = fragment("dev/Tinycast/Features/Updates/UI/UpdatePill.swift")
        expect(full?.folders == ["dev", "tinycast", "features", "updates", "ui"], "the folders are kept in order")
        expect(full?.name == "UpdatePill.swift", "the file name is kept as typed")
        expect(fragment("UI/UpdatePill.swift")?.folders == ["ui"], "two parts are enough")
        expect(fragment("UpdatePill.swift") == nil, "a bare name is no partial path")
        expect(fragment("dev/") == nil, "one folder alone is no partial path")
        expect(fragment("/Users/test/a/b.txt") == nil, "an absolute path is the pasted-path feature's")
        expect(fragment("~/a/b.txt") == nil, "a home path is the pasted-path feature's")
        expect(fragment("file:///a/b.txt") == nil, "a file URL is the pasted-path feature's")
        expect(fragment("../a/b.txt") == nil, "a parent step names nothing")
        expect(fragment("a/../b/c.txt") == nil, "a parent step in the middle names nothing")
        expect(fragment("./a/b.txt")?.folders == ["a"], "a leading ./ is dropped")
        expect(fragment("a//b.txt")?.folders == ["a"], "a doubled slash is one slash")
        expect(fragment("a/b.txt/")?.name == "b.txt", "a trailing slash is dropped")
        expect(fragment("  a/b.txt \n")?.name == "b.txt", "surrounding space is dropped")
        expect(fragment("\"a/b.txt\"")?.name == "b.txt", "one pair of quotes is dropped")
        expect(fragment("a/xy") == nil, "a name under the launcher's minimum is too short to search")
        expect(fragment("My Folder/My File.txt")?.folders == ["my folder"], "spaces stay inside a part")
        expect(fragment("Docs/Résumé.pdf")?.name == "Résumé.pdf", "accents are kept as typed")
    }

    static func path(_ text: String) -> FileSearchResult {
        FileSearchResult(url: URL(filePath: text), isDirectory: false, homeDirectory: URL(filePath: home))
    }

    static func fragmentMatching() {
        let query = "dev/Tinycast/Features/Updates/UI/UpdatePill.swift"
        let target = "/Users/test/Github/tinycast-worktrees/dev/Tinycast/Features/Updates/UI/UpdatePill.swift"
        func matches(_ file: String, _ query: String = query) -> Bool {
            guard let fragment = fragment(query) else { return false }
            return FileSearchPathFragment.matches(file, fragment)
        }
        expect(matches(target), "the end of the path matches")
        expect(
            !matches("/Users/test/Github/tinycast-worktrees/fork-sync/Tinycast/Features/Updates/UI/UpdatePill.swift"),
            "the same file under another folder does not match")
        expect(matches(target.uppercased()), "case does not matter")
        expect(
            matches("/Users/test/Github/tinycast-worktrees/dev/tinycast/features/updates/ui/updatepill.swift"),
            "case does not matter in the folders either")
        expect(
            !matches("/x/dev/Tinycast/Features/Update/UI/UpdatePill.swift"), "a folder must match whole, not in part")
        expect(
            !matches("/x/dev/Tinycast/Features/Updates/xUI/UpdatePill.swift"), "a folder may not merely end alike")
        expect(!matches("/Tinycast/Features/Updates/UI/UpdatePill.swift"), "a path shorter than the query cannot match")
        expect(
            matches("/x/dev/Tinycast/Features/Updates/UI/OldUpdatePill.swift"),
            "a file name that merely contains the typed one still matches")
        expect(
            !matches("/x/dev/Tinycast/Features/Updates/UI/UpdatePillTests.swift"),
            "a name that does not contain the typed one does not")
        expect(matches(target, "UI/UpdatePill.swift"), "a shorter tail matches the same file")
        expect(matches(target, "ui/updatepill"), "a half-typed name matches")
        expect(!matches(target, "Updates/UpdatePill.swift"), "a gap in the folders does not match")
        expect(
            matches("/Users/test/Résumé/Docs/a.pdf", "resume/Docs/a.pdf"), "accents do not matter in a folder")
    }

    static func fragmentSearch() {
        let hit = path("/x/dev/Tinycast/UI/UpdatePill.swift")
        let other = path("/x/fork-sync/Tinycast/UI/UpdatePill.swift")
        let plain = path("/x/UpdatePill.swift")
        var asked: [[String]] = []
        let found = FileSearchPathFragment.results(for: "dev/Tinycast/UI/UpdatePill.swift") { prepared in
            asked.append(prepared.terms.map { String(decoding: $0, as: UTF8.self) })
            return [other, hit, plain]
        }
        expect(found == [hit], "only the file under the typed path is kept")
        expect(asked == [["updatepill.swift"]], "the search is for the file name alone, asked once")

        var calls = 0
        let ordinary = FileSearchPathFragment.results(for: "UpdatePill") { _ in
            calls += 1
            return [hit]
        }
        expect(ordinary == nil, "ordinary text is left to the ordinary search")
        expect(calls == 0, "and asks the index nothing")

        let none = FileSearchPathFragment.results(for: "dev/Nothing/UpdatePill.swift") { _ in [hit, other] }
        expect(none == [], "a partial path that fits nothing finds nothing, rather than falling back")
        let order = FileSearchPathFragment.results(for: "Tinycast/UI/UpdatePill.swift") { _ in [other, hit] }
        expect(order == [other, hit], "the index's order is kept")
    }

    static func existence() {
        expect(
            resolve("/Users/test/none.txt", existing: ["/Users/test/a.txt"]) == nil,
            "a missing path earns nothing")
        expect(resolve("/Users/test/a.txt", existing: []) == nil, "nothing exists on an empty disk")
    }

    static func lookup() {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "fs-path-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        let folder = root.appending(path: "My Folder", directoryHint: .isDirectory)
        let file = folder.appending(path: "note.txt", directoryHint: .notDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: file.path, contents: Data("x".utf8))
        defer { try? FileManager.default.removeItem(at: root) }

        expect(FileSearchPathLookup.result(for: file.path)?.isDirectory == false, "a real file is a file row")
        expect(
            FileSearchPathLookup.result(for: folder.path)?.isDirectory == true,
            "a real folder is a folder row")
        expect(FileSearchPathLookup.result(for: file.path)?.id == file.path, "the row id is the path")
        expect(FileSearchPathLookup.result(for: file.path)?.name == "note.txt", "the row carries the name")
        expect(
            FileSearchPathLookup.result(for: file.path.replacingOccurrences(of: " ", with: "\\ "))?.id
                == file.path,
            "an escaped space finds the same row")
        expect(
            FileSearchPathLookup.result(for: folder.path + "/missing") == nil, "a missing path earns no row")
        expect(FileSearchPathLookup.result(for: "safari") == nil, "ordinary text earns no row")
        var asked = 0
        let denied = FileSearchPathLookup.result(
            for: file.path,
            isAllowed: {
                asked += 1; return false
            })
        expect(denied == nil, "a denied lookup earns no row")
        expect(asked == 1, "the gate is asked once for a path")
        asked = 0
        _ = FileSearchPathLookup.result(
            for: "safari",
            isAllowed: {
                asked += 1; return true
            })
        _ = FileSearchPathLookup.result(
            for: "",
            isAllowed: {
                asked += 1; return true
            })
        expect(asked == 0, "text that is no path never asks the gate")
        expect(FileSearchPathLookup.result(for: "/") == nil, "the root earns no row")
        expect(
            FileSearchPathLookup.result(for: NSHomeDirectory()) == nil, "the real home folder earns no row")
    }
}
