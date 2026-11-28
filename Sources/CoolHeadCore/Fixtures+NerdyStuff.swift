import Foundation

/// Checks for Nerdy stuff written from its slots (NerdyStuff.swift; docs/CARD-TEMPLATE.md, Nerdy stuff), on every busy
/// sample's made-up readings and on made-up slots for what the samples don't reach.
extension Fixture {
    static func nerdyStuffSamples(_ now: Date) -> [(String, Card)] { [] }

    /// Every family's cards as the app makes them, with their Nerdy stuff, made up: for the check below and for
    /// screenshots (see PanelView's sample cards).
    public static func nerdyLiveSamples(_ now: Date) -> [(String, LiveCard)] {
        var out: [(String, LiveCard)] = []
        // power
        let morning = PowerState.logDate.date(from: "2026-11-16 08:00:00 -0500")!
        let holds = PowerState.parseAssertions(assertionsText)
        func first(_ c: [LiveCard]) -> LiveCard? { c.first }
        out += [("power-low-adapter", first(PowerState.cards(lowPower: PowerState.parseCustom(customText), lowPowerNow: true, onPower: true, busy: true, holds: [], who: who, night: nil, now: morning))),
                ("power-held-awake", first(PowerState.cards(lowPower: nil, lowPowerNow: false, onPower: true, busy: false, holds: [holds[0]], who: who, idleFor: { _ in 2.75 * 3600 }, night: nil, now: morning))),
                ("power-night-wakes", first(PowerState.cards(lowPower: nil, lowPowerNow: false, onPower: false, busy: false, holds: [], who: who, night: PowerState.parseLog(logText()), now: morning))),
                ("power-night-upkeep", first(PowerState.cards(lowPower: nil, lowPowerNow: false, onPower: false, busy: false, holds: [], who: who, night: PowerState.parseLog(logText(upkeepMost: true)), now: morning)))]
            .compactMap { k, c in c.map { (k, $0) } }
        // browsers, crash loops, hardware
        let chrome = "/Applications/Google Chrome.app"
        if let c = BrowserTampering.cards(policies: [("Google Chrome", chrome, ["force an extension", "set the search engine"])], managed: false, scripted: []).first { out.append(("browser-policy", c)) }
        if let c = BrowserTampering.cards(policies: [], managed: false, scripted: [
            BrowserTampering.Scripted(pid: 4100, browser: "Google Chrome", bundle: chrome, parent: "node", folder: NSHomeDirectory() + "/Downloads/helper-ext")]).first { out.append(("browser-scripted", c)) }
        if let c = CrashLoops.cards(CrashLoops.loops(crashes("Backblaze", bundle: "com.backblaze.bzbmenu", 40, every: 1800, ago: 900, now: now), now: now)).first { out.append(("crash-loop", c)) }
        for (id, r) in hardwareReports(now) { for (i, c) in r.cards(now: now).enumerated() { out.append(("hardware-\(id)-\(i)", c)) } }
        // a hang, fast charging, and warm with no cause, made up
        if let f = Fixture.all(now).first {
            let since = now.addingTimeInterval(-600)
            let hc = Hang.card(.paused, f.evidence, stuckFor: 600, waiting: ["python3"], volumes: [], terminal: nil, now: now)
            out.append(("hang-paused", LiveCard(id: "hang-paused", pid: f.evidence.pid, card: hc,
                                                details: NerdyStuff.hang(f.evidence, card: hc, kind: .paused, since: since, now: now, threshold: 300, waiting: ["python3"]).lines())))
        }
        var warmMac = MacState(); warmMac.thermal = "fair"; warmMac.charging = true; warmMac.batteryPercent = 54; warmMac.batteryWatts = 38
        warmMac.adapterWatts = 96; warmMac.macWatts = 14; warmMac.memoryPressure = "normal"
        let plain = Card(state: .working, headline: "", explanation: "", fixes: [Fix.guide("air", "Give it air", "This shows how.", steps: ["Move it."], recommended: true)])
        out.append(("charging", LiveCard(id: "charging", pid: nil, card: plain, details: NerdyStuff.charging(warmMac, card: plain, now: now).lines())))
        out.append(("heat", LiveCard(id: "heat", pid: nil, card: plain,
                                     details: NerdyStuff.warm(warmMac, card: plain, busiest: (1...9).map { ("p\($0)", 0.9 - Double($0) / 20) }, now: now).lines())))
        // memory, with the samples' own groups and a few more, so the list is cut at five
        // the same card as Wording's memory-chrome sample (its MacState and Chrome group), so a screenshot's Nerdy stuff
        // matches the card drawn above it; the readings Nerdy stuff shows are added after the card is made
        var tight = MacState(); tight.memoryPressure = "warning"; tight.swapUsedMB = 1500; tight.swapTotalMB = 3000
        let chrome0 = MemGroup(key: "Google Chrome", name: "Google Chrome", kind: .browser, bundle: "/Applications/Google Chrome.app", bytes: UInt64(5.5 * 1_000_000_000), count: 41)
        let mc = MemoryAdvice.card([chrome0], mac: tight, now: now, tabMemoryOn: false)
        tight.swappedOutMB = 600; tight.memoryGB = 16; tight.diskFreeBytes = 180_000_000_000
        let groups = [chrome0] + [("Slack", 1.2, 6), ("Docker", 0.9, 4), ("Mail", 0.6, 3), ("Xcode", 0.54, 2), ("Music", 0.3, 1), ("Notes", 0.2, 1)]
            .map { MemGroup(key: $0.0, name: $0.0, kind: .app, bundle: "/Applications/\($0.0).app", bytes: UInt64($0.1 * 1_073_741_824), count: $0.2) }
        out.append(("memory-chrome", LiveCard(id: "memory-warning", pid: nil, card: mc,
                                              details: NerdyStuff.memory(groups, mac: tight, card: mc, now: now).lines())))
        return out
    }

