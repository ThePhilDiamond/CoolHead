import Foundation

/// Checks for telling a leak from work (see Leaks, research rule 15), and the example card `coolhead wording` shows.
extension Fixture {
    static let pagesBundle = "/Applications/Pages.app"

    static func leakSamples(_ now: Date, hours: Double = 3, from: Double = 1.2, to: Double = 9.1, windows: [Int]? = nil) -> [Leaks.Sample] {
        let n = Int(hours * 12)
        return (0...n).map { i in
            let f = Double(i) / Double(n)
            return Leaks.Sample(at: now.addingTimeInterval(-hours * 3600 * (1 - f)), bytes: UInt64((from + (to - from) * f) * 1_000_000_000),
                                windows: windows.map { $0[min(i, $0.count - 1)] } ?? 3)
        }
    }

    static func leakTightMac() -> MacState {
        var s = MacState(); s.memoryPressure = "warning"; s.swapUsedMB = 2500; s.swapTotalMB = 4096
        return s
    }

    /// The example card (see Wording).
    static func leakSamplesForWording(_ now: Date) -> [(String, Card)] {
        let pages = MemGroup(key: pagesBundle, name: "Pages", kind: .app, bundle: pagesBundle, bytes: 9_100_000_000, count: 1)
        let slack = MemGroup(key: "/Applications/Slack.app", name: "Slack", kind: .app, bundle: "/Applications/Slack.app", bytes: 1_200_000_000, count: 5)
        return [("memory-leaking-app", MemoryAdvice.card([pages, slack], mac: leakTightMac(), now: now, leak: Leaks.judge(leakSamples(now))))]
    }

    static func leakChecks(_ now: Date) -> [(String, Bool, String)] {
        var review: [(String, Bool, String)] = []
        let j = Leaks.judge

        // a leak: steady growth with the same windows; not one: windows changed, it fell back, too short, too little, not doubled
        let steady = j(leakSamples(now))
        var dip = leakSamples(now); dip[10] = Leaks.Sample(at: dip[10].at, bytes: dip[9].bytes / 2, windows: 3)
        let r1 = steady == .init(from: 1_200_000_000, to: 9_100_000_000, since: now.addingTimeInterval(-3 * 3600))
            && j(leakSamples(now, windows: [3, 3, 3, 3, 4])) == nil && j(dip) == nil
            && j(leakSamples(now, hours: 1.5)) == nil && j(leakSamples(now, from: 1.0, to: 2.5)) == nil
            && j(leakSamples(now, from: 6.0, to: 8.5)) == nil && j(Array(leakSamples(now).prefix(2))) == nil
        review.append(("leak-judged", r1, "steady 1.2 to 9.1 GB over 3 hours: \(steady != nil); windows changed, a dip, 90 minutes, 1.5 GB, not doubled: none"))

        // the tracker: a reading every 5 minutes, kept 6 hours; an app that reopened starts afresh
        let t = Leaks.Tracker()
        let start = now.addingTimeInterval(-4 * 3600)
        for i in 0...48 {
            let at = start.addingTimeInterval(Double(i) * 300)
            let gb = 1.0 + Double(i) * 0.15
            t.note([(pagesBundle, 501, UInt64(gb * 1_000_000_000)), ("/Applications/Notes.app", 502, 400_000_000)], windows: { [501: 2, 502: 1] }, now: at)
        }
        let tracked = t.leak(pagesBundle), flat = t.leak("/Applications/Notes.app")
        let early = !t.due(start.addingTimeInterval(48 * 300 + 60)) && t.due(start.addingTimeInterval(49 * 300))
        t.note([(pagesBundle, 777, 8_000_000_000)], windows: { [777: 2] }, now: start.addingTimeInterval(49 * 300))
        let reset = t.leak(pagesBundle) == nil
        review.append(("leak-tracked", tracked != nil && flat == nil && early && reset,
                       "Pages \(tracked.map { "\(Fmt.bytes($0.from)) to \(Fmt.bytes($0.to))" } ?? "none"); Notes none \(flat == nil); every 5 minutes \(early); reopened starts afresh \(reset)"))

        // the memory card: the leak said, with quitting and reopening as the advice; Caution only where quitting loses work;
        // nothing for a browser (it has its own restart) or without a leak
        let pages = MemGroup(key: pagesBundle, name: "Pages", kind: .app, bundle: pagesBundle, bytes: 9_100_000_000, count: 1)
        let claude = MemGroup(key: "/Applications/Claude.app", name: "Claude", kind: .app, bundle: "/Applications/Claude.app", bytes: 9_100_000_000, count: 4)
        let chrome = MemGroup(key: "/Applications/Google Chrome.app", name: "Google Chrome", kind: .browser, bundle: "/Applications/Google Chrome.app", bytes: 9_100_000_000, count: 40)
        let card = MemoryAdvice.card([pages], mac: leakTightMac(), now: now, leak: steady)
        let claudeCard = MemoryAdvice.card([claude], mac: leakTightMac(), now: now, leak: steady)
        let chromeCard = MemoryAdvice.card([chrome], mac: leakTightMac(), now: now, leak: steady)
        let none = MemoryAdvice.card([pages], mac: leakTightMac(), now: now)
        let r = card.recommended
        let r3 = card.headline == "Memory is tight: Pages is using 8.5 GB, far more than it needs."
            && card.explanation == "With the same windows open, it used 1.1 GB three hours ago: probably a leak. Save your work, then quit and reopen it."
            && r?.consequence.hasPrefix("Save your work first.") == true && !card.fixes.contains { $0.id == "quit" }
            && (card.headline + " " + card.explanation).split(separator: " ").count <= 40
            && r?.id == "reopen" && r?.kind == .restartApp(pagesBundle) && r?.caution == false && r?.title == "Quit and reopen Pages"
            && claudeCard.recommended?.caution == true && !chromeCard.fixes.contains { $0.id == "reopen" } && !none.fixes.contains { $0.id == "reopen" }
        let parts = "[claude caution \(claudeCard.recommended?.caution == true) \(claudeCard.recommended?.id ?? "-"); chrome \(!chromeCard.fixes.contains { $0.id == "reopen" }); none \(!none.fixes.contains { $0.id == "reopen" }); words \((card.headline + " " + card.explanation).split(separator: " ").count)] "
        review.append(("leak-card", r3, parts + card.headline + " " + card.explanation + " Options: \(card.fixes.map(\.id)); \(r?.consequence ?? "")"))

        // on this Mac: the window list can be read without a permission
        let counts = Leaks.windowCounts()
        review.append(("leak-windows-this-mac", !counts.isEmpty, "windows counted for \(counts.count) processes"))
        return review
    }
}
