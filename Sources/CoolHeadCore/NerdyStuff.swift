import Foundation

/// A card's Nerdy stuff, written from fixed slots, in this order, so every family says the same kinds of things in the
/// same places and a power user can check them (docs/CARD-TEMPLATE.md, Nerdy stuff):
///   What Cool Head saw: each reading the card is built on, with its exact figure, the macOS source it came from, when
///     it was read, and where there is one, a Terminal command that shows the same figure; then what else was busy.
///   Why this verdict: the rule that made the verdict, with its threshold, and which kind of card won and why.
///   Why this option: every option's facts (who does it, what it does about the problem, Caution, what it closes), and
///     why the recommended one was chosen.
///   What it is: the process or thing the card is about.
///   What Cool Head did: this card's lines from Cool Head's log, newest first.
/// A slot with nothing to say is left out; a list stops at five, with one line for the rest. Technical terms are fine
/// here, each said the same way every time; sources are named by their technical name, from a closed list.
public struct NerdyStuff {
    /// Where a reading came from: the macOS interface or file Cool Head read it from, by its technical name.
    public enum Source: String, CaseIterable {
        case rusage = "proc_pid_rusage"
        case ps = "ps"
        case taskInfo = "proc_pidinfo"
        case procArgs = "sysctl KERN_PROCARGS2"
        case openFiles = "proc_pidfdinfo"
        case gpu = "IORegistry, IOAccelerator AppUsage"
        case ownFile = "the file it writes"
        case coolHead = "Cool Head's readings, every 10 seconds"
        case psState = "ps, process state"
        case unresponsive = "SkyLight SLSEventIsAppUnresponsive"
        case thermal = "ProcessInfo.thermalState"
        case pressure = "sysctl kern.memorystatus_vm_pressure_level"
        case swap = "sysctl vm.swapusage"
        case swapouts = "host_statistics64, swapouts"
        case diskSpace = "URL volumeAvailableCapacity"
        case battery = "IORegistry, AppleSmartBattery"
        case lowPower = "pmset -g custom"
        case assertions = "pmset -g assertions"
        case sleepLog = "pmset -g log"
        case smart = "NVMe SMART log"
        case reports = "DiagnosticReports"
        case policies = "CFPreferences, the browser's policy domain"
        case appsMemory = "proc_pid_rusage footprints, added up by app"
        case ports = "IORegistry, port-statistics"
        case physicalMemory = "ProcessInfo.physicalMemory"
        case powerlog = "powerlog, CurrentPowerlog.PLSQL"
        case systemProfiler = "system_profiler SPPowerDataType, read up to an hour earlier"
        case enrollment = "profiles status -type enrollment"
        case procPath = "proc_pidpath"
        case lowPowerNow = "ProcessInfo.isLowPowerModeEnabled"
    }

    public struct Reading {
        public var name: String
        public var value: String
        public var source: Source
        public var at: Date?
        /// A Terminal command that shows the same figure, for whoever wants to check it.
        public var check: String?
        /// The figure alone, where `value` also says how it was taken, for verbose mode's card.
        public var brief: String? = nil
        public init(_ name: String, _ value: String, _ source: Source, at: Date? = nil, check: String? = nil) {
            self.name = name; self.value = value; self.source = source; self.at = at; self.check = check
        }
        var lines: [String] {
            ["\(name): \(value) (\(source.rawValue)\(at.map { ", \(Fmt.time($0))" } ?? ""))"] + (check.map { ["  check: \($0)"] } ?? [])
        }
    }

    /// A list: its title, its rows biggest first, and how to total what's left past the first five.
    public struct List {
        public var title: String
        public var rows: [String]
        /// The line for the rows past the fifth: "and 13 more, 24% in total". Nil to say only how many.
        public var rest: String?
        public init(_ title: String, _ rows: [String], rest: String? = nil) { self.title = title; self.rows = rows; self.rest = rest }
        var lines: [String] {
            guard !rows.isEmpty else { return [] }
            let more = rows.count - NerdyStuff.cap
            return [title + ":"] + rows.prefix(NerdyStuff.cap).map { "  " + $0 } + (more > 0 ? ["  " + (rest ?? "and \(more) more")] : [])
        }
    }

    /// Sentences the card's template moved out of its explanation (beyond 3), first under What Cool Head saw.
    public var moved: [String] = []
    public var saw: [Reading] = []
    public var lists: [List] = []
    public var verdict: [String] = []
    public var option: [String] = []
    public var identity: [String] = []
    public var did: [String] = []

