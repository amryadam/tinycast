import Foundation

/// Side-by-side apps with their own bundle ids, so a build updates within its own.
enum ReleaseChannel: Sendable {
    case stable
    case beta
    /// A local build. It has no release stream, and never updates itself.
    case development
    /// FORK(fork-update): this fork's own builds, updated from the fork's releases.
    case fork

    init(bundleID: String?) {
        switch bundleID {
        case "com.tinycast.app": self = .stable
        case "com.tinycast.app.beta": self = .beta
        case "com.amryadam.tinycast": self = .fork  // FORK(fork-update)
        default: self = .development
        }
    }

    var updatesItself: Bool { self != .development }

    /// FORK(fork-update): the repository whose releases this channel reads.
    var repository: String { self == .fork ? "amryadam/tinycast" : "abue-ammar/tinycast" }

    /// Beta ships as a GitHub prerelease and stable does not; neither ever sees the other's.
    func accepts(prerelease: Bool) -> Bool {
        switch self {
        case .stable, .fork: return !prerelease  // FORK(fork-update)
        case .beta: return prerelease
        case .development: return false
        }
    }
}
