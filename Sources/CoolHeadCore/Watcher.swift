import Darwin
import Foundation
import Observation

/// A card on screen, with the facts behind it.
public struct LiveCard: Identifiable {
    public let id: String
    public let pid: pid_t?
    /// The process's start time, to check it is still the same process before acting on it.
    public var start: Date? = nil
    public let card: Card
    public let details: [String]
    /// What the panel calls this card's process ("Your Photo Export job export.py", "WhatsApp").
    public var displaySubject = ""
    /// What a report may call this card's process: anonymised as in the case report.
    public var reportSubject = "the Mac as a whole"
    /// The anonymised case report, for cards that offer "Share this case".
    public var report: (title: String, body: String)? = nil
    /// True for cards that should notify when they last: stalled, or busy with no explanation.
    public var needsLook: Bool { card.state == .stalled || card.state == .unknown }
    /// What the card is about, whatever its state: the process, or the Mac-wide condition.
    public var cause: String { causeKey ?? pid.map { "pid-\($0)" } ?? id }
    /// Overrides the cause, so a card keeps one identity as it changes (the memory card, warning or critical).
    public var causeKey: String? = nil
    /// How bad it is, to tell whether a card the person chose to wait on has got meaningfully worse:
    /// 2 for stuck or critical memory, 1 for something that needs a look, 0 otherwise.
    public var severity: Int {
        if card.state == .stalled || id.hasPrefix("memory-critical") { return 2 }
        return needsLook ? 1 : 0
    }
}

/// Samples every process on a timer and turns sustained load into cards.
/// Nothing is written to disk: what it needs while running stays in memory and is gone when it quits.
@Observable
public final class Watcher {
    public static let shared = Watcher()

    public private(set) var cards: [LiveCard] = []
    public private(set) var mac = MacState()
    /// Share of the whole Mac that Cool Head itself used over the last tick.
    public private(set) var overhead: Double = 0
    public private(set) var dismissed: Set<String> = []
    /// Cards put off until a time, by their cause (a process, or a Mac-wide condition).
    /// Each waited-on cause: until when, and how bad it was when the person chose to wait.
    public private(set) var snoozed: [String: (until: Date, severity: Int)] = [:]
    /// Cool Head's own recent activity, for "Report a problem": which cards appeared and cleared, which buttons
    /// were pressed and what happened. Anonymised as it is written, kept in memory only, never on disk, and
    /// limited to the last 6 hours.
    public private(set) var activity: [LogEntry] = []
    public struct LogEntry { public let t: Date; public let text: String }
    /// Set to open the "Report a problem" form (from the bottom row, the right-click menu, or after a fix).
    public var showReport = false
    /// Processes put on background priority by "Run it cooler", by process number and start time.
    public private(set) var cooled: [String: CooledItem] = [:]
    /// A process running at background priority because the person chose "Run it cooler": pinned at the top of
    /// the panel until it ends or they set it back.
    public struct CooledItem: Identifiable {
        public var id: String { key }
        public let key: String
        public let pid: pid_t
        public let start: Date?
        public let name: String
        public let reportSubject: String
        public let since: Date
        public let before: Int?
        public let after: Int?
    }
    public var cooledList: [CooledItem] { cooled.values.sorted { $0.since < $1.since } }
    /// Called on the main thread when a card has needed a look for 10 minutes, once per card.
    @ObservationIgnored public var onAlert: ((LiveCard) -> Void)?
    /// Called on the main thread after every update.
    @ObservationIgnored public var onPublish: (() -> Void)?

    @ObservationIgnored public var interval: TimeInterval = 10
    @ObservationIgnored private var tracks: [pid_t: Track] = [:]
    @ObservationIgnored private var lastTick: Date?
    @ObservationIgnored private var firstSeen: [String: Date] = [:]
    @ObservationIgnored private var alerted: Set<String> = []
    @ObservationIgnored private var seenIDs: Set<String> = []
    @ObservationIgnored private var lastPriority: [pid_t: Int] = [:]
    @ObservationIgnored private let queue = DispatchQueue(label: "coolhead.watcher", qos: .utility)
    @ObservationIgnored private var timer: DispatchSourceTimer?