    public init() {}

    /// Most rows a list shows before its line for the rest.
    public static let cap = 5
    public static let headings = ["What Cool Head saw", "Why this verdict", "Why this option", "What it is", "What Cool Head did"]

    /// The lines the panel shows and copies: each slot under its heading, empty slots left out.
    public func lines() -> [String] {
        let slots: [[String]] = [moved + saw.flatMap(\.lines) + lists.flatMap(\.lines), verdict, option, identity, did]
        return zip(NerdyStuff.headings, slots).flatMap { h, s in s.isEmpty ? [] : [h] + s }
    }

    /// The key readings, for verbose mode's card in place of its explanation: each reading's name and figure, without
    /// its source or check (those stay in Nerdy stuff); then the first three rows of the first list; then what it is
    /// and the rule behind the verdict, named Rule on every card, whether or not its line starts with a name ("Busy:
    /// 0.5 cores or more…", "Shown when…"), so a reading and its rule never share a name.
    /// Readings with the same name (a process writing 3 files) share one row, their figures joined by "; ".
    public func key() -> [(name: String, value: String)] {
        var out: [(name: String, value: String)] = []
        for r in saw {
            let v = r.brief ?? r.value
            if let i = out.firstIndex(where: { $0.name == r.name }) { out[i].value += "; " + v } else { out.append((r.name, v)) }
        }
        if let l = lists.first, !l.rows.isEmpty {
            let title = l.title.replacingOccurrences(of: #"\s*\([^)]*\)$"#, with: "", options: .regularExpression)
            out.append((title, l.rows.prefix(3).map { $0.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression) }.joined(separator: "; ")))
        }
        if let line = identity.first, let r = line.range(of: ": ") { out.append((String(line[..<r.lowerBound]), String(line[r.upperBound...]))) }
        if let rule = verdict.first { out.append(("Rule", rule)) }
        return out
    }

    /// The Mac itself, put before the card's lines when they are copied (for a forum post or an issue), not shown on
    /// each card: what a helper asks first.
    public static func yourMac(_ mac: MacState, now: Date = Date()) -> [String] {
        var out = ["Your Mac", "Model: \(CaseReport.model()), \(mac.cores) cores (\(mac.performanceCores) performance, \(mac.efficiencyCores) efficiency)"]
        let v = ProcessInfo.processInfo.operatingSystemVersionString
        out.append("macOS: \(v)")
        if mac.memoryGB > 0 { out.append(String(format: "Memory: %.0f GB", mac.memoryGB)) }
        let up = ProcessInfo.processInfo.systemUptime
        out.append("Up: " + (up >= 2 * 86400 ? "\(Int(up / 86400)) days, \(Int(up.truncatingRemainder(dividingBy: 86400) / 3600)) hours" : Fmt.duration(up))
                   + ", since \(Fmt.time(now.addingTimeInterval(-up)))")
        if let sp = ThisMac.space() { out.append("Startup disk: \(sp.text)") }
        out.append("Heat: \(mac.thermal) (ProcessInfo.thermalState); memory pressure: \(mac.memoryPressure)")
        return out
    }

