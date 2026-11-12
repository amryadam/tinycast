import Foundation

/// A partial path such as `Features/Updates/UI/UpdatePill.swift`, which finds the files that end that way.
///
/// File names never contain a slash, so the name index cannot answer such a query itself. It is
/// searched by its last part, and the matches are kept when their path ends as the query does.
enum FileSearchPathFragment {
    struct Fragment: Equatable, Sendable {
        /// Every part before the last, folded for comparison. Each must match a whole folder name.
        let folders: [String]
        /// The last part as typed. A file name only has to contain it, so a half-typed name still finds the file.
        let name: String
    }

    /// Nil for anything that is not a relative path of at least two parts, so ordinary text and the
    /// pasted-path feature's absolute paths are left alone.
    static func parse(_ query: String) -> Fragment? {
        var text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        text = unquoted(text).trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = text.lowercased()
        guard !text.hasPrefix("/"), !text.hasPrefix("~"), !lowered.hasPrefix("file:") else { return nil }

        var parts = text.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        while parts.first == "." { parts.removeFirst() }
        guard parts.count >= 2, !parts.contains(where: { $0 == "." || $0 == ".." }),
            parts.allSatisfy({ !$0.trimmingCharacters(in: .whitespaces).isEmpty }),
            // Below the launcher's own minimum a name matches too much, and the index keeps only its best.
            let name = parts.last, name.count >= FileSearchQuery.launcherMinimumLength
        else { return nil }
        return Fragment(folders: parts.dropLast().map(FileSearchQuery.fold), name: name)
    }

    /// Whether `path` ends in the fragment: whole folder names, then a file name containing the last part.
    static func matches(_ path: String, _ fragment: Fragment) -> Bool {
        let parts = path.split(separator: "/", omittingEmptySubsequences: true)
        guard parts.count > fragment.folders.count,
            let name = parts.last,
            FileSearchQuery.fold(String(name)).contains(FileSearchQuery.fold(fragment.name))
        else { return false }
        let folders = parts.dropLast().suffix(fragment.folders.count)
        return zip(folders, fragment.folders).allSatisfy { FileSearchQuery.fold(String($0)) == $1 }
    }

    /// How many name matches are fetched before the path narrows them. The ordinary search keeps 200,
    /// which a name found in many places would fill with other folders' files.
    static let candidateLimit = 20_000

    /// The matches for a partial path, found by searching for its file name, or nil when `query` is
    /// not a partial path and the ordinary search should run. `search` is given the name query and
    /// how many matches to return.
    static func results(
        for query: String, search: (FileSearchQuery.Prepared, Int) -> [FileSearchResult]
    ) -> [FileSearchResult]? {
        guard let fragment = parse(query), let prepared = FileSearchQuery.prepare(fragment.name) else {
            return nil
        }
        return search(prepared, candidateLimit).filter { matches($0.id, fragment) }
    }

    // One matching pair, as a copied path or a shell argument carries.
    private static func unquoted(_ text: String) -> String {
        let pairs: [(Character, Character)] = [("\"", "\""), ("'", "'"), ("“", "”"), ("‘", "’")]
        guard text.count >= 2, let first = text.first, let last = text.last,
            pairs.contains(where: { $0.0 == first && $0.1 == last })
        else { return text }
        return String(text.dropFirst().dropLast())
    }
}