    static func nerdyStuffChecks(_ now: Date) -> [(String, Bool, String)] {
        let samples = Wording.nerdySamples(now: now)
        var bad: [String] = []
        let sources = NerdyStuff.Source.allCases.map { "(\($0.rawValue)" }
        for (id, n) in samples.sorted(by: { $0.key < $1.key }) {
            let lines = n.lines()
            // the slots' headings, in their fixed order, each once
            let heads = lines.filter(NerdyStuff.headings.contains)
            if heads != NerdyStuff.headings.filter(heads.contains) || Set(heads).count != heads.count { bad.append("\(id): headings \(heads)") }
            if heads.first != NerdyStuff.headings[0] { bad.append("\(id): doesn't start with what Cool Head saw") }
            // every reading names its source, from the closed list
            for r in n.saw where !r.lines[0].contains("(\(r.source.rawValue)") || !sources.contains(where: r.lines[0].contains) {
                bad.append("\(id): \(r.name) names no source")
            }
            // lists stop at five, with a line for the rest
            for l in n.lists {
                let shown = l.lines.dropFirst().count
                if shown > NerdyStuff.cap + 1 || (l.rows.count > NerdyStuff.cap && shown != NerdyStuff.cap + 1) { bad.append("\(id): \(l.title) shows \(shown) lines") }
            }
            // the word list's rules that hold beyond the cards
            for l in lines { for p in CardTemplate.clarity(l) { bad.append("\(id): \(p) in \"\(l.prefix(40))\"") } }
            // every option is in Why this option, and the recommended one says so
            if n.option.count != (Wording.samples(now: now).first { $0.0 == id }?.1.fixes.count ?? n.option.count) { bad.append("\(id): not every option is in Why this option") }
        }
        // every other family, as the app makes its cards: headings in order, every reading with a source from the list,
        // lists cut at five, and the word list's clarity rules
        let live = nerdyLiveSamples(now)
        for (id, c) in live {
            guard !c.details.isEmpty else { bad.append("\(id): no Nerdy stuff"); continue }
            if id.hasPrefix("hardware-") && !c.details.contains("Why this verdict") { bad.append("\(id): no rule behind the card") }
            let heads = c.details.filter(NerdyStuff.headings.contains)
            if heads.isEmpty || heads != NerdyStuff.headings.filter(heads.contains) { bad.append("\(id): headings \(heads)") }
            let sawEnd = c.details.dropFirst().firstIndex(where: NerdyStuff.headings.contains) ?? c.details.endIndex
            for l in c.details[1..<sawEnd] where !l.hasPrefix(" ") && !l.hasSuffix(":") && l.contains(": ") && !c.card.facts.contains(l) {
                if !sources.contains(where: l.contains) { bad.append("\(id): \"\(l.prefix(40))\" names no source") }
            }
            var run = 0
            for l in c.details { run = l.hasPrefix("  ") && !l.hasPrefix("  check:") ? run + 1 : 0; if run > NerdyStuff.cap + 1 { bad.append("\(id): a list longer than five and its rest line"); break } }
            for l in c.details { for p in CardTemplate.clarity(l) { bad.append("\(id): \(p) in \"\(l.prefix(40))\"") } }
            // every reading has a name: a family's line without one shows as "Note"
            for l in c.details where l.hasPrefix("Note: ") { bad.append("\(id): a reading without a name, \"\(l.prefix(40))\"") }
        }
        if !live.contains(where: { $0.0 == "heat" && $0.1.details.contains("  and 4 more") }) { bad.append("heat: the busiest aren't all counted in the rest line") }
        if !live.contains(where: { $0.0 == "hang-paused" && $0.1.details.contains { $0.hasPrefix("Stuck: paused (ps state T) for 5 minutes") } }) { bad.append("hang-paused: not the hang's own rule") }
        if !live.contains(where: { $0.0 == "memory-chrome" && $0.1.details.contains { $0.hasPrefix("  and 2 more, ") && $0.hasSuffix(" in total") } }) { bad.append("memory-chrome: the biggest users aren't cut at five with the rest added up") }
        // made up: sentences the template moved out of the explanation are shown, first; a long list is cut at five
        var m = NerdyStuff()
        m.moved = ["It also writes a large log."]
        m.saw = [.init("CPU", "1.00 cores", .rusage)]
        m.lists = [.init("Also busy", (1...8).map { "row \($0)" })]
        let ml = m.lines()
        if ml.count < 2 || ml[1] != "It also writes a large log." { bad.append("made-up: moved sentences not first under what Cool Head saw") }
        if ml.filter({ $0.hasPrefix("  row") }).count != NerdyStuff.cap || !ml.contains("  and 3 more") { bad.append("made-up: a list of 8 isn't cut at five with 3 more") }
        // the energy week: 18 rows show five, then the rest with their share added up
        let shares = [0.31, 0.18, 0.12, 0.09, 0.06] + Array(repeating: 0.02, count: 12) + [0.0]
        let el = NerdyStuff.energy(shares.enumerated().map { "\(PowerHistory.share($0.element))  app \($0.offset)" }, shares: shares).lines()
        if el.filter({ $0.hasPrefix("  ") }).count != NerdyStuff.cap + 1 || !el.contains("  and 13 more, 24% in total") { bad.append("energy week: \(el.suffix(2))") }
        // the clarity rules catch the case that started them
        if CardTemplate.clarity("it moved over 256 MB to storage").isEmpty { bad.append("made-up: \"moved over 256 MB\" isn't caught") }
        if CardTemplate.clarity("it moved over 1.5 GB to storage").isEmpty { bad.append("made-up: \"over 1.5 GB\" isn't caught") }
        // What Cool Head did: only this card's own lines, though another card's mention the same name
        let t0 = now.addingTimeInterval(-60)
        let mixed = [Watcher.LogEntry(t: t0, text: "Stop pressed for a Python script: stopped", about: "pid-1"),
                     Watcher.LogEntry(t: t0, text: "Card: a Python script, working", about: "pid-2")]
        if NerdyStuff.did(mixed, about: "pid-2") != ["\(Fmt.time(t0)) Card: a Python script, working"] { bad.append("made-up: another card's log line shows") }
        // a process's own text: secrets hidden, the home folder as ~
        let raw = "step 40/100 token=abc123 in " + NSHomeDirectory() + "/Projects/x"
        if NerdyStuff.shown(raw).contains("abc123") || NerdyStuff.shown(raw).contains(NSHomeDirectory()) { bad.append("made-up: \(NerdyStuff.shown(raw))") }
        // the battery's condition and capacity name system_profiler, with no time, since they are read up to an hour earlier
        if !live.contains(where: { $0.0.hasPrefix("hardware-battery") && $0.1.details.contains { $0.hasPrefix("Maximum Capacity: ") && $0.hasSuffix("(\(NerdyStuff.Source.systemProfiler.rawValue))") } }) {
            bad.append("hardware-battery: Maximum Capacity doesn't name system_profiler")
        }
        // a path with a space is one word to the shell, home outside the quotes
        if NerdyStuff.shellPath(NSHomeDirectory() + "/Library/Application Support/My Job/run's log.txt") != "~/'Library/Application Support/My Job/run'\\''s log.txt'" {
            bad.append("made-up: a path with a space or a quote isn't one word: \(NerdyStuff.shellPath(NSHomeDirectory() + "/Library/Application Support/My Job/run's log.txt"))")
        }
        if !CardTemplate.clarity("Busy: 0.5 cores or more for 60 seconds.").isEmpty { bad.append("made-up: a clear line is flagged") }
        let ok = bad.isEmpty
        return [("nerdy-stuff", ok, ok ? "\(samples.count) busy samples and \(live.count) cards of every other family written from the slots: headings in order, every reading with its source, lists at five, the word list's clarity rules" : bad.joined(separator: "; "))]
    }
}