    struct Track {
        var cpu: Double            // CPU seconds at the last tick
        var written: UInt64
        var cores = 0.0            // smoothed cores in use
        var lastWritten: UInt64 = 0
        var busySince: Date?
        var footprint: UInt64 = 0
    }

    public init() {}

    public func start() {
        guard timer == nil else { return }
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: interval, leeway: .seconds(2))
        t.setEventHandler { [weak self] in self?.tick() }
        timer = t
        t.resume()
    }

    public func dismiss(_ id: String) {
        dismissed.insert(id)
        cards.removeAll { $0.id == id }
    }

    /// Hides a card until a time; it comes back then if its cause is still there.
    public func snooze(_ card: LiveCard, until: Date) {
        log("Chose to wait on \(card.reportSubject) until \(Fmt.clock(until))")
        snoozed[card.cause] = (until, card.severity)
        cards.removeAll { $0.cause == card.cause }
    }

    /// Adds to the activity log. `text` must already be anonymised (use `reportSubject`, never paths or names).
    public func log(_ text: String) {
        let now = Date()
        let add = { [self] in
            activity.append(LogEntry(t: now, text: text))
            activity.removeAll { now.timeIntervalSince($0.t) > 6 * 3600 }
            if activity.count > 300 { activity.removeFirst(activity.count - 300) }
        }
        if Thread.isMainThread { add() } else { DispatchQueue.main.async(execute: add) }
    }

    /// The result of acting on a card, to show the person.
    /// The result of acting on a card, with a sentence saying what changed when it worked.
    public enum Outcome { case done(String), gone, failed(String) }

    /// True if this process number still belongs to the process the card was about (numbers are reused).
    func sameProcess(_ c: LiveCard) -> Bool {
        guard let p = c.pid, let b = Proc.bsd(p) else { return false }
        guard let s = c.start else { return true }
        return abs(b.start.timeIntervalSince(s)) < 1
    }

    public func stop(_ c: LiveCard) -> Outcome {
        guard let p = c.pid, sameProcess(c) else { log("Stop pressed for \(c.reportSubject): it had already gone"); return .gone }
        let ok = kill(p, SIGTERM) == 0
        let why = ok ? "" : String(cString: strerror(errno))
        log("Stop pressed for \(c.reportSubject): " + (ok ? "stopped" : "failed (\(why))"))
        return ok ? .done("Stopped \(c.displaySubject.isEmpty ? "it" : c.displaySubject).") : .failed(why)
    }

    public func isCooled(_ c: LiveCard) -> Bool { cooled[Watcher.key(c)] != nil }

    /// "Back to full speed" from a pinned item.
    public func restore(_ item: CooledItem) -> Outcome {
        var c = LiveCard(id: "pinned", pid: item.pid, start: item.start,
                         card: Card(state: .working, headline: "", explanation: "", fixes: []), details: [], reportSubject: item.reportSubject)
        c.displaySubject = item.name
        return setCooler(c, on: false)
    }

    /// Background priority on or off; checks macOS accepted it by reading it back.
    public func setCooler(_ c: LiveCard, on: Bool) -> Outcome {
        let what = on ? "Run it cooler" : "Back to full speed"
        guard let p = c.pid, sameProcess(c) else { log("\(what) pressed for \(c.reportSubject): it had already gone"); return .gone }
        guard setpriority(4 /* PRIO_DARWIN_PROCESS */, id_t(p), on ? 0x1000 /* PRIO_DARWIN_BG */ : 0) == 0 else {
            let why = String(cString: strerror(errno))
            log("\(what) pressed for \(c.reportSubject): failed (\(why))")
            return .failed(why)
        }
        // confirm by its scheduling priority: the background band is 4 (getpriority can't report this setting for
        // another process, so it isn't used). macOS may take a moment to move it, so look twice.
        var pri: Int?
        let before = cooled[Watcher.key(c)]?.before ?? lastPriority[p]
        if let first = Proc.schedulingPriority(p) {
            var pri0 = first
            defer { pri = pri0 }
            if (pri0 <= 4) != on { usleep(300_000); pri0 = Proc.schedulingPriority(p) ?? pri0 }
            guard (pri0 <= 4) == on else {
                log("\(what) pressed for \(c.reportSubject): set, but its priority stayed at \(pri0)")
                return .failed("macOS accepted it, but the process's priority didn't change (\(pri0))")
            }
        }
        let name = c.displaySubject.isEmpty ? "It" : c.displaySubject
        log("\(what) pressed for \(c.reportSubject): applied")
        if on {
            cooled[Watcher.key(c)] = CooledItem(key: Watcher.key(c), pid: p, start: c.start, name: name, reportSubject: c.reportSubject,
                                                since: Date(), before: before, after: pri)
            let change = (before != nil && pri != nil) ? " (priority \(before!) → \(pri!))" : ""
            return .done("Done. \(name) is running cooler\(change). It's pinned at the top.")
        }
        cooled.removeValue(forKey: Watcher.key(c))
        return .done("\(name) is back to full speed.")
    }

    static func key(_ c: LiveCard) -> String { "\(c.pid ?? 0)-\(c.start?.timeIntervalSince1970 ?? 0)" }

    public var needsLook: Bool { level != .good }

    /// What the menu bar shows, by shape and colour, so it reads without relying on colour alone:
    /// a green circle when all is well, a yellow triangle when something needs a look, a red octagon for a problem.
    public enum Level { case good, warning, issue }
    public var level: Level {
        if cards.contains(where: { $0.severity >= 2 }) || mac.thermal == "serious" || mac.thermal == "critical" { return .issue }
        if cards.contains(where: { $0.needsLook }) { return .warning }
        return .good
    }

    // MARK: - Sampling

    private func tick() {
        let now = Date()
        let dt = lastTick.map { now.timeIntervalSince($0) } ?? 0
        lastTick = now
        let me = getpid()
        var seen = Set<pid_t>()
        var own = 0.0
        var unreadable: [pid_t] = []
        for pid in Proc.allPIDs() {
            guard let u = Proc.usage(pid) else { unreadable.append(pid); continue }
            seen.insert(pid)
            var tr = tracks[pid] ?? Track(cpu: u.cpuSeconds, written: u.diskWritten)
            if dt > 0 {
                let c = max(0, u.cpuSeconds - tr.cpu) / dt
                tr.cores = tr.cores == 0 ? c : 0.5 * tr.cores + 0.5 * c
                tr.lastWritten = u.diskWritten &- tr.written
                if pid == me { own = c }
            }
            tr.cpu = u.cpuSeconds
            tr.written = u.diskWritten
            tr.footprint = u.footprint
            if tr.cores >= 0.5 { tr.busySince = tr.busySince ?? now } else if tr.cores < 0.25 { tr.busySince = nil }
            tracks[pid] = tr
        }
        // processes owned by other users (root, _mds_stores, _windowserver): macOS doesn't let us read their usage
        // directly, but ps can; its figure is a recent average, which is what a lasting load needs
        if !unreadable.isEmpty {
            let ps = Proc.psCPU()
            for pid in unreadable {
                guard let pc = ps[pid] else { continue }
                seen.insert(pid)
                var tr = tracks[pid] ?? Track(cpu: 0, written: 0)
                tr.cores = pc / 100
                if tr.cores >= 0.5 { tr.busySince = tr.busySince ?? now } else if tr.cores < 0.25 { tr.busySince = nil }
                tracks[pid] = tr
            }
        }
        tracks = tracks.filter { seen.contains($0.key) }
        let state = MacState.read()
        guard dt > 0 else { publish(state, [], own: 0); return }

        let warm = state.thermal != "nominal"
        let busy = tracks.filter { $0.key != me && $0.value.cores >= 0.5 && now.timeIntervalSince($0.value.busySince ?? now) >= 60 }
            .sorted { $0.value.cores > $1.value.cores }.prefix(5)
        var live: [LiveCard] = []
        for (pid, tr) in busy {
            guard let e = Evidence.gather(pid: pid, measured: (tr.cores, tr.lastWritten)) else { continue }
            let c = Card.make(e, now: now, busySince: tr.busySince, warm: warm)
            guard c.state != .quiet else { continue }
            var lc = LiveCard(id: "\(pid)-\(c.state.rawValue)", pid: pid, start: e.start, card: c, details: e.lines())
            lc.reportSubject = CaseReport.subject(e)
            lc.displaySubject = Card.subject(e)
            if let pr = Proc.schedulingPriority(pid), pr > 4 { lastPriority[pid] = pr }
            if c.fixes.contains(where: { $0.kind == .share }) {
                lc.report = (CaseReport.title(e, card: c), CaseReport.make(e, card: c, mac: state, busySince: tr.busySince, now: now))
            }
            live.append(lc)
        }
        live += macCards(state, now: now)
        if ProcessInfo.processInfo.environment["COOLHEAD_DEBUG"] != nil {
            let top = tracks.sorted { $0.value.cores > $1.value.cores }.prefix(3)
                .map { "\($0.key):\(String(format: "%.2f", $0.value.cores)) since \($0.value.busySince.map { Int(now.timeIntervalSince($0)) } ?? -1)s" }
            FileHandle.standardError.write("tick busy=\(busy.count) cards=\(live.map { $0.card.headline.prefix(50) }) top=\(top)\n".data(using: .utf8)!)
        }

        publish(state, live, own: own / Double(max(1, state.cores)))
    }

    /// Cards about the Mac as a whole, which no single process explains.
    private func macCards(_ s: MacState, now: Date) -> [LiveCard] {
        var out: [LiveCard] = []
        if s.charging, let w = s.batteryWatts, w > 15, s.thermal != "nominal" {
            out.append(LiveCard(id: "charging", pid: nil, card: Card(
                state: .working,
                headline: "Fast charging is adding heat.",
                explanation: "It's charging at about \(Int(w.rounded())) W. That slows down after 80%.",
                fixes: [Card.wait(until: nil, now: now, recommended: true),
                        Fix(id: "unplug", title: "Unplug for a bit", consequence: "Charging stops until you plug back in.", kind: .info)]),
                details: s.lines(), reportSubject: "fast charging adding heat"))
        }
        if s.memoryPressure == "warning" || s.memoryPressure == "critical" {
            // count memory the way a person thinks of it: each app with all its helpers, each job on its own
            var groups = MemoryAdvice.merge(tracks.compactMap { pid, tr in
                MemoryAdvice.group(pid: pid, path: Proc.path(pid), args: Proc.args(pid), footprint: tr.footprint)
            })
            for i in groups.indices.prefix(3) where groups[i].kind == .job {
                if let p = groups[i].pid { groups[i].evidence = Evidence.gather(pid: p, measured: (tracks[p]?.cores ?? 0, 0)) }
            }
            let card = MemoryAdvice.card(groups, mac: s, now: now)
            let top = groups.first
            let subject = top.map { g -> String in
                if let e = g.evidence { return "memory running short (\(s.memoryPressure)); most used by \(CaseReport.subject(e))" }
                return "memory running short (\(s.memoryPressure)); most used by " + (g.kind == .macOS || g.bundle != nil ? g.name : "a program (its name is withheld)")
            } ?? "memory running short (\(s.memoryPressure))"
            var mc = LiveCard(id: "memory-\(s.memoryPressure)", pid: top?.kind == .job ? top?.pid : nil,
                              start: top?.kind == .job ? top?.evidence?.start : nil,
                              card: card, details: s.lines(), reportSubject: subject)
            mc.causeKey = "memory"
            if let e = top?.evidence { mc.displaySubject = Card.subject(e) }
            out.append(mc)
        }
        return out
    }

    private func publish(_ state: MacState, _ live: [LiveCard], own: Double) {
        let now = Date()
        DispatchQueue.main.async { [self] in
            mac = state
            overhead = own
            snoozed = snoozed.filter { $0.value.until > now }
            // a waited-on card stays hidden (and the badge green) until its time, unless it gets meaningfully worse
            func waitingOn(_ c: LiveCard) -> Bool { snoozed[c.cause].map { c.severity <= $0.severity } ?? false }
            let before = Dictionary(cards.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            let after = Dictionary(live.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            for (id, c) in after where before[id] == nil && seenIDs.insert(id).inserted {
                log(c.pid == nil ? "Card: \(c.reportSubject)" : "Card: \(c.reportSubject), \(CaseReport.stateWords(c.card.state))")
            }
            for (id, c) in before where after[id] == nil && !live.contains(where: { $0.cause == c.cause }) {
                log("Cleared: \(c.reportSubject)"); seenIDs.remove(id)
            }
            cards = live.filter { !dismissed.contains($0.id) && !waitingOn($0) }
            // notify once for a card that has needed a look for 10 minutes; forget cards that went away
            let ids = Set(live.filter(\.needsLook).map(\.id))
            for c in live where c.needsLook {
                if firstSeen[c.id] == nil { firstSeen[c.id] = now }
                if !alerted.contains(c.id), now.timeIntervalSince(firstSeen[c.id]!) >= 600, !dismissed.contains(c.id), !waitingOn(c) {
                    alerted.insert(c.id)
                    onAlert?(c)
                }
            }
            firstSeen = firstSeen.filter { ids.contains($0.key) }
            alerted = alerted.filter { ids.contains($0) }
            // a pinned (cooled) process that has ended is unpinned
            for (k, item) in cooled {
                let alive = Proc.bsd(item.pid).map { b in item.start.map { abs(b.start.timeIntervalSince($0)) < 1 } ?? true } ?? false
                if !alive { cooled.removeValue(forKey: k); log("\(item.reportSubject) finished while running cooler") }
            }
            onPublish?()
        }
    }
}

extension Evidence {
    /// The facts behind a card, one plain line each, for the card's details.
    public func lines() -> [String] {
        var out: [String] = []
        out.append("Process: \(name), number \(pid)")
        if !args.isEmpty { out.append("Command: \(Redact.args(args).joined(separator: " "))") }
        out.append("Started by: \(startedBy)")
        if let c = launchCommand { out.append("Launched as: \(Redact.text(c))") }
        if let d = cwd, d != "/" { out.append("Folder: \(d)") }
        if let s = start { out.append("Started: \(Fmt.time(s)), \(Fmt.duration(Date().timeIntervalSince(s))) ago") }
        out.append("CPU: \(Fmt.cores(coresNow)) now; memory \(Fmt.bytes(memoryBytes))")
        for w in writing.prefix(3) { out.append("Writing: \(w)") }
        if let p = progress { out.append("Progress: \(p.line) (written \(Fmt.time(p.lineTime)))") }
        for l in locks.prefix(2) { out.append("Lock: \((l.path as NSString).lastPathComponent)" + (l.note.map { ", \($0)" } ?? "")) }
        return out
    }
}

extension MacState {
    public func lines() -> [String] {
        var out = ["Heat: \(thermal)", "Memory pressure: \(memoryPressure)"]
        if swapTotalMB > 0 { out.append(String(format: "Swap: %.1f of %.1f GB", swapUsedMB / 1024, swapTotalMB / 1024)) }
        if let b = batteryPercent { out.append("Battery: \(b)%" + (charging ? ", charging" : "")) }
        if let w = batteryWatts, charging { out.append(String(format: "Battery taking %.0f W", w)) }
        if let w = macWatts { out.append(String(format: "Mac using %.0f W", w)) }
        if let a = adapterWatts { out.append("Charger: \(a) W") }
        return out
    }
}

/// Hides values that look like secrets (tokens, keys, passwords, credentials in URLs) wherever command lines are
/// shown, so they aren't copied into an issue by accident.
public enum Redact {
    static let secretFlag = try! NSRegularExpression(
        pattern: #"((?:^|[\s-])(?:[\w.-]*(?:token|key|secret|password|passwd|pwd|auth|bearer|credential|apikey)[\w.-]*)[=:])\S+"#,
        options: [.caseInsensitive])
    static let urlCredential = try! NSRegularExpression(pattern: #"(://[^/\s:@]+:)[^@\s/]+@"#)

    public static func text(_ s: String) -> String {
        var t = secretFlag.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "$1[hidden]")
        t = urlCredential.stringByReplacingMatches(in: t, range: NSRange(t.startIndex..., in: t), withTemplate: "$1[hidden]@")
        return t
    }

    /// Also hides the value after a bare secret flag: --token abc123
    public static func args(_ a: [String]) -> [String] {
        var out: [String] = []
        var hideNext = false
        for x in a {
            if hideNext { out.append("[hidden]"); hideNext = false; continue }
            let bare = x.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "-"))
            if x.hasPrefix("-") && !x.contains("=") && ["token", "key", "secret", "password", "passwd", "pwd", "auth", "bearer", "apikey", "api-key"].contains(where: { bare.hasSuffix($0) }) {
                hideNext = true
            }
            out.append(text(x))
        }
        return out
    }
}
