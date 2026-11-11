import Foundation

/// The effect half of `FileSearchPathQuery`: probes the real filesystem and builds a Files row.
enum FileSearchPathLookup {
    // `isAllowed` is asked once, just before the first `stat`, so text that is no path never asks.
    static func result(
        for query: String, fileManager: FileManager = .default, isAllowed: () -> Bool = { true }
    ) -> FileSearchResult? {
        let home = fileManager.homeDirectoryForCurrentUser
        var allowed: Bool?
        let location = FileSearchPathQuery.resolve(query, homeDirectory: home.path) { path in
            if allowed == nil { allowed = isAllowed() }
            var isDirectory: ObjCBool = false
            guard allowed == true, fileManager.fileExists(atPath: path, isDirectory: &isDirectory)
            else { return nil }
            return isDirectory.boolValue ? .directory : .file
        }
        guard let location else { return nil }
        let isDirectory = location.kind == .directory
        return FileSearchResult(
            url: URL(filePath: location.path, directoryHint: isDirectory ? .isDirectory : .notDirectory),
            isDirectory: isDirectory, homeDirectory: home)
    }
}
