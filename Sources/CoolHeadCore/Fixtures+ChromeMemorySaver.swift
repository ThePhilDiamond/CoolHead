import Foundation

/// Checks for Memory Saver at Maximum (see ChromeMemorySaver): when it's offered, and the write itself, done for real on
/// a made-up Local State in a temporary folder, never Chrome's.
extension Fixture {
    static func chromeMemorySaverChecks(_ now: Date) -> [(String, Bool, String)] {
        var review: [(String, Bool, String)] = []
        typealias S = ChromeMemorySaver.State
        // when it's offered: 8 GB or less; twice this week; once and off; never at Maximum, or within 30 days of Cool Head
        // setting it when the person has lowered it since
        func offer(_ s: S?, count: Int, gb: Double = 16, setDaysAgo: Double? = nil) -> Bool {
            ChromeMemorySaver.shouldOffer(s, week: PressureHistory.Week(count: count, minutes: count * 10, chromeCount: count), memoryGB: gb,
                                          setAt: setDaysAgo.map { now.addingTimeInterval(-$0 * 86400) }, now: now)
        }
        let moderate = S(on: true, level: 0), off = S(on: false, level: 0), max = S(on: true, level: 2)
        let rules = [offer(moderate, count: 0, gb: 8), offer(moderate, count: 2), offer(off, count: 1), offer(moderate, count: 1), offer(moderate, count: 0),
                     offer(max, count: 3, gb: 8), offer(moderate, count: 3, setDaysAgo: 10), offer(moderate, count: 3, setDaysAgo: 40)]
        review.append(("saver-offered-when", rules == [true, true, true, false, false, false, false, true],
                       "8 GB, twice, once and off, once and on, never, already Maximum, lowered 10 days after Cool Head set it, 40 days: \(rules)"))

        // the option on Chrome's card, and none once it's at Maximum
        let tight = mac("warning", swappedMB: 600)
        func card(_ s: S?, offerIt: Bool) -> Card {
            MemoryAdvice.card(chromeHeavy, mac: tight, now: now, context: MemoryContext(slowed: true, memorySaver: s, offerSaverMaximum: offerIt), tabMemoryOn: false)
        }
        let offered = card(moderate, offerIt: true).fixes.first { $0.id == "saver-max" }
        let plain = card(moderate, offerIt: false).fixes.map(\.id)
        let atMax = card(max, offerIt: false).fixes.map(\.id)
        review.append(("saver-option", offered?.kind == .restartBrowser("/Applications/Google Chrome.app") && offered?.recommended == false
                       && offered?.consequence.contains("your own setting") == true && plain.contains("saver") && !plain.contains("saver-max")
                       && !atMax.contains("saver") && !atMax.contains("saver-max"), offered?.consequence ?? "not offered"))

        // the write: only the two values change, the file keeps its mode, and not while a Chrome holds the folder
        let dir = NSTemporaryDirectory() + "coolhead-selftest-saver-\(getpid())"
        try? FileManager.default.removeItem(atPath: dir)
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let path = dir + "/Local State"
        let before = #"{"browser":{"hovercard":{"memory_usage_enabled":true},"enabled_labs_experiments":["a@1"]},"performance_tuning":{"high_efficiency_mode":{"state":2,"aggressiveness":0},"battery_saver_mode":{"state":1}},"profile":{"info_cache":{"Default":{"name":"Person 1","active_time":1763700000.123456}}},"big":9007199254740993,"text":"café \/ \"q\""}"#
        func reset() {
            FileManager.default.createFile(atPath: path, contents: Data(before.utf8), attributes: [.posixPermissions: 0o600])
            try? FileManager.default.removeItem(atPath: dir + "/SingletonLock")
        }
        reset()
        let wrote = ChromeMemorySaver.setMaximum(path: path)
        let after = FileManager.default.contents(atPath: path).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        var expected = (try? JSONSerialization.jsonObject(with: Data(before.utf8))) as? [String: Any] ?? [:]
        var tuning = expected["performance_tuning"] as? [String: Any] ?? [:], mode = tuning["high_efficiency_mode"] as? [String: Any] ?? [:]
        mode["aggressiveness"] = 2; tuning["high_efficiency_mode"] = mode; expected["performance_tuning"] = tuning
        let same = after.map { ($0 as NSDictionary).isEqual(to: expected) } ?? false
        let perms = (try? FileManager.default.attributesOfItem(atPath: path))?[.posixPermissions] as? NSNumber
        let leftovers = ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []).filter { $0 != "Local State" }
        // a live Chrome holds the folder: this process stands in for it, on this Mac
        var host = [CChar](repeating: 0, count: 256); _ = gethostname(&host, host.count)
        reset(); try? FileManager.default.createSymbolicLink(atPath: dir + "/SingletonLock", withDestinationPath: "\(String(cString: host))-\(getpid())")
        let live = ChromeMemorySaver.setMaximum(path: path)
        let untouched = FileManager.default.contents(atPath: path) == Data(before.utf8)
        // a lock left by a process that has ended is stale; one from another Mac isn't
        reset(); try? FileManager.default.createSymbolicLink(atPath: dir + "/SingletonLock", withDestinationPath: "\(String(cString: host))-99999")
        let stale = Proc.bsd(99999) == nil ? ChromeMemorySaver.setMaximum(path: path) : .set
        reset(); try? FileManager.default.createSymbolicLink(atPath: dir + "/SingletonLock", withDestinationPath: "another-mac.local-123")
        let elsewhere = ChromeMemorySaver.setMaximum(path: path)
        try? FileManager.default.removeItem(atPath: dir)
        review.append(("saver-write", wrote == .set && same && perms?.intValue == 0o600 && leftovers.isEmpty && live == .chromeOpen && untouched
                       && stale == .set && elsewhere == .chromeOpen,
                       "set \(wrote), only the two values changed \(same), mode \(String(perms?.intValue ?? 0, radix: 8)), leftovers \(leftovers); live lock \(live), stale \(stale), other Mac \(elsewhere)"))
        return review
    }

    static func chromeMemorySaverSamples(_ now: Date) -> [(String, Card)] {
        [("memory-chrome-saver-max", MemoryAdvice.card(chromeHeavy, mac: mac("warning", swappedMB: 600), now: now,
                                                       context: MemoryContext(slowed: true, week: PressureHistory.Week(count: 3, minutes: 40, chromeCount: 2),
                                                                              memorySaver: ChromeMemorySaver.State(on: true, level: 0), offerSaverMaximum: true),
                                                       tabMemoryOn: false))]
    }
}
