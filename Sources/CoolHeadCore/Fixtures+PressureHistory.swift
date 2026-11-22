import Foundation

/// Checks for the memory history and the gate (see PressureHistory and MemoryGate): a record kept on this Mac only, for one
/// stated purpose.
extension Fixture {
    static func mac(_ pressure: String, swappedMB: Double?) -> MacState {
        var s = MacState(); s.memoryPressure = pressure; s.swapUsedMB = 2000; s.swapTotalMB = 3072; s.swappedOutMB = swappedMB
        return s
    }
    static let chromeHeavy = [MemGroup(key: "c", name: "Google Chrome", kind: .browser, bundle: "/Applications/Google Chrome.app", bytes: 5_500_000_000, count: 41)]

    static func pressureHistoryChecks(_ now: Date) -> [(String, Bool, String)] {
        var review: [(String, Bool, String)] = []
        typealias E = PressureHistory.Episode
        let t0 = now.addingTimeInterval(-3600)
        func at(_ s: Double) -> Date { t0.addingTimeInterval(s) }

        // the gate: macOS has said so for a minute, and memory is being moved to disk now
        let gate = [MemoryGate.slowed(mac("warning", swappedMB: 400), tightSince: at(0), now: at(30)),
                    MemoryGate.slowed(mac("warning", swappedMB: 40), tightSince: at(0), now: at(90)),
                    MemoryGate.slowed(mac("warning", swappedMB: 400), tightSince: at(0), now: at(90)),
                    MemoryGate.slowed(mac("critical", swappedMB: 400), tightSince: at(0), now: at(90)),
                    MemoryGate.slowed(mac("normal", swappedMB: 1400), tightSince: nil, now: at(90)),
                    MemoryGate.slowed(mac("warning", swappedMB: nil), tightSince: at(0), now: at(90))]
        review.append(("memory-gate", gate == [false, false, true, true, false, false],
                       "30 s with 400 MB moved, 90 s with 40 MB, 90 s with 400 MB, critical, normal with 1.4 GB, not yet measured: \(gate)"))

        // spells: a short one isn't kept; two close together are one; the peak rises; it ends after 2 minutes fine
        var short: [E] = []
        for s in stride(from: 0.0, through: 40, by: 10) { PressureHistory.note(&short, tight: .warning, slowed: false, top: .chrome, swapOutPages: 100, now: at(s)) }
        for s in stride(from: 50.0, through: 200, by: 10) { PressureHistory.note(&short, tight: nil, slowed: false, top: nil, swapOutPages: 100, now: at(s)) }
        var list: [E] = []
        var saves = 0
        func tick(_ s: Double, _ level: E.Level?, slowed: Bool = false, pages: UInt64 = 1000) {
            if PressureHistory.note(&list, tight: level, slowed: slowed, top: level == nil ? nil : .chrome, swapOutPages: pages, pageSize: 16384, now: at(s)) { saves += 1 }
        }
        for s in stride(from: 0.0, to: 300, by: 10) { tick(s, .warning, slowed: s >= 90, pages: 1000 + UInt64(s)) }
        for s in stride(from: 300.0, to: 420, by: 10) { tick(s, nil) }       // fine for 2 minutes: ends at 290
        for s in stride(from: 480.0, to: 600, by: 10) { tick(s, .critical, slowed: true, pages: 1600) }   // 3 minutes later: continues it
        let one = list.count == 1 ? list[0] : nil
        for s in stride(from: 600.0, to: 740, by: 10) { tick(s, nil) }
        let ended = list.first?.end == at(590)
        review.append(("pressure-episodes", short.isEmpty && one?.peak == .critical && one?.slowed == true && one?.top == .chrome
                       && one?.movedMB == Double(600) * 16384 / 1_048_576 && ended && saves >= 4 && saves <= 8,
                       "short spell kept \(!short.isEmpty); one spell \(one != nil), peak \(one.map { "\($0.peak)" } ?? "-"), moved \(one?.movedMB ?? 0) MB; ended at 590 \(ended); saved \(saves) times"))

        // a spell left open by a crash ends when it was last seen; old ones go after 30 days, and at most 500 are kept
        var crashed = [E(start: at(0), last: at(200), end: nil, peak: .warning, slowed: true, top: .app, startPages: nil)]
        PressureHistory.closeOpen(&crashed, now: at(5000))
        func old(hoursAgo: Double) -> E {
            let start = now.addingTimeInterval(-hoursAgo * 3600 - 600), end = now.addingTimeInterval(-hoursAgo * 3600 - 300)
            return E(start: start, last: end, end: end, peak: .warning, slowed: true, top: .app, startPages: nil)
        }
        var many: [E] = [old(hoursAgo: 40 * 24)]
        for i in stride(from: 519, through: 0, by: -1) { many.append(old(hoursAgo: Double(i))) }
        PressureHistory.prune(&many, now: now)
        review.append(("pressure-retention", crashed.first?.end == at(200) && many.count == PressureHistory.maxEpisodes
                       && many.allSatisfy { now.timeIntervalSince($0.start) < 30 * 24 * 3600 },
                       "crashed spell ended at its last sighting \(crashed.first?.end == at(200)); kept \(many.count), none older than 30 days"))

        // the week line: only spells that slowed the Mac, in the last 7 days
        func ep(_ daysAgo: Double, _ minutes: Double, _ top: E.Top, slowed: Bool = true) -> E {
            let s = now.addingTimeInterval(-daysAgo * 24 * 3600)
            return E(start: s, last: s.addingTimeInterval(minutes * 60), end: s.addingTimeInterval(minutes * 60), peak: .warning, slowed: slowed, top: top, startPages: nil)
        }
        let w3 = PressureHistory.week(PressureHistory.sample(now: now), now: now)
        let w1 = PressureHistory.week([ep(2, 12.4, .chrome), ep(3, 30, .chrome, slowed: false), ep(9, 50, .chrome)], now: now)
        let w0 = PressureHistory.week([], now: now)
        let lines = [PressureHistory.weekLine(w3), PressureHistory.chromeLine(w3) ?? "-", PressureHistory.weekLine(w1), PressureHistory.chromeLine(w1) ?? "-",
                     PressureHistory.weekLine(w0), PressureHistory.chromeLine(w0) ?? "-"]
        review.append(("pressure-week-line", lines == ["Memory slowed your Mac 3 times this week, about 40 minutes in all.", "Chrome was using the most memory in 2 of them.",
                                                       "Memory slowed your Mac once this week, for about 12 minutes.", "Chrome was using the most memory.",
                                                       "Memory hasn't slowed your Mac this week.", "-"], lines.joined(separator: " | ")))

        // saved in Cool Head's preferences and read back, with no names in it
        let suite = "coolhead-selftest-pressure"
        let d = UserDefaults(suiteName: suite)!
        PressureHistory.save(PressureHistory.sample(now: now), d, now: now)
        let back = PressureHistory.load(d)
        let json = d.data(forKey: PressureHistory.key).map { String(decoding: $0, as: UTF8.self) } ?? ""
        d.removePersistentDomain(forName: suite)
        review.append(("pressure-saved", back == PressureHistory.sample(now: now) && !json.contains("Google") && !json.contains("Chrome") && json.contains("\"chrome\""),
                       "\(back.count) spells read back; \(json.count) characters, no app names"))

        // the calm card: Chrome using the most, macOS says warning, nothing moved to disk; never at critical, never when
        // memory is moving to disk, and today's card when the gate isn't judged (the selftests' other cards)
        let calm = MemoryAdvice.card(chromeHeavy, mac: mac("warning", swappedMB: 30), now: now, context: MemoryContext(slowed: false), tabMemoryOn: false)
        let critical = MemoryAdvice.card(chromeHeavy, mac: mac("critical", swappedMB: 30), now: now, context: MemoryContext(slowed: false), tabMemoryOn: false)
        let early = MemoryAdvice.card(chromeHeavy, mac: mac("warning", swappedMB: 400), now: now, context: MemoryContext(slowed: false), tabMemoryOn: false)
        let unjudged = MemoryAdvice.card(chromeHeavy, mac: mac("warning", swappedMB: 30), now: now, tabMemoryOn: false)
        let slack = MemoryAdvice.card([MemGroup(key: "s", name: "Slack", kind: .app, bundle: "/Applications/Slack.app", bytes: 3_000_000_000, count: 5)],
                                      mac: mac("warning", swappedMB: 30), now: now, context: MemoryContext(slowed: false))
        review.append(("memory-chrome-calm", calm.state == .working && calm.fixes.isEmpty && calm.headline == "Memory is busy, but your Mac is keeping up."
                       && critical.state != .working && !critical.fixes.isEmpty && early.state != .working && unjudged.state != .working && slack.state != .working,
                       calm.headline + " " + calm.explanation))

        // the week on Chrome's card: from the second time this week
        let twice = MemoryAdvice.card(chromeHeavy, mac: mac("warning", swappedMB: 600), now: now,
                                      context: MemoryContext(slowed: true, week: PressureHistory.Week(count: 3, minutes: 40, chromeCount: 2)), tabMemoryOn: false)
        let once = MemoryAdvice.card(chromeHeavy, mac: mac("warning", swappedMB: 600), now: now,
                                     context: MemoryContext(slowed: true, week: PressureHistory.Week(count: 1, minutes: 12, chromeCount: 1)), tabMemoryOn: false)
        review.append(("memory-chrome-week", twice.explanation.hasSuffix("It's slowed your Mac 3 times this week, about 40 minutes in all, so it's likely to happen again while Chrome holds this much.")
                       && !once.explanation.contains("this week"), twice.explanation))
        return review
    }

    static func pressureHistorySamples(_ now: Date) -> [(String, Card)] {
        [("memory-chrome-calm", MemoryAdvice.card(chromeHeavy, mac: mac("warning", swappedMB: 30), now: now, context: MemoryContext(slowed: false), tabMemoryOn: false)),
         ("memory-chrome-week", MemoryAdvice.card(chromeHeavy, mac: mac("warning", swappedMB: 600), now: now,
                                                  context: MemoryContext(slowed: true, week: PressureHistory.Week(count: 3, minutes: 40, chromeCount: 2)), tabMemoryOn: false))]
    }
}
