import AppKit

/// Checks for the CPU limit (CPUCap): the levels offered, the option on a card, and the card once it's limited.
extension Fixture {
    /// A made-up app already running cooler and still busy, offered the limit; and the same app at Slow and steady, still
    /// adding to the heat (for screenshots: COOLHEAD_SNAPSHOT_SAMPLES).
    static func cpuCapSamples(_ now: Date) -> [(String, Card)] {
        let app = Evidence.sample(name: "Huddle", path: "/Applications/Huddle.app/Contents/MacOS/Huddle", start: now.addingTimeInterval(-3 * 3600), cores: 3)
        return [("cap-offered", Card.make(app, now: now, busySince: now.addingTimeInterval(-3600), warm: true).offeringCap(app: true, cores: 3)),
                ("cap-half", Card.stillHotUnderCap(subject: "Huddle", app: true, level: .slow, now: 1.5))]
    }

    static func cpuCapChecks(_ now: Date) -> [(String, Bool, String)] {
        var review: [(String, Bool, String)] = []
        func offer(_ c: Card) -> CPUCap.Offer? { c.fixes.compactMap { if case .cpuCap(let o) = $0.kind { return o }; return nil }.first }
        let app = Evidence.sample(name: "Huddle", path: "/Applications/Huddle.app/Contents/MacOS/Huddle", start: now.addingTimeInterval(-3 * 3600), cores: 3)
        let c = Card.make(app, now: now, busySince: now.addingTimeInterval(-3600), warm: true).offeringCap(app: true, cores: 3)
        let o = offer(c)
        let ok = c.recommended.map { if case .cpuCap = $0.kind { return true }; return false } == true
            && !c.fixes.contains { $0.kind == .cooler } && c.fixes.filter(\.recommended).count == 1
            && c.explanation.hasSuffix("It's already running cooler and still using about 3 cores.")
            && o?.current == .cooler && o?.suggested == .easy && o?.now == 3 && o?.levels == [.barely, .slow, .easy, .cooler, .full]
        review.append(("cpu-cap-offered", ok, "recommended \(c.recommended?.title ?? "none"); \(c.explanation)"))

        // levels: fixed amounts, the same five stops for everything; the lightest limit that at least halves its use is
        // recommended
        let amounts = CPUCap.Level.allCases.map(\.cores)
        let suggestions = [0.8, 1, 1.5, 1.9, 2, 4].map { CPUCap.suggested(cores: $0) }
        // where a Managed line's slider sits: Cooler when only running cooler, its limit, or Full speed as an exception
        var item = Watcher.CooledItem(key: "k", pid: 1, start: nil, name: "Huddle", reportSubject: "a sample", since: now, before: nil, after: nil,
                                      rule: "app:com.example.huddle")
        let onlyCooler = item.level
        item.capLevel = .barely; let atLimit = item.level
        item.fullSpeed = true; let exception = item.level
        review.append(("cpu-cap-levels", amounts == [0.2, 0.5, 1, nil, nil] && CPUCap.levels == [.barely, .slow, .easy, .cooler, .full]
                       && suggestions == [.barely, .slow, .slow, .slow, .easy, .easy]
                       && onlyCooler == .cooler && atLimit == .barely && exception == .full,
                       "amounts \(amounts.map { $0.map { String($0) } ?? "none" }); for 0.8, 1, 1.5, 1.9, 2, 4 cores \(suggestions.map(\.name)); a line at \(onlyCooler.name), \(atLimit.name), \(exception.name)"))

        // the words: an amount always, a comparison only with what it uses now, and no promise where it changes little
        let slowLine = CPUCap.Level.slow.line(now: 1.5, app: true)
        let words = slowLine == "Slow and steady: up to half of one core (50% in Activity Monitor): about a third of its pace now, and about a third of the heat."
            && CPUCap.Level.easy.effect(now: 0.8, app: true) == "up to one core (100% in Activity Monitor): at least what it uses now, so nothing changes."
            && CPUCap.Level.easy.effect(now: 1.25, app: true) == "up to one core (100% in Activity Monitor): about 80% of its pace now, and about 80% of the heat."
            && CPUCap.Level.easy.effect(now: nil, app: true) == "up to one core (100% in Activity Monitor)."
            && CPUCap.Level.easy.effect(now: 4, app: true) == "up to one core (100% in Activity Monitor): about a quarter of its pace now, and about a quarter of the heat."
        review.append(("cpu-cap-words", words, slowLine))

        // already limited and still hot: the next level down is recommended, with no comparison (nothing is measured)
        let h = Card.stillHotUnderCap(subject: "Huddle", app: true, level: .slow, now: 1.5)
        let ho = offer(h)
        let hotOK = ho?.current == .slow && ho?.suggested == .barely && ho?.now == nil
            && h.explanation.hasPrefix("It's limited to Slow and steady and still using about 1.5 cores.")
        // at Barely running there's no level further down: it doesn't recommend where it already is as slowing it further
        let low = Card.stillHotUnderCap(subject: "Huddle", app: true, level: .barely, now: 1)
        let lowOK = !low.explanation.contains("further") && low.explanation.hasSuffix("quitting it stops the heat.")
        review.append(("cpu-cap-still-hot", hotOK && lowOK, "\(h.headline) \(h.explanation) suggested \(ho?.suggested.name ?? "none"); at Barely running: \(low.explanation)"))

        // when a card running cooler offers the limit: a core or more, three minutes or more after; once limited, where it is
        let base = Card.make(app, now: now, busySince: now.addingTimeInterval(-3600), warm: true)
        func when(_ minutes: Double, _ cores: Double, _ level: CPUCap.Level? = nil) -> CPUCap.Offer? {
            offer(base.runningCooler(subject: "Huddle", app: true, since: now.addingTimeInterval(-60 * minutes), level: level, cores: cores, now: now))
        }
        let early = when(2, 3), late = when(3, 3), light = when(10, 0.8), limited = when(1, 1.5, .slow)
        review.append(("cpu-cap-offered-when", early == nil && late?.current == .cooler && light == nil && limited?.current == .slow,
                       "2 minutes \(early != nil); 3 minutes \(late != nil); 0.8 core \(light != nil); limited \(limited?.current.name ?? "none")"))

        // the slider reports once, where it's let go (25 November 2026: a drag applied each stop it passed, and passing
        // Cooler cleared a rule's level): macOS's own slider, not continuous, stopping only at the levels; a VoiceOver
        // step reports once, at once
        final class Count: NSObject { var stops: [Int] = []; @objc func changed(_ s: CPUCap.Slider) { stops.append(s.stop) } }
        let slider = CPUCap.Slider.make(levels: 5, at: 1), count = Count()
        slider.target = count; slider.action = #selector(Count.changed(_:))
        slider.accessibilityPerformIncrement()
        // what a release applies: where it's let go, unless that's its level or where it was grabbed; and the page's
        // level moves the thumb when it isn't held (a pick that didn't take puts it back)
        let applies = [CPUCap.Slider.apply(released: 3, grabbed: 1, level: 1),   // dragged to Cooler: Cooler
                       CPUCap.Slider.apply(released: 1, grabbed: 3, level: 1),   // dragged back to where it is: nothing
                       CPUCap.Slider.apply(released: 1, grabbed: 1, level: 2),   // grabbed, not moved, level changed: nothing
                       CPUCap.Slider.apply(released: 2, grabbed: nil, level: 1)] // a key or VoiceOver step: applies
        let shown = CPUCap.Slider.make(levels: 5, at: 1)
        shown.doubleValue = 3; shown.show(1)
        let putBack1 = shown.stop == 1 && shown.level == 1 && shown.toApply == nil
        // released on a stop that didn't take (no redraw from the page): back on its level
        shown.doubleValue = 2; shown.putBack()
        let putBack = putBack1 && shown.stop == 1
        let sliderOK = !slider.isContinuous && slider.allowsTickMarkValuesOnly && slider.numberOfTickMarks == 5
            && slider.minValue == 0 && slider.maxValue == 4 && count.stops == [2] && !slider.tracking
            && applies == [3, nil, nil, 2] && putBack
        review.append(("cpu-cap-slider-applies-once", sliderOK,
                       "continuous \(slider.isContinuous); stops only \(slider.allowsTickMarkValuesOnly); \(slider.numberOfTickMarks) stops from \(slider.minValue) to \(slider.maxValue); a VoiceOver step reported \(count.stops); releases apply \(applies); put back \(putBack)"))

        // never offered: a virtual machine, an extension Finder waits on, a call app; an ordinary app is
        let vm = CPUCap.neverLimited(path: "/Applications/UTM.app/Contents/MacOS/UTM", key: "app:com.utmapp.UTM", virtualMachine: true)
        let appex = CPUCap.neverLimited(path: "/Applications/Drive.app/Contents/PlugIns/FileProvider.appex/Contents/MacOS/FileProvider",
                                        key: "app:com.example.drive", virtualMachine: false)
        let call = CPUCap.neverLimited(path: "/Applications/zoom.us.app/Contents/MacOS/zoom.us", key: "app:us.zoom.xos", virtualMachine: false)
        let ordinary = CPUCap.neverLimited(path: "/Applications/Huddle.app/Contents/MacOS/Huddle", key: "app:com.example.huddle", virtualMachine: false)
        let notOffered = offer(base.runningCooler(subject: "zoom.us", app: true, since: now.addingTimeInterval(-600), level: nil,
                                                  cores: 3, now: now, neverLimited: true)) == nil
        review.append(("cpu-cap-never-limited", vm && appex && call && !ordinary && notOffered,
                       "virtual machine \(vm); extension \(appex); call app \(call); an ordinary app \(ordinary); card offers it \(!notOffered)"))

        // the share settles where the level's amount is used, whatever the app would use at full speed, a step at a time
        func settle(want: Double, target: Double) -> (share: Double, used: Double, biggestStep: Double) {
            var share = 1.0, step = 1.0
            for _ in 0..<40 {
                let next = CPULimiter.nextShare(share, target: target, used: want * share)
                step = max(step == 1 ? 0 : step, max(next / share, share / next)); share = next
            }
            return (share, want * share, step)
        }
        let fourCores = settle(want: 4, target: 0.2), halfOfThree = settle(want: 3, target: 0.5), small = settle(want: 0.1, target: 0.5)
        let idle = CPULimiter.nextShare(0.1, target: 0.2, used: 0)
        let floor = CPULimiter.nextShare(0.05, target: 0.001, used: 8)
        let shareOK = abs(fourCores.used - 0.2) < 0.01 && abs(halfOfThree.used - 0.5) < 0.01 && small.share == 1
            && fourCores.biggestStep <= 2 && abs(idle - 0.15) < 0.0001 && floor == 0.05
        review.append(("cpu-limit-share", shareOK,
                       "4 cores held to \(String(format: "%.2f", fourCores.used)); 3 cores to \(String(format: "%.2f", halfOfThree.used)); under its limit runs fully \(small.share); idle steps up to \(idle); never below \(floor)"))

        // a rule keeps only the level, in a throwaway set; removing the rule or trusting the app forgets it
        let suite = "coolhead.selftest.\(UUID().uuidString)"
        let saved = Trust.defaults
        if let d = UserDefaults(suiteName: suite) { Trust.defaults = d }
        let key = "app:com.example.huddle"
        CoolerRules.add(key, name: "Huddle")
        CoolerRules.setLevel(key, .slow)
        let stored = CoolerRules.levels[key] == .slow
            && (Trust.defaults.dictionary(forKey: "alwaysCoolerLimit") as? [String: String]) == [key: "slow"]
        // 0.21.0's levels: its one-core "steady" and its relative "half" are the one-core level; anything unknown is dropped
        Trust.defaults.set([key: "half", "app:b": "steady", "app:c": "quarter"], forKey: "alwaysCoolerLimit")
        let old = CoolerRules.levels
        let legacy = old == [key: .easy, "app:b": .easy]
        Trust.defaults.set([key: "slow"], forKey: "alwaysCoolerLimit")
        CoolerRules.setLevel(key, .barely)
        let changed = CoolerRules.levels[key] == .barely
        Trust.add(key, name: "Huddle")
        let trustForgets = CoolerRules.levels[key] == nil
        CoolerRules.add(key, name: "Huddle"); CoolerRules.setLevel(key, .easy); CoolerRules.remove(key)
        let removeForgets = CoolerRules.levels.isEmpty
        Trust.defaults = saved
        UserDefaults.standard.removePersistentDomain(forName: suite)
        review.append(("cpu-limit-rule-level", stored && legacy && changed && trustForgets && removeForgets,
                       "stored as the level only \(stored); 0.21.0's levels \(old.mapValues(\.name)); changed \(changed); trusting forgets it \(trustForgets); removing forgets it \(removeForgets)"))

        // for real, on a busy child process of our own: held to the level's fixed amount whatever came before (25
        // November 2026: Half speed after another limit held it to 0.37 core of about 0.95, and a rule's Half speed was
        // 0.1 from each launch, both from a measured "before")
        review.append(cpuLimitHoldsChecks())
        return review
    }
    /// A child process that keeps one core busy, limited to Barely running and then to Slow and steady, and a second
    /// group started at Slow and steady: each should settle at its level's amount.
    static func cpuLimitHoldsChecks() -> (String, Bool, String) {
        func busy() -> Process? {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/yes")
            p.standardOutput = FileHandle.nullDevice
            return (try? p.run()) != nil ? p : nil
        }
        guard let a = busy() else { return ("cpu-limit-holds-the-amount", false, "couldn't start /usr/bin/yes") }
        let limiter = CPULimiter()
        // the limiter narrows toward the amount a step a second, so it settles sooner on a quick Mac than on a busy test
        // machine (a CI runner read 0.69 and 0.90 at a fixed 4 seconds, 25 November 2026): wait, up to 20 seconds,
        // for two readings a second apart both within the level's range, and say how long it took
        func settle(_ key: String, _ fits: (Double) -> Bool) -> (used: Double, seconds: Int) {
            var inRow = 0, last = -1.0
            for s in 1...20 {
                Thread.sleep(forTimeInterval: 1)
                last = limiter.snapshot[key]?.used ?? -1
                inRow = fits(last) ? inRow + 1 : 0
                if inRow == 2 { return (last, s) }
            }
            return (last, 20)
        }
        let barelyFits = { (u: Double) in u > 0 && u < 0.35 }, slowFits = { (u: Double) in abs(u - 0.5) < 0.15 }
        let pid = a.processIdentifier
        limiter.set("a", pids: [pid], trust: nil, root: pid, level: .barely)
        let barely = settle("a", barelyFits)
        limiter.set("a", pids: [pid], trust: nil, root: pid, level: .slow)
        let change = settle("a", slowFits)
        limiter.remove("a")
        var fresh = (used: -1.0, seconds: 0)
        if let b = busy() {
            let bp = b.processIdentifier
            limiter.set("b", pids: [bp], trust: nil, root: bp, level: .slow)
            fresh = settle("b", slowFits)
            limiter.remove("b")
            b.terminate()
        }
        a.terminate()
        let ok = barelyFits(barely.used) && slowFits(change.used) && slowFits(fresh.used)
        func say(_ r: (used: Double, seconds: Int)) -> String { String(format: "%.2f", r.used) + " core after \(r.seconds) s" }
        return ("cpu-limit-holds-the-amount", ok,
                "Barely running \(say(barely)); then Slow and steady \(say(change)); a fresh group at Slow and steady \(say(fresh))")
    }
}
