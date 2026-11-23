import Foundation

/// Checks for the CPU limit (CPUCap): the levels offered, the option on a card, and the card once it's limited.
extension Fixture {
    /// A made-up app already running cooler and still busy, offered the limit; and the same app at half speed, still
    /// adding to the heat (for screenshots: COOLHEAD_SNAPSHOT_SAMPLES).
    static func cpuCapSamples(_ now: Date) -> [(String, Card)] {
        let app = Evidence.sample(name: "Huddle", path: "/Applications/Huddle.app/Contents/MacOS/Huddle", start: now.addingTimeInterval(-3 * 3600), cores: 3)
        return [("cap-offered", Card.make(app, now: now, busySince: now.addingTimeInterval(-3600), warm: true).offeringCap(app: true, cores: 3)),
                ("cap-half", Card.stillHotUnderCap(subject: "Huddle", app: true, level: .half, before: 3, now: 1.5))]
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
            && o?.current == .cooler && o?.suggested == .half && o?.levels == [.barely, .steady, .half, .cooler, .full]
        review.append(("cpu-cap-offered", ok, "recommended \(c.recommended?.title ?? "none"); \(c.explanation)"))

        // levels: Slow and steady only from about 3 cores; half speed is half of the use before the limit; Cooler and Full
        // speed have no limit
        let two = CPUCap.levels(before: 2), three = CPUCap.levels(before: 3)
        let amounts = CPUCap.Level.barely.cores(before: 3) == 0.2 && CPUCap.Level.steady.cores(before: 3) == 1
            && CPUCap.Level.half.cores(before: 3) == 1.5 && CPUCap.Level.cooler.cores(before: 3) == nil && CPUCap.Level.full.cores(before: 3) == nil
        // where a Managed line's slider sits: Cooler when only running cooler, its limit, or Full speed as an exception
        var item = Watcher.CooledItem(key: "k", pid: 1, start: nil, name: "Huddle", reportSubject: "a sample", since: now, before: nil, after: nil,
                                      rule: "app:com.example.huddle")
        let onlyCooler = item.level
        item.capLevel = .barely; let atLimit = item.level
        item.fullSpeed = true; let exception = item.level
        review.append(("cpu-cap-levels", two == [.barely, .half, .cooler, .full] && three.count == 5 && amounts
                       && onlyCooler == .cooler && atLimit == .barely && exception == .full,
                       "at 2 cores \(two.map(\.name)); at 3 \(three.map(\.name)); a line at \(onlyCooler.name), \(atLimit.name), \(exception.name)"))

        // already at half speed and still hot: the next level down is recommended, and the words compare with before
        let h = Card.stillHotUnderCap(subject: "Huddle", app: true, level: .half, before: 3, now: 1.5)
        let ho = offer(h)
        let hotOK = ho?.current == .half && ho?.suggested == .steady && h.explanation.hasPrefix("It's at half speed and still using about 1.5 cores.")
            && CPUCap.Level.steady.line(before: 3, app: true, limited: true) == "Slow and steady: about a third of its pace before the limit, and about a third of the heat."
        review.append(("cpu-cap-still-hot", hotOK, "\(h.headline) \(h.explanation) suggested \(ho?.suggested.name ?? "none")"))

        // when a card running cooler offers the limit: a core or more, three minutes or more after; once limited, where it is
        let base = Card.make(app, now: now, busySince: now.addingTimeInterval(-3600), warm: true)
        func when(_ minutes: Double, _ cores: Double, _ level: CPUCap.Level? = nil) -> CPUCap.Offer? {
            offer(base.runningCooler(subject: "Huddle", app: true, since: now.addingTimeInterval(-60 * minutes), level: level,
                                     before: level == nil ? nil : 3, cores: cores, now: now))
        }
        let early = when(2, 3), late = when(3, 3), light = when(10, 0.8), limited = when(1, 1.5, .half)
        review.append(("cpu-cap-offered-when", early == nil && late?.current == .cooler && light == nil && limited?.current == .half
                       && limited?.before == 3,
                       "2 minutes \(early != nil); 3 minutes \(late != nil); 0.8 core \(light != nil); limited \(limited?.current.name ?? "none")"))

        // never offered: a virtual machine, an extension Finder waits on, a call app; an ordinary app is
        let vm = CPUCap.neverLimited(path: "/Applications/UTM.app/Contents/MacOS/UTM", key: "app:com.utmapp.UTM", virtualMachine: true)
        let appex = CPUCap.neverLimited(path: "/Applications/Drive.app/Contents/PlugIns/FileProvider.appex/Contents/MacOS/FileProvider",
                                        key: "app:com.example.drive", virtualMachine: false)
        let call = CPUCap.neverLimited(path: "/Applications/zoom.us.app/Contents/MacOS/zoom.us", key: "app:us.zoom.xos", virtualMachine: false)
        let ordinary = CPUCap.neverLimited(path: "/Applications/Huddle.app/Contents/MacOS/Huddle", key: "app:com.example.huddle", virtualMachine: false)
        let notOffered = offer(base.runningCooler(subject: "zoom.us", app: true, since: now.addingTimeInterval(-600), level: nil, before: nil,
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
        let fourCores = settle(want: 4, target: 0.2), halfOfThree = settle(want: 3, target: 1.5), small = settle(want: 0.1, target: 0.5)
        let idle = CPULimiter.nextShare(0.1, target: 0.2, used: 0)
        let floor = CPULimiter.nextShare(0.05, target: 0.001, used: 8)
        let shareOK = abs(fourCores.used - 0.2) < 0.01 && abs(halfOfThree.used - 1.5) < 0.01 && small.share == 1
            && fourCores.biggestStep <= 2 && abs(idle - 0.15) < 0.0001 && floor == 0.05
        review.append(("cpu-limit-share", shareOK,
                       "4 cores held to \(String(format: "%.2f", fourCores.used)); 3 cores to \(String(format: "%.2f", halfOfThree.used)); under its limit runs fully \(small.share); idle steps up to \(idle); never below \(floor)"))

        // a rule keeps only the level, in a throwaway set; removing the rule or trusting the app forgets it
        let suite = "coolhead.selftest.\(UUID().uuidString)"
        let saved = Trust.defaults
        if let d = UserDefaults(suiteName: suite) { Trust.defaults = d }
        let key = "app:com.example.huddle"
        CoolerRules.add(key, name: "Huddle")
        CoolerRules.setLevel(key, .half)
        let stored = CoolerRules.levels[key] == .half
            && (Trust.defaults.dictionary(forKey: "alwaysCoolerLimit") as? [String: String]) == [key: "half"]
        CoolerRules.setLevel(key, .barely)
        let changed = CoolerRules.levels[key] == .barely
        Trust.add(key, name: "Huddle")
        let trustForgets = CoolerRules.levels[key] == nil
        CoolerRules.add(key, name: "Huddle"); CoolerRules.setLevel(key, .steady); CoolerRules.remove(key)
        let removeForgets = CoolerRules.levels.isEmpty
        Trust.defaults = saved
        UserDefaults.standard.removePersistentDomain(forName: suite)
        review.append(("cpu-limit-rule-level", stored && changed && trustForgets && removeForgets,
                       "stored as the level only \(stored); changed \(changed); trusting forgets it \(trustForgets); removing forgets it \(removeForgets)"))
        return review
    }
}
