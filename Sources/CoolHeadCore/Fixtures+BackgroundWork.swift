import Foundation

/// Checks for reading macOS's own background work (see BackgroundWork, research rules 13, 16 and 17), and the example
/// cards `coolhead wording` shows for it.
extension Fixture {
    static let spotlightPath = "/System/Library/Frameworks/CoreServices.framework/Frameworks/Metadata.framework/Support/mds_stores"
    static let dasdPath = "/usr/libexec/dasd"

    static func macOSProcess(_ name: String, _ path: String, start: Date, cores: Double = 1.5) -> Evidence {
        catalogueProcess(name, path, mine: false, start: start, cores: cores)
    }

    /// The example cards (see Wording).
    static func backgroundWorkSamples(_ now: Date) -> [(String, Card)] {
        let day: TimeInterval = 24 * 3600
        let mds = macOSProcess("mds_stores", spotlightPath, start: now.addingTimeInterval(-3 * day))
        let dasd = macOSProcess("dasd", dasdPath, start: now.addingTimeInterval(-3 * day))
        let update = BackgroundWork.Update(version: "27.2", date: now.addingTimeInterval(-2 * day))
        func make(_ e: Evidence, busy: TimeInterval, _ r: BackgroundWork.Reading) -> Card {
            Card.make(e, now: now, busySince: now.addingTimeInterval(-busy), background: r)
        }
        return [("spotlight-low-priority", make(mds, busy: 40 * 60, .init(cool: true))),
                ("spotlight-after-update", make(mds, busy: 9 * 3600, .init(update: update))),
                ("stuck-macos-service", make(dasd, busy: 30 * 3600, .init(stuck: .init(since: now.addingTimeInterval(-30 * 3600), afterRestart: false)))),
                ("stuck-after-restart", make(dasd, busy: 2 * 3600, .init(stuck: .init(since: now.addingTimeInterval(-3 * day), afterRestart: true))))]
    }

