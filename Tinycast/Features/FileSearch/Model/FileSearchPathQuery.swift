import Foundation

/// A pasted filesystem path, resolved to a real location. Existence comes from an injected probe.
enum FileSearchPathQuery {
    enum Kind: Equatable, Sendable {
        case file
        case directory
    }

    struct Location: Equatable, Sendable {
        let path: String
        let kind: Kind
        let line: Int?
        let column: Int?
    }

    /// Answers what sits at an absolute path, or nil when nothing does.
    typealias Probe = (String) -> Kind?

    // The whole spelling is probed first, so a real file named `a:1` is not read as a position.
    static func resolve(_ query: String, homeDirectory: String, probe: Probe) -> Location? {
        let home = homeDirectory.hasSuffix("/") ? String(homeDirectory.dropLast()) : homeDirectory
        guard let path = spelling(of: query, home: home) else { return nil }
        let excluded: Set<String> = ["/", normalized(home)]
        func found(_ path: String) -> Kind? { excluded.contains(path) ? nil : probe(path) }

        if let kind = found(path) {
            return Location(path: path, kind: kind, line: nil, column: nil)
        }
        for candidate in positions(in: path) {
            if let kind = found(candidate.path) {
                return Location(
                    path: candidate.path, kind: kind, line: candidate.line, column: candidate.column)
            }
        }
        return nil
    }

    // MARK: - Spelling

    private static func spelling(of query: String, home: String) -> String? {
        var text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        text = unquoted(text).trimmingCharacters(in: .whitespacesAndNewlines)
        if text.lowercased().hasPrefix("file:") {
            guard let url = URL(string: text), url.isFileURL, isThisMachine(url.host) else { return nil }
            text = url.path
        } else {
            text = unescaped(text)
            if text == "~" || text.hasPrefix("~/") { text = home + text.dropFirst() }
        }
        guard text.hasPrefix("/") else { return nil }
        return normalized(text)
    }

    // A file URL with another host names a remote path, not one on this machine.
    private static func isThisMachine(_ host: String?) -> Bool {
        guard let host, !host.isEmpty else { return true }
        return host.lowercased() == "localhost"
    }

    // One matching pair, as a copied path or a shell argument carries.
    private static func unquoted(_ text: String) -> String {
        let pairs: [(Character, Character)] = [("\"", "\""), ("'", "'"), ("“", "”"), ("‘", "’")]
        guard text.count >= 2, let first = text.first, let last = text.last,
            pairs.contains(where: { $0.0 == first && $0.1 == last })
        else { return text }
        return String(text.dropFirst().dropLast())
    }

    // A backslash makes the next character literal, as a shell writes `My\ Folder`.
    private static func unescaped(_ text: String) -> String {
        var result = ""
        var escaped = false
        for character in text {
            if escaped || character != "\\" {
                result.append(character)
                escaped = false
            } else {
                escaped = true
            }
        }
        if escaped { result.append("\\") }
        return result
    }

    // By name alone: a symlink is never followed.
    private static func normalized(_ path: String) -> String {
        var parts: [Substring] = []
        for part in path.split(separator: "/") {
            switch part {
            case ".": continue
            case "..": if !parts.isEmpty { parts.removeLast() }
            default: parts.append(part)
            }
        }
        return "/" + parts.joined(separator: "/")
    }

    // MARK: - Position

    private struct Candidate {
        let path: String
        let line: Int
        let column: Int?
    }

    // Longest suffix first: `a:12:3` is line 12, column 3 of `a` before line 3 of `a:12`.
    private static func positions(in path: String) -> [Candidate] {
        let text = path.hasSuffix(":") ? String(path.dropLast()) : path
        guard let last = splitNumber(text[...]) else { return [] }
        var result: [Candidate] = []
        if let line = splitNumber(last.head) {
            result.append(Candidate(path: String(line.head), line: line.value, column: last.value))
        }
        result.append(Candidate(path: String(last.head), line: last.value, column: nil))
        return result.filter { $0.path.hasPrefix("/") }
    }

    private static func splitNumber(_ text: Substring) -> (head: Substring, value: Int)? {
        guard let colon = text.lastIndex(of: ":") else { return nil }
        let tail = text[text.index(after: colon)...]
        guard !tail.isEmpty, tail.allSatisfy({ $0.isASCII && $0.isNumber }), let value = Int(tail)
        else { return nil }
        return (text[..<colon], value)
    }
}
