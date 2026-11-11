import Foundation

// One render builds the launcher screen about 14 times, so the lookup runs once per query.
@MainActor
private enum PastedPathMemo {
    static var memo = Memo<String, FileSearchResult?>()
}

extension FileSearchCoordinator {
    /// `launcherFiles(for:)` with the row for a pasted path first.
    func launcherFilesLeadingWithPastedPath(for query: String) -> [FileSearchResult] {
        let found = launcherFiles(for: query)
        guard showsFilesInLauncher else { return found }
        let pasted = PastedPathMemo.memo.value(for: query) {
            FileSearchPathLookup.result(for: query, isAllowed: Permissions.hasFullDiskAccess)
        }
        guard let pasted else { return found }
        return Array(([pasted] + found.filter { $0.id != pasted.id }).prefix(FileSearchQuery.launcherLimit))
    }
}
