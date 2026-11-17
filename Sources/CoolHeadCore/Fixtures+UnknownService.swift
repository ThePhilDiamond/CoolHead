import Foundation

/// Checks for the reading of a macOS service nobody catalogued (see BackgroundWork.unknownCard, research rule 6), and
/// the example cards `coolhead wording` shows.
extension Fixture {
    static let unknownServicePath = "/System/Library/PrivateFrameworks/SpotlightKnowledge.framework/Versions/A/Support/spotlightknowledged"

    static func unknownService(cores: Double = 1.2, mine: Bool = true, fromShell: Bool = false, path: String = unknownServicePath, now: Date) -> Evidence {
        let start = now.addingTimeInterval(-3 * 3600)
        let parents = fromShell ? [Evidence.Ancestor(pid: 4000, name: "zsh", path: "/bin/zsh", args: ["-zsh"])]
            : [Evidence.Ancestor(pid: 1, name: "launchd", path: "/sbin/launchd", args: [])]
        return Evidence(pid: 99999, name: (path as NSString).lastPathComponent, path: path, args: [path], cwd: nil, start: start, mine: mine,
                        coresNow: cores, coresAverage: cores, performanceShare: nil, memoryBytes: 300_000_000, ancestors: parents, writing: [],
                        locks: [], progress: nil, bytesWrittenDuringSample: 0, lastOutput: nil, lastLine: nil, savesAsItGoes: false, workStart: start)
    }

    /// The example cards (see Wording).
    static func unknownServiceSamples(_ now: Date) -> [(String, Card)] {
        let e = unknownService(now: now)
        return [("macos-unknown-low-priority", Card.make(e, now: now, busySince: now.addingTimeInterval(-40 * 60), background: .init(cool: true))),
                ("macos-unknown-normal-priority", Card.make(e, now: now, busySince: now.addingTimeInterval(-2 * 3600), background: .init(cool: false)))]
    }

    static func unknownServiceChecks(_ now: Date) -> [(String, Bool, String)] {
        var review: [(String, Bool, String)] = []
        func card(_ e: Evidence, _ r: BackgroundWork.Reading?, busy: TimeInterval) -> Card {
            Card.make(e, now: now, busySince: now.addingTimeInterval(-busy), background: r)
        }
        func words(_ c: Card) -> Int { (c.headline + " " + c.explanation).split(separator: " ").count }

        // which processes get the reading: macOS's services started by launchd (or whose parents can't be read), not a
        // macOS command someone ran from a shell, and not a catalogued service
        let r1 = BackgroundWork.isService(unknownService(now: now)) && !BackgroundWork.isService(unknownService(fromShell: true, path: "/usr/bin/zip", now: now))
            && !BackgroundWork.isService(Evidence.sample(name: "render", path: "/Users/x/bin/render", start: now, cores: 2))
        let catalogued = card(Fixture.catalogueProcess("mds_stores", "/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/Metadata.framework/Versions/A/Support/mds_stores",
                                                       start: now.addingTimeInterval(-3600), cores: 1.2), nil, busy: 1800)
        let zip = card(unknownService(fromShell: true, path: "/usr/bin/zip", now: now), nil, busy: 1800)
        let r1b = r1 && !catalogued.explanation.contains("We don't know") && !zip.headline.contains("part of macOS")
        review.append(("unknown-service-which", r1b, "service true; zip from a shell false; your own tool false | catalogued: \(catalogued.headline) | zip: \(zip.headline)"))

        // the card: part of macOS, not known by name; at low priority it says it uses little power; nothing to press but
        // Look it up (waiting is the card's clock), never Stop or Run it cooler; amber only after an hour at normal priority; quiet when quiet
        let e = unknownService(now: now)
        let low = card(e, .init(cool: true), busy: 2 * 3600)
        let normal = card(e, .init(cool: false), busy: 2 * 3600)
        let short = card(e, .init(cool: false), busy: 20 * 60)
        let unread = card(e, nil, busy: 20 * 60)
        let root = card(unknownService(mine: false, now: now), nil, busy: 20 * 60)
        let rootLong = card(unknownService(mine: false, now: now), .init(cool: false), busy: 2 * 3600)
        let quiet = card(unknownService(cores: 0.05, now: now), nil, busy: 20 * 60)
        let noAction = [low, normal, short, unread, root].allSatisfy { c in !c.fixes.contains { $0.kind == .stop || $0.kind == .cooler } }
        let r2 = low.headline == "spotlightknowledged is part of macOS, working in the background."
            && low.explanation.hasPrefix("We don't know this one by name. It runs at low priority") && low.state == .working
            && normal.explanation.hasSuffix("at normal priority. If it runs for a day, we'll say what to try.") && normal.state == .unknown && short.state == .working
            && !short.explanation.contains("a day")
            && unread.explanation == "We don't know this one by name. It has used about 1 core for 20 minutes."
            && root.explanation.hasSuffix("stopping it would only start it again.")
            && low.recommended == nil && low.fixes.map(\.id) == ["lookup"] && normal.recommended == nil && noAction && quiet.state == .quiet
            && [low, normal, root, rootLong].allSatisfy { words($0) <= 40 }
        review.append(("unknown-service-card", r2, "\(low.headline) \(low.explanation) | normal: \(normal.explanation) (\(normal.state)) | not read: \(unread.explanation) | quiet: \(quiet.headline)"))

        // a day or more busy is still the stuck card's (rule 16)
        let stuck = Card.make(e, now: now, busySince: now.addingTimeInterval(-26 * 3600),
                              background: .init(cool: false, stuck: .init(since: now.addingTimeInterval(-26 * 3600), afterRestart: false)))
        review.append(("unknown-service-stuck-wins", stuck.headline.contains("seems stuck"), stuck.headline))
        return review
    }
}
