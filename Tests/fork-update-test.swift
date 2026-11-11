import Foundation

// Tests for the fork's update channel. See docs/fork/fork-update.md.
@main
@MainActor
struct ForkUpdateTests {
    static var failures = 0
    static var passes = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if condition() {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static func main() {
        parsesForkVersions()
        ordersForkVersions()
        roundTripsThroughTheCache()
        derivesTheForkChannel()
        namesTheRepositoryPerChannel()
        offersOnlyForkReleasesToTheFork()
        keepsForkReleasesAwayFromOtherChannels()
        skipsWhatIsNotInstallable()
        offersOnlyWhatIsNewer()
        readsTheLiveFeedShape()

        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    static func version(_ text: String) -> AppVersion {
        guard let parsed = AppVersion(text) else { fatalError("must parse: \(text)") }
        return parsed
    }

    // MARK: - AppVersion

    static func parsesForkVersions() {
        expect(AppVersion("0.12.11-fork.2")?.description == "0.12.11-fork.2", "round-trips a fork version")
        expect(AppVersion("v0.12.11-fork.2")?.fork == 2, "reads the fork counter from a tag")
        expect(AppVersion("0.12.11")?.fork == nil, "a plain version has no fork counter")
        expect(AppVersion("0.12.11-fork.2")?.isPrerelease == false, "a fork version is not a prerelease")
        expect(AppVersion("0.12.11-fork.2")?.beta == nil, "a fork version has no beta counter")

        for bad in [
            "0.12.11-fork", "0.12.11-fork.", "0.12.11-fork.x", "0.12.11-fork.-1",
            "0.12.11-fork.1.2", "0.12.11-fork.+1", "0.12.11-fork.1-beta.1", "0.12.11-beta.1-fork.1",
            "0.12.11-Fork.1", "0.12.11-forks.1",
        ] {
            expect(AppVersion(bad) == nil, "rejects \(bad)")
        }
        // What upstream already rejected is still rejected.
        expect(AppVersion("0.2.0-alpha.1") == nil, "still rejects a channel that never ships")
        expect(AppVersion("0.2.0-beta.4")?.beta == 4, "betas still parse")
    }

    static func ordersForkVersions() {
        expect(version("0.12.11-fork.10") > version("0.12.11-fork.9"), "fork counters compare numerically")
        expect(version("0.12.11-fork.2") > version("0.12.11-fork.1"), "a later fork revision is newer")
        expect(version("0.12.12-fork.1") > version("0.12.11-fork.9"), "a newer base outranks any older revision")
        expect(version("0.12.11-fork.1") > version("0.12.11"), "the first fork revision is newer than its base")
        expect(version("0.12.11") < version("0.12.11-fork.1"), "and the base is older than it")
        expect(version("0.12.11-fork.1") == version("0.12.11-fork.1"), "equal fork versions are equal")
        expect(version("0.12.11-fork.1") != version("0.12.11-fork.2"), "different revisions differ")
        expect(version("0.12.11-fork.3") < version("0.12.12"), "a newer plain base outranks a fork revision")
    }

    static func roundTripsThroughTheCache() {
        let release = AvailableRelease(
            version: version("0.12.11-fork.2"), tag: "v0.12.11-fork.2",
            assetURL: URL(string: "https://example.invalid/Tinycast-Fork-0.12.11-fork.2.zip")!,
            assetSize: 10_202_461, signatureURL: nil, publishedAt: nil)
        guard let encoded = try? JSONEncoder().encode(release),
            let decoded = try? JSONDecoder().decode(AvailableRelease.self, from: encoded)
        else {
            failures += 1
            print("FAIL: a fork release survives the cache file")
            return
        }
        expect(decoded == release, "a fork release survives the cache file")
        expect(decoded.version.fork == 2, "and keeps its fork counter")
        expect(
            (try? JSONDecoder().decode(AppVersion.self, from: Data("\"0.12.11-fork.x\"".utf8))) == nil,
            "a corrupt cached fork version fails to decode")
    }

    // MARK: - ReleaseChannel

    static func derivesTheForkChannel() {
        let fork = ReleaseChannel(bundleID: "com.amryadam.tinycast")
        expect(fork == .fork, "the fork's bundle id is the fork channel")
        expect(fork.updatesItself, "the fork channel updates itself")
        expect(fork.accepts(prerelease: false), "the fork takes releases")
        expect(!fork.accepts(prerelease: true), "the fork never takes a prerelease")

        expect(ReleaseChannel(bundleID: "com.tinycast.app") == .stable, "stable is unchanged")
        expect(ReleaseChannel(bundleID: "com.tinycast.app.beta") == .beta, "beta is unchanged")
        expect(ReleaseChannel(bundleID: "com.tinycast.app.dev") == .development, "dev is unchanged")
        expect(ReleaseChannel(bundleID: "com.amryadam.tinycast.dev") == .development, "the fork's dev id stays local")
        expect(ReleaseChannel(bundleID: nil) == .development, "no bundle id never updates")
        expect(!ReleaseChannel.development.updatesItself, "a local build still does not update itself")
    }

    static func namesTheRepositoryPerChannel() {
        expect(ReleaseFeed.releasesURL(for: .fork).absoluteString
            == "https://api.github.com/repos/amryadam/tinycast/releases?per_page=20",
            "the fork reads the fork's releases")
        for channel in [ReleaseChannel.stable, .beta, .development] {
            expect(ReleaseFeed.releasesURL(for: channel).absoluteString
                == "https://api.github.com/repos/abue-ammar/tinycast/releases?per_page=20",
                "\(channel) still reads upstream's releases")
        }
        expect(ReleaseChannel.fork.repository == "amryadam/tinycast", "the fork's repository")
        expect(ReleaseChannel.stable.repository == "abue-ammar/tinycast", "upstream's repository")
    }

    // MARK: - ReleaseFeed

    static func entry(
        tag: String, prerelease: Bool = false, draft: Bool = false,
        assets: [String]? = nil
    ) -> String {
        let names = assets ?? ["Tinycast-Fork-\(tag).zip", "Tinycast-Fork-\(tag).zip.sha256"]
        let list = names.map {
            """
            {"name":"\($0)","size":2048,"browser_download_url":"https://example.invalid/\($0)"}
            """
        }
        return """
            {"tag_name":"\(tag)","prerelease":\(prerelease),"draft":\(draft),
             "published_at":"2026-11-11T12:00:00Z","assets":[\(list.joined(separator: ","))]}
            """
    }

    static func feed(_ entries: String...) -> Data {
        Data("[\(entries.joined(separator: ","))]".utf8)
    }

    static func offersOnlyForkReleasesToTheFork() {
        let data = feed(
            entry(tag: "v0.12.11-fork.1"), entry(tag: "v0.12.11-fork.2"),
            entry(tag: "v0.12.11-fork.3", draft: true),
            entry(tag: "v0.12.12", assets: ["Tinycast-0.12.12.zip"]),
            entry(tag: "v0.13.0-beta.1", prerelease: true, assets: ["Tinycast-0.13.0-beta.1.zip"]))
        let newest = ReleaseFeed.newest(from: data, channel: .fork, architecture: .appleSilicon)
        expect(newest?.version.description == "0.12.11-fork.2", "the fork gets its newest published release")
        expect(newest?.tag == "v0.12.11-fork.2", "and its tag")
        expect(newest?.assetURL.lastPathComponent == "Tinycast-Fork-v0.12.11-fork.2.zip", "and its zip, not the checksum")
    }

    static func keepsForkReleasesAwayFromOtherChannels() {
        let data = feed(
            entry(tag: "v0.12.11-fork.2"), entry(tag: "v0.12.12", assets: ["Tinycast-0.12.12.zip"]))
        let stable = ReleaseFeed.newest(from: data, channel: .stable, architecture: .appleSilicon)
        expect(stable?.version.description == "0.12.12", "stable takes only the plain release")
        let onlyFork = feed(entry(tag: "v0.12.11-fork.2"))
        expect(
            ReleaseFeed.newest(from: onlyFork, channel: .stable, architecture: .appleSilicon) == nil,
            "stable is never offered a fork release")
        expect(
            ReleaseFeed.newest(from: onlyFork, channel: .beta, architecture: .appleSilicon) == nil,
            "beta is never offered a fork release")
        let plainOnly = feed(entry(tag: "v0.12.12", assets: ["Tinycast-0.12.12.zip"]))
        expect(
            ReleaseFeed.newest(from: plainOnly, channel: .fork, architecture: .appleSilicon) == nil,
            "the fork is never offered a plain upstream release")
    }

    static func skipsWhatIsNotInstallable() {
        let noZip = feed(entry(tag: "v0.12.11-fork.2", assets: ["notes.txt", "x.zip.sha256"]))
        expect(
            ReleaseFeed.newest(from: noZip, channel: .fork, architecture: .appleSilicon) == nil,
            "a fork release with no zip is not offered")
        let prerelease = feed(entry(tag: "v0.12.11-fork.2", prerelease: true))
        expect(
            ReleaseFeed.newest(from: prerelease, channel: .fork, architecture: .appleSilicon) == nil,
            "a fork release flagged as a prerelease is not offered")
        expect(
            ReleaseFeed.newest(from: Data("not json".utf8), channel: .fork, architecture: .appleSilicon) == nil,
            "a broken feed offers nothing")
    }

    static func offersOnlyWhatIsNewer() {
        let data = feed(entry(tag: "v0.12.11-fork.2"))
        let latest = ReleaseFeed.newest(from: data, channel: .fork, architecture: .appleSilicon)
        expect(ReleaseFeed.offer(latest, running: version("0.12.11-fork.1")) != nil, "an older fork build is offered it")
        expect(ReleaseFeed.offer(latest, running: version("0.12.11-fork.2")) == nil, "the same build is not")
        expect(ReleaseFeed.offer(latest, running: version("0.12.11-fork.3")) == nil, "a newer build is not")
        expect(ReleaseFeed.offer(latest, running: version("0.12.11")) != nil, "the base build is offered the first fork revision")
    }

    /// The shape of the fork's real release, from the live API.
    static func readsTheLiveFeedShape() {
        let live = """
            [{"url":"https://api.github.com/repos/amryadam/tinycast/releases/1","tag_name":"v0.12.11-fork.1",
              "name":"Tinycast Fork 0.12.11-fork.1","draft":false,"prerelease":false,
              "created_at":"2026-11-11T12:36:42Z","published_at":"2026-11-11T12:37:10Z",
              "assets":[
               {"name":"Tinycast-Fork-0.12.11-fork.1.zip","size":10202461,
                "browser_download_url":"https://github.com/amryadam/tinycast/releases/download/v0.12.11-fork.1/Tinycast-Fork-0.12.11-fork.1.zip"},
               {"name":"Tinycast-Fork-0.12.11-fork.1.zip.sha256","size":99,
                "browser_download_url":"https://github.com/amryadam/tinycast/releases/download/v0.12.11-fork.1/Tinycast-Fork-0.12.11-fork.1.zip.sha256"}],
              "body":"notes"}]
            """
        let release = ReleaseFeed.newest(from: Data(live.utf8), channel: .fork, architecture: .appleSilicon)
        expect(release?.version.description == "0.12.11-fork.1", "reads the live release")
        expect(release?.assetSize == 10_202_461, "with its real size")
        expect(release?.signatureURL == nil, "and no signature, so the running copy's own requirement is the trust root")
        expect(release?.publishedAt != nil, "and its publish date")
    }
}
