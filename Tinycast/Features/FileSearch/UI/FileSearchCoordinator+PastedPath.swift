import Foundation

@MainActor
private enum PastedPathMemo {
    struct Key: Equatable {
        let query: String
        let second: Int
    }

    static var memo = Memo<Key, FileSearchResult?>()
}

extension FileSearchCoordinator {
    /// `launcherFiles(for:)` with the row for a pasted path first.
    func launcherFilesLeadingWithPastedPath(for query: String) -> [FileSearchResult] {
        let found = launcherFiles(for: query)
        guard showsFilesInLauncher else { return found }
        // One render builds the screen about 14 times; the second keeps a late file from staying unseen.
        let key = PastedPathMemo.Key(query: query, second: Int(Date.now.timeIntervalSince1970))
        let cached = PastedPathMemo.memo.value(for: key) {
            FileSearchPathLookup.result(for: query, isAllowed: Permissions.hasFullDiskAccess)
        }
        // Trashing re-renders inside the same second, so a cached row is checked once more.
        let pasted = cached.flatMap { FileManager.default.fileExists(atPath: $0.id) ? $0 : nil }
        return FileSearchPathQuery.leading(pasted, before: found, limit: FileSearchQuery.launcherLimit)
    }
}
