import Foundation

// A real index on disk and the real session, asked with partial paths. See docs/fork/path-suffix.md.
@main
@MainActor
struct FileSearchFragmentTests {
    nonisolated(unsafe) static var failures = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static func main() async throws {
        let fm = FileManager.default
        let scratch = fm.temporaryDirectory.appending(path: "fs-fragment-test-\(UUID().uuidString)")
        try fm.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: scratch) }
        let root = URL(fileURLWithPath: realPath(scratch.path)).appending(path: "home")
        for file in [
            "work/dev/Tinycast/Features/Updates/UI/UpdatePill.swift",
            "work/fork-sync/Tinycast/Features/Updates/UI/UpdatePill.swift",
            "work/dev/Tinycast/Features/Updates/UI/UpdateCoordinator.swift",
            "work/dev/Tinycast/Features/Updates/Model/UpdatePill.swift",
            "work/dev/Résumé/Docs/cv.pdf",
            "work/dev/node_modules/pkg/UpdatePill.swift",
        ] {
            try write(root.appending(path: file))
        }
        let policy = FileSearchPolicy(
            scopes: [root.path], ignorePatterns: ["node_modules"], homeDirectory: root)
        let index = FileIndex()
        index.replace(with: try build(policy, at: scratch.appending(path: "index.bin")), policy: policy)
        let session = FileSearchSession(index: index)

        func ask(_ query: String) async -> [String] {
            session.search(query)
            let deadline = ContinuousClock.now.advanced(by: .seconds(5))
            while session.state != .ready, ContinuousClock.now < deadline {
                try? await Task.sleep(for: .milliseconds(10))
            }
            return session.results.map { String($0.id.dropFirst(root.path.count + 1)) }
        }

        func check(_ query: String, _ expected: [String], _ message: String) async {
            let found = await ask(query)
            expect(found.sorted() == expected.sorted(), "\(message): got \(found)")
        }

        let target = "work/dev/Tinycast/Features/Updates/UI/UpdatePill.swift"
        let forkSync = "work/fork-sync/Tinycast/Features/Updates/UI/UpdatePill.swift"
        let model = "work/dev/Tinycast/Features/Updates/Model/UpdatePill.swift"
        await check("dev/Tinycast/Features/Updates/UI/UpdatePill.swift", [target], "a partial path finds the file")
        await check("UI/UpdatePill.swift", [target, forkSync], "a shorter tail finds every file that ends so")
        await check("fork-sync/Tinycast/Features/Updates/UI/UpdatePill.swift", [forkSync], "another folder finds only its own file")
        await check("Updates/UI/UpdatePill", [target, forkSync], "a half-typed name still finds it")
        await check(
            "dev/Tinycast/Features/Updates/UI/UpdateCoordinator.swift",
            ["work/dev/Tinycast/Features/Updates/UI/UpdateCoordinator.swift"], "a different file under the same folders")
        await check("dev/Tinycast/Features/Updates/Model/UpdatePill.swift", [model], "the folder before the name decides which file")
        await check("resume/Docs/cv.pdf", ["work/dev/Résumé/Docs/cv.pdf"], "accents and case do not matter")
        await check("dev/Nothing/UpdatePill.swift", [], "a path that fits nothing finds nothing")
        await check("pkg/UpdatePill.swift", [], "an ignored folder stays ignored")
        await check("UpdatePill", [target, forkSync, model], "an ordinary name still searches by name alone")
        await check("\"dev/Tinycast/Features/Updates/UI/UpdatePill.swift\"", [target], "a quoted path works")

        print(failures == 0 ? "File search fragment tests passed" : "\(failures) file search fragment tests failed")
        exit(failures == 0 ? 0 : 1)
    }

    static func build(_ policy: FileSearchPolicy, at url: URL) throws -> FileIndexSnapshot {
        let roots = FileIndexCrawler.roots(of: policy)
        let listings = FileIndexCrawler.Crawl(roots: roots, policy: policy).run(workers: 2)
        try FileIndexSnapshot.write(
            listings, roots: roots, eventID: 1, fingerprint: policy.fingerprint, to: url)
        guard let snapshot = FileIndexSnapshot(contentsOf: url) else {
            print("FAIL: the written index does not map back")
            exit(1)
        }
        return snapshot
    }

    static func write(_ url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: url)
    }

    static func realPath(_ path: String) -> String {
        guard let resolved = realpath(path, nil) else { return path }
        defer { free(resolved) }
        return String(cString: resolved)
    }
}