    /// A path as a Terminal command takes it: one word whatever its spaces, the home folder as ~ (outside the quotes,
    /// so the shell expands it), a ' inside escaped.
    public static func shellPath(_ p: String) -> String {
        let home = NSHomeDirectory()
        let q = { (s: String) in "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        let p = Redact.text(p)
        return p.hasPrefix(home + "/") ? "~/" + q(String(p.dropFirst(home.count + 1))) : q(p)
    }

    /// Text from a process (a path, a command, a line of its log) as Nerdy stuff shows and copies it: secrets hidden
    /// (see Redact), the home folder as ~.
    public static func shown(_ s: String) -> String { Redact.text(s).replacingOccurrences(of: NSHomeDirectory(), with: "~") }

    // MARK: - Shared slots

    /// Why this option, from the options' own facts, the same for every card: each with who does it, what it does
    /// about the problem, and its Caution; the recommended one with the card's line saying why.
    public static func options(_ c: Card) -> [String] {
        c.fixes.map { f in
            var facts = [f.doer == .coolHead ? "one click" : "you do it", f.impact.lowercased()]
            if f.caution { facts.append("Caution") }
            if f.closesSomething { facts.append("closes something") }
            if f.holdBack { facts.append("never put forward") }
            let head = "\(f.title): " + facts.joined(separator: ", ")
            guard f.recommended else { return head + "." }
            // the card's line, without its subject: "recommended because it helps in one click."
            let why = (c.why ?? "").replacingOccurrences(of: "Cool Head recommends this", with: "")
            return head + "; recommended" + (why.isEmpty || why == "." ? "." : why)
        }
    }

    /// What Cool Head did: this card's lines from Cool Head's log (anonymised as it was written), newest first: those
    /// written about this card's cause (see Watcher.log), not any that mention a name like it.
    public static func did(_ log: [Watcher.LogEntry], about key: String) -> [String] {
        guard !key.isEmpty else { return [] }
        return log.filter { $0.about == key }.suffix(cap).reversed().map { "\(Fmt.time($0.t)) \($0.text)" }
    }

    // MARK: - The Mac as a whole

    /// The Mac-wide readings a card rests on, from MacState, each with its source and a command to check it.
    public enum MacReading { case heat, pressure, swap, moved, disk, battery, power }
    public static func mac(_ s: MacState, _ which: [MacReading], at now: Date) -> [Reading] {
        var out: [Reading] = []
        for w in which {
            switch w {
            case .heat:
                out.append(Reading("Heat", "\(["fair": "warm", "serious": "hot", "critical": "hot"][s.thermal] ?? "normal") (macOS: \(s.thermal))", .thermal, at: now))
            case .pressure:
                out.append(Reading("Memory pressure", s.memoryPressure, .pressure, at: now,
                                   check: "sysctl kern.memorystatus_vm_pressure_level (1 is normal, 2 warning, 4 critical)"))
            case .swap where s.swapTotalMB > 0:
                out.append(Reading("Swap", String(format: "%.1f of %.1f GB", s.swapUsedMB / 1024, s.swapTotalMB / 1024), .swap, at: now, check: "sysctl vm.swapusage"))
            case .moved:
                if let mb = s.swappedOutMB { out.append(Reading("Moved to storage in the last 2 minutes", String(format: "%.0f MB", mb), .swapouts, at: now, check: "vm_stat 120 (pageouts and swapouts are pages; multiply by the page size it prints)")) }
            case .disk:
                if let d = s.diskFreeBytes { out.append(Reading("Startup disk free", MemoryAdvice.diskGB(d), .diskSpace, at: now, check: "df -H /")) }
            case .battery:
                if let b = s.batteryPercent { out.append(Reading("Charge", "\(b)%" + (s.charging ? ", charging" : ""), .battery, at: now, check: "pmset -g batt")) }
            case .power:
                if let w = s.batteryWatts, s.charging { out.append(Reading("Into the battery", String(format: "%.0f W", w), .battery, at: now, check: "ioreg -rn AppleSmartBattery (Voltage in mV times Amperage in mA)")) }
                if let w = s.macWatts { out.append(Reading("The Mac uses", String(format: "%.0f W", w), .battery, at: now)) }
                if let a = s.adapterWatts { out.append(Reading("Charger", "\(a) W", .battery, at: now)) }
            default: break
            }
        }
        return out
    }

    /// A card about the Mac or a part of it, from the facts its family gathered, each "Name: value" a reading from
    /// `source`, with the rule behind the card as its verdict.
    public static func facts(_ lines: [String], source: Source, verdict: [String], card c: Card, now: Date? = nil,
                             before: [Reading] = [], identity: [String] = [], log: [Watcher.LogEntry] = [], key: String = "") -> NerdyStuff {
        var n = NerdyStuff()
        n.moved = c.facts
        n.saw = before + lines.map { l in
            guard let r = l.range(of: ": ") else { return Reading("Note", l, source, at: now) }
            return Reading(String(l[..<r.lowerBound]), String(l[r.upperBound...]), source, at: now)
        }
        n.verdict = verdict
        n.option = options(c)
        n.identity = identity
        n.did = did(log, about: key)
        return n
    }

    // MARK: - Hangs, fast charging, warm with no cause

    /// A stuck process: the busy slots, with how it is stuck first, and the hang's own rule as the verdict.
    public static func hang(_ e: Evidence, card c: Card, kind: Hang.Kind, since: Date, now: Date, threshold: TimeInterval,
                            waiting: [String], log: [Watcher.LogEntry] = []) -> NerdyStuff {
        var n = busy(e, card: c, busySince: nil, now: now, log: log, key: "pid-\(e.pid)")
        n.saw.insert(Reading("Stuck", "\(Hang.words(kind)), since \(Fmt.time(since)), \(Fmt.duration(now.timeIntervalSince(since)))",
                             kind == .notResponding ? .unresponsive : .psState, at: now,
                             check: kind == .notResponding ? nil : "ps -o pid,stat,command -p \(e.pid)"), at: 0)
        if !waiting.isEmpty { n.lists.append(List("Programs it started, waiting on it (\(Source.taskInfo.rawValue))", waiting)) }
        let how: String
        switch kind {
        case .paused: how = "paused (ps state T)"
        case .diskWait: how = "waiting on a drive (ps state U)"
        case .notResponding: how = "marked Not Responding by macOS"
        }
        // the hang's own rule, not the busy rule or the catalogue's usual time, which are about work, not a hang
        n.verdict = ["Stuck: \(how) for \(Fmt.duration(threshold)) or more before a card shows."] + n.verdict.filter { $0.hasPrefix("Card:") || $0.hasPrefix("Won on:") }
        return n
    }

    /// Fast charging adding heat.
    public static func charging(_ s: MacState, card c: Card, now: Date, log: [Watcher.LogEntry] = [], key: String = "") -> NerdyStuff {
        facts([], source: .battery, verdict: ["Fast charging: more than 15 W into the battery while macOS says warm or hotter."],
              card: c, before: mac(s, [.heat, .battery, .power], at: now), log: log, key: key)
    }

    /// Warm with no single cause, with the busiest programs, by cores, as name and cores.
    public static func warm(_ s: MacState, card c: Card, busiest: [(String, Double)], now: Date, log: [Watcher.LogEntry] = [], key: String = "") -> NerdyStuff {
        var n = facts([], source: .thermal, verdict: ["Warm with no single cause: macOS says warm or hotter, and no busy program or fast charging explains it."],
                      card: c, before: mac(s, [.heat, .pressure, .moved, .battery, .power], at: now), log: log, key: key)
        if !busiest.isEmpty { n.lists.append(List("Busiest, by cores (\(Source.coolHead.rawValue))", busiest.map { String(format: "%.2f  %@", $0.1, $0.0) })) }
        return n
    }

    // MARK: - The energy week

    /// The Power page's Nerdy stuff: every app's share, five shown with the rest totalled (copying copies all of them).
    public static func energy(_ rows: [String], shares: [Double]) -> NerdyStuff {
        var n = NerdyStuff()
        let past = shares.dropFirst(cap).reduce(0, +)
        n.lists = [List("Energy this week, by app or program (\(Source.powerlog.rawValue))", rows,
                        rest: "and \(max(0, rows.count - cap)) more, \(PowerHistory.share(past)) in total")]
        n.verdict = ["On the list above: the top three, then each whose share shows as \(Int(PowerHistory.moreFloor))% or more of the week's energy. Copying copies every one."]
        return n
    }

    // MARK: - Memory

    /// The memory card's Nerdy stuff: macOS's readings, the biggest users by footprint (five, then the rest totalled),
    /// and the rule that makes memory tight.
    public static func memory(_ groups: [MemGroup], mac s: MacState, card c: Card, now: Date, log: [Watcher.LogEntry] = [], key: String = "") -> NerdyStuff {
        var n = facts([], source: .pressure, verdict: [
            "Tight: macOS says warning or critical, or it moved \(Int(MemoryAdvice.heavySwapMB)) MB or more to storage in 2 minutes while it says normal.",
            "On the card: \(Int(MemoryAdvice.movingSwapMB)) MB or more moved in 2 minutes; less than \(MemoryAdvice.diskGB(MemoryAdvice.lowDiskBytes)) free on the startup disk."],
            card: c, now: now,
            before: mac(s, [.pressure, .moved, .swap, .disk], at: now)
                + (s.memoryGB > 0 ? [Reading("Installed memory", String(format: "%.0f GB", s.memoryGB), .physicalMemory)] : []),
            log: log, key: key)
        let sorted = groups.sorted { $0.bytes > $1.bytes }
        let rest = sorted.dropFirst(cap)
        n.lists.append(List("Biggest, by footprint (\(Source.appsMemory.rawValue); 1 GB is 1,024 MB, as Activity Monitor counts)",
                            sorted.map { "\(Fmt.bytes($0.bytes))  \($0.name)" + ($0.count > 1 ? ", \($0.count) processes" : "") },
                            rest: "and \(rest.count) more, \(Fmt.bytes(rest.reduce(0) { $0 + $1.bytes })) in total"))
        return n
    }

    // MARK: - Busy apps and jobs

    /// A busy process's Nerdy stuff, from what Cool Head gathered about it (see Evidence).
    /// `alsoBusy`: the other busiest processes by cores, biggest first, as name and cores.
    public static func busy(_ e: Evidence, card c: Card, busySince: Date?, now: Date, alsoBusy: [(String, Double)] = [],
                            log: [Watcher.LogEntry] = [], key: String = "") -> NerdyStuff {
        var n = NerdyStuff()
        n.moved = c.facts
        // CPU: Cool Head's own running average for the user's processes; ps's for others (macOS doesn't let an app read
        // another user's usage directly)
        let pct = Int((e.coresNow * 100).rounded())
        n.saw.append(Reading("CPU", String(format: "%.2f cores (%d%% in Activity Monitor), ", e.coresNow, pct)
                                    + (e.mine ? "a running average of readings every 10 seconds" : "ps's recent average"),
                             e.mine ? .rusage : .ps, at: now, check: "top -l 2 -pid \(e.pid) -stats pid,command,cpu"))
        n.saw[n.saw.count - 1].brief = String(format: "%.2f cores (%d%% in Activity Monitor)", e.coresNow, pct)
        if e.memoryBytes > 0 { n.saw.append(Reading("Memory (footprint)", Fmt.bytes(e.memoryBytes), .rusage, at: now)) }
        if let g = e.gpuShare { n.saw.append(Reading("Graphics chip", "\(Int((g * 100).rounded()))% of its time", .gpu, at: now)) }
        if let s = busySince {
            n.saw.append(Reading("Busy since", "\(Fmt.time(s)), \(Fmt.duration(now.timeIntervalSince(s)))", .coolHead))
        }
        if let p = e.progress {
            n.saw.append(Reading("Progress", shown(p.line), .ownFile, at: p.lineTime,
                                 check: "tail -n 20 \(shellPath(p.file))"))
        }
        for w in e.writing.prefix(3) { n.saw.append(Reading("Writing", shown(w), .openFiles)) }
        if !alsoBusy.isEmpty {
            n.lists.append(List("Also busy, by cores (\(Source.coolHead.rawValue))", alsoBusy.map { String(format: "%.2f  %@", $0.1, $0.0) }))
        }
        // the rule behind the verdict, then what the card made of it, and which kind of card won
        n.verdict.append("Busy: 0.5 cores or more, or \(Int((GPU.busyShare * 100).rounded()))% of the graphics chip, for \(Int(Watcher.busyMinute)) seconds before a card shows.")
        // a known macOS process: how long it usually takes, and where that comes from
        if let k = Pattern.match(name: e.name, path: e.path, pid: e.pid) {
            n.verdict.append("Usually: under \(Fmt.duration(k.usualHours * 3600)), from Cool Head's catalogue (\(k.source)).")
        }
        // which kind of card won, its score, and the factor that put it ahead of the closest
        if let ch = c.choice {
            n.verdict.append("Card: \(ch.winner)" + (ch.scores[ch.winner].map { " (\($0.text))" } ?? "")
                             + (ch.others.isEmpty ? "." : "; also fitted: \(Fmt.list(ch.others))."))
            if let b = ch.because { n.verdict.append("Won on: \(b.kind).") }
        }
        n.option = options(c)
        n.identity.append("Process: \(e.name), PID \(e.pid)" + (e.mine ? "" : ", another user's"))
        if let p = e.path { n.identity.append("Path: \(shown(p))") }
        if !e.args.isEmpty { n.identity.append("Command: \(shown(Redact.args(e.args).joined(separator: " "))) (\(Source.procArgs.rawValue))") }
        n.identity.append("Started by: \(e.startedBy)")
        if let l = e.launchCommand { n.identity.append("Launched as: \(shown(l))") }
        if let s = e.start { n.identity.append("Started: \(Fmt.time(s)), \(Fmt.duration(now.timeIntervalSince(s))) ago (\(Source.taskInfo.rawValue))") }
        if let d = e.cwd, d != "/" { n.identity.append("Folder: \(shown(d))") }
        for l in e.locks.prefix(2) { n.identity.append("Lock: \((l.path as NSString).lastPathComponent)" + (l.note.map { ", \(shown($0))" } ?? "")) }
        n.did = did(log, about: key)
        return n
    }
}
