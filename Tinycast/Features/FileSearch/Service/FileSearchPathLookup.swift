import Foundation

/// The effect half of `FileSearchPathQuery`: probes the real filesystem and builds a Files row.
enum FileSearchPathLookup {
    // Only path-shaped text reaches the `stat`, so ordinary typing costs nothing.
    static func result(for query: String, fileManager: FileManager = .default) -> FileSearchResult? {
        let home = fileManager.homeDirectoryForCurrentUser
        let location = FileSearchPathQuery.resolve(query, homeDirectory: home.path) { path in
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory) else { return nil }
            return isDirectory.boolValue ? .directory : .file
        }
        guard let location else { return nil }
        let isDirectory = location.kind == .directory
        return FileSearchResult(
            url: URL(filePath: location.path, directoryHint: isDirectory ? .isDirectory : .notDirectory),
            isDirectory: isDirectory, homeDirectory: home)
    }
}