    static func backgroundWorkChecks(_ now: Date) -> [(String, Bool, String)] {
        var review: [(String, Bool, String)] = []
        let day: TimeInterval = 24 * 3600
        typealias T = BackgroundWork.Thread

        // rule 13: priority from ps -M, and "runs cool" only when nearly all busy CPU is at background priority
        let text = """
        USER          PID   TT   %CPU STAT PRI     STIME     UTIME COMMAND
        _mds_stores   560   ??   82.0 R    31T   0:00.07   0:00.07 /System/Library/Frameworks/CoreServices.framework/mds_stores 31T
                      560         0.0 S    31T   0:00.00   0:00.00         31T
                      560        80.5 R     4T   0:00.08   0:00.59          4T
                      560         1.5 S     4T   0:00.04   0:00.39          4T
        """
        let parsed = BackgroundWork.parseThreads(text)
        let cool = BackgroundWork.cool
        let r1 = parsed.map(\.priority) == [31, 31, 4, 4] && parsed.map(\.cpu) == [82.0, 0.0, 80.5, 1.5]
            && cool(Array(parsed.dropFirst()), 4) == true
            && cool([T(cpu: 60, priority: 4), T(cpu: 40, priority: 31)], 4) == false
            && cool([T(cpu: 1, priority: 4)], 4) == nil
            && cool([T(cpu: 50, priority: 4), T(cpu: 50, priority: 4)], 2) == false        // two E cores clock up
            && cool([T(cpu: 50, priority: 4), T(cpu: 50, priority: 4)], 4) == true
        review.append(("background-priority-read", r1, "threads \(parsed.map { "\($0.priority) at \($0.cpu)%" }); 90% rule and two-E-core exception"))

        // rule 17: the last full macOS update, not security responses or other software
        func entry(_ name: String, _ version: String, _ daysAgo: Double) -> [String: Any] {
            ["displayName": name, "displayVersion": version, "date": now.addingTimeInterval(-daysAgo * day), "processName": "softwareupdated"]
        }
        let history = [entry("macOS 26.6.2", "26.6.2", 60), entry("macOS 27.2", "27.2", 3), entry("macOS Rapid Security Response 27.2 (a)", "27.2 (a)", 1),
                       entry("macOS Background Security Improvement 27.2.1", "27.2.1", 0.5), entry("Safari 27.2", "27.2", 0.2), entry("XProtectPlistConfigData", "5321", 0.1)]
        let last = BackgroundWork.lastUpdate(history: history)
        let r2 = last?.version == "27.2" && BackgroundWork.ago(now.addingTimeInterval(-2 * day - 60), now: now) == "2 days ago"
            && BackgroundWork.ago(now.addingTimeInterval(-30 * 3600), now: now) == "yesterday"
            && BackgroundWork.ago(now.addingTimeInterval(-5 * 3600), now: now) == "5 hours ago"
        review.append(("background-last-update", r2, "last full update \(last?.version ?? "none")"))

        // the card after an update: normal, saying when; not "longer than usual" within a week
        let mds = macOSProcess("mds_stores", spotlightPath, start: now.addingTimeInterval(-3 * day))
        let update = BackgroundWork.Update(version: "27.2", date: now.addingTimeInterval(-2 * day))
        let after = Card.make(mds, now: now, busySince: now.addingTimeInterval(-9 * 3600), background: .init(update: update))
        let without = Card.make(mds, now: now, busySince: now.addingTimeInterval(-9 * 3600))
        let lowCard = Card.make(mds, now: now, busySince: now.addingTimeInterval(-40 * 60), background: .init(cool: true))
        let hotCard = Card.make(mds, now: now, busySince: now.addingTimeInterval(-40 * 60), background: .init(cool: false))
        let r3 = after.state == .working && after.headline == "Spotlight is indexing your files. That's normal after an update."
            && after.explanation.hasPrefix("You updated to macOS 27.2 2 days ago; this usually goes on for hours or days after an update.")
            && without.state == .unknown && without.headline.contains("longer than usual")
            && lowCard.explanation.contains("on the chip's efficiency cores, so it uses little power") && !hotCard.explanation.contains("efficiency cores")
        review.append(("background-card-after-update", r3, after.headline + " " + after.explanation + " | " + lowCard.explanation))

        // rule 16: busy a day is stuck; a record from just before this boot carries over, and says a restart didn't help
        let boot = now.addingTimeInterval(-2 * 3600)
        var records: [String: BackgroundWork.Record] = [:]
        let fresh = BackgroundWork.note("dasd", busySince: now.addingTimeInterval(-2 * 3600), now: now, boot: boot, records: &records)
        records = [:]
        let day1 = BackgroundWork.note("dasd", busySince: now.addingTimeInterval(-25 * 3600), now: now, boot: now.addingTimeInterval(-30 * 3600), records: &records)
        records = ["dasd": .init(since: now.addingTimeInterval(-3 * day), last: boot.addingTimeInterval(-600), boot: now.addingTimeInterval(-4 * day), restarted: false)]
        let carried = BackgroundWork.note("dasd", busySince: now.addingTimeInterval(-3600), now: now, boot: boot, records: &records)
        let kept = records["dasd"]?.restarted == true
        let again = BackgroundWork.note("dasd", busySince: now.addingTimeInterval(-3600), now: now.addingTimeInterval(60), boot: boot, records: &records)
        records = ["dasd": .init(since: now.addingTimeInterval(-3 * day), last: boot.addingTimeInterval(-5 * 3600), boot: now.addingTimeInterval(-4 * day), restarted: false),
                   "old": .init(since: now.addingTimeInterval(-9 * day), last: now.addingTimeInterval(-3 * day), boot: now.addingTimeInterval(-9 * day), restarted: false)]
        let quietBefore = BackgroundWork.note("dasd", busySince: now.addingTimeInterval(-3600), now: now, boot: boot, records: &records)
        let r4 = fresh == nil && day1 == .init(since: now.addingTimeInterval(-25 * 3600), afterRestart: false)
            && carried?.afterRestart == true && carried?.since == now.addingTimeInterval(-3 * day) && kept && again?.afterRestart == true
            && quietBefore == nil && records["old"] == nil
        review.append(("background-stuck-across-restart", r4, "fresh \(String(describing: fresh)); a day \(String(describing: day1)); carried over a restart \(String(describing: carried)); quiet before the restart \(String(describing: quietBefore))"))

        // the stuck cards: a restart first; after a restart, a macOS update or telling Apple (never an action on macOS's own
        // processes); not for work expected after a recent update; not for anything outside macOS's folders
        let dasd = macOSProcess("dasd", dasdPath, start: now.addingTimeInterval(-3 * day))
        let stuck = BackgroundWork.Stuck(since: now.addingTimeInterval(-30 * 3600), afterRestart: false)
        let stuckRestart = BackgroundWork.Stuck(since: now.addingTimeInterval(-3 * day), afterRestart: true)
        let first = Card.make(dasd, now: now, busySince: now.addingTimeInterval(-30 * 3600), background: .init(stuck: stuck))
        let second = Card.make(dasd, now: now, busySince: now.addingTimeInterval(-3600), background: .init(stuck: stuckRestart))
        let spotlightUpdating = Card.make(mds, now: now, busySince: now.addingTimeInterval(-30 * 3600), background: .init(update: update, stuck: stuck))
        let notMacOS = BackgroundWork.stuckCard(catalogueProcess("dasd", "/Users/x/dasd", start: now, cores: 1), .init(stuck: stuck), now: now)
        let words = { (c: Card) in (c.headline + " " + c.explanation).split(separator: " ").count }
        let r5 = first.headline == "dasd, part of macOS, seems stuck: it's been busy for over a day." && first.recommended?.id == "restart"
            && second.headline == "dasd, part of macOS, is stuck: a restart didn't clear it." && second.recommended?.id == "update"
            && second.explanation.contains("busy for 3 days") && second.fixes.contains { $0.id == "feedback" }
            && ![first, second].contains { c in c.fixes.contains { $0.interrupts } }
            && [first, second].allSatisfy { words($0) <= 45 && $0.explanation.lowercased().contains("we can't be certain") }
            && spotlightUpdating.headline.contains("That's normal after an update") && notMacOS == nil
        review.append(("background-stuck-card", r5, first.headline + " / " + second.headline + " " + second.explanation))

        // on this Mac, for real: a busy loop of Cool Head's own, run at background priority with taskpolicy, reads as
        // running cool through ps; this Mac's last update reads from its install history
        var live = "taskpolicy couldn't start"
        var r6 = false
        if let p = Fixture.busyLoop(background: true) {
            // read every second, for up to 10 seconds, until it has used enough of a busy Mac to judge (see RunCooler's check)
            var threads: [BackgroundWork.Thread] = [], c: Bool?
            for _ in 0..<10 {
                Thread.sleep(forTimeInterval: 1)
                threads = BackgroundWork.threads(p.processIdentifier)
                c = BackgroundWork.cool(threads, efficiencyCores: 4)
                if c != nil { break }
            }
            Fixture.end(p)
            r6 = c == true
            live = "threads \(threads.map { "\($0.priority) at \($0.cpu)%" }): cool \(String(describing: c))"
        }
        let mine = BackgroundWork.lastUpdate(now: now)
        review.append(("background-priority-this-mac", r6, live + "; last update here: \(mine.map { "\($0.version), \(BackgroundWork.ago($0.date, now: now))" } ?? "none read")"))
        return review
    }
}
