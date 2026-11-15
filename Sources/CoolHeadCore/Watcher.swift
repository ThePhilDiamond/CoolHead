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
    /// What a report may call this card's process: anonymised as in the case report.
    public var reportSubject = "the Mac as a whole"
    /// The anonymised case report, for cards that offer "Share this case".
    public var report: (title: String, body: String)? = nil
    /// True for cards that should notify when they last: stalled, or busy with no explanation.
    public var needsLook: Bool { card.state == .stalled || card.state == .unknown }
    /// What the card is about, whatever its state: the process, or the Mac-wide condition.
    public var cause: String { pid.map { "pid-\($0)" } ?? id }
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
    public private(set) var snoozed: [String: Date] = [:]
    /// Cool Head's own recent activity, for "Report a problem": which cards appeared and cleared, which buttons
    /// were pressed and what happened. Anonymised as it is written, kept in memory only, never on disk, and
    /// limited to the last 6 hours.
    public private(set) var activity: [LogEntry] = []
    public struct LogEntry { public let t: Date; public let text: String }
    /// Set to open the "Report a problem" form (from the bottom row, the right-click menu, or after a fix).
    public var showReport = false
    /// Processes put on background priority by "Run it cooler", by process number and start time.
    public private(set) var cooled: Set<String> = []
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
        snoozed[card.cause] = until
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
    public enum Outcome { case done, gone, failed(String) }

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
        return ok ? .done : .failed(why)
    }

    public func isCooled(_ c: LiveCard) -> Bool { cooled.contains(Watcher.key(c)) }

    /// Background priority on or off; checks macOS accepted it by reading it back.
    public func setCooler(_ c: LiveCard, on: Bool) -> Outcome {
        guard let p = c.pid, sameProcess(c) else { log("Run it cooler pressed for \(c.reportSubject): it had already gone"); return .gone }
        guard setpriority(4 /* PRIO_DARWIN_PROCESS */, id_t(p), on ? 0x1000 /* PRIO_DARWIN_BG */ : 0) == 0 else {
            return .failed(String(cString: strerror(errno)))
        }
        errno = 0
        let now = getpriority(4, id_t(p))
        guard errno == 0, (now == 0x1000) == on else { return .failed("macOS didn't apply it") }
        if on { cooled.insert(Watcher.key(c)) } else { cooled.remove(Watcher.key(c)) }
        log((on ? "Run it cooler" : "Back to full speed") + " pressed for \(c.reportSubject): applied")
        return .done
    }

    static func key(_ c: LiveCard) -> String { "\(c.pid ?? 0)-\(c.start?.timeIntervalSince1970 ?? 0)" }

    public var needsLook: Bool { level != .good }

    /// What the menu bar shows, by shape and colour, so it reads without relying on colour alone:
    /// a green circle when all is well, a yellow triangle when something needs a look, a red octagon for a problem.
    public enum Level { case good, warning, issue }
    public var level: Level {
        if cards.contains(where: { $0.card.state == .stalled }) || mac.thermal == "serious" || mac.thermal == "critical"
            || mac.memoryPressure == "critical" { return .issue }
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
                headline: "The battery is fast-charging at about \(Int(w.rounded())) W, which adds heat.",
                explanation: "Charging is fastest when the battery is low and slows once it passes about 80%. The Mac itself is using \(s.macWatts.map { "\(Int($0.rounded())) W" } ?? "less").",
                fixes: [Card.wait(until: nil, now: now, recommended: true),
                        Fix(id: "unplug", title: "Unplug for a while if the heat bothers you", consequence: "The battery stops charging; plug back in later.", kind: .info)]),
                details: s.lines(), reportSubject: "fast charging adding heat"))
        }
        if s.memoryPressure == "warning" || s.memoryPressure == "critical" {
            let top = tracks.max { $0.value.footprint < $1.value.footprint }
            var who = "One process"
            var size = ""
            var quit: Fix?
            if let (pid, tr) = top, let e = Evidence.gather(pid: pid, measured: (tr.cores, 0)) {
                who = Card.subject(e)
                size = Fmt.bytes(tr.footprint)
                // Quit only the main program of a real app; a catalogue entry's risk (Docker stops its containers)
                // is the consequence, and then it isn't recommended
                if let bundle = e.quittableBundle, let app = e.quittableApp {
                    let risk = Pattern.match(name: e.name, path: e.path)?.risk
                    quit = Fix(id: "quit", title: "Quit \(app)", consequence: risk ?? "It quits normally and asks you to save anything open.",
                               kind: .quitApp(bundle), recommended: risk == nil)
                }
            }
            var fixes = [Card.wait(until: nil, now: now, recommended: !(quit?.recommended ?? false))]
            if let q = quit { fixes.append(q) }
            out.append(LiveCard(id: "memory-\(s.memoryPressure)", pid: nil, card: Card(
                state: .unknown,
                headline: "Memory is \(s.memoryPressure == "critical" ? "very " : "")tight. \(who) is using the most, \(size).",
                explanation: String(format: "macOS reports memory pressure as %@, and %.1f GB of %.1f GB of swap is in use, so it is moving memory to the disk, which slows everything down.", s.memoryPressure, s.swapUsedMB / 1024, s.swapTotalMB / 1024),
                fixes: fixes), details: s.lines(), reportSubject: "memory running short (\(s.memoryPressure))"))
        }
        return out
    }

    private func publish(_ state: MacState, _ live: [LiveCard], own: Double) {
        let now = Date()
        DispatchQueue.main.async { [self] in
            mac = state
            overhead = own
            snoozed = snoozed.filter { $0.value > now }
            let before = Dictionary(cards.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            let after = Dictionary(live.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            for (id, c) in after where before[id] == nil && seenIDs.insert(id).inserted {
                log(c.pid == nil ? "Card: \(c.reportSubject)" : "Card: \(c.reportSubject), \(CaseReport.stateWords(c.card.state))")
            }
            for (id, c) in before where after[id] == nil && !live.contains(where: { $0.cause == c.cause }) {
                log("Cleared: \(c.reportSubject)"); seenIDs.remove(id)
            }
            cards = live.filter { !dismissed.contains($0.id) && snoozed[$0.cause] == nil }
            // notify once for a card that has needed a look for 10 minutes; forget cards that went away
            let ids = Set(live.filter(\.needsLook).map(\.id))
            for c in live where c.needsLook {
                if firstSeen[c.id] == nil { firstSeen[c.id] = now }
                if !alerted.contains(c.id), now.timeIntervalSince(firstSeen[c.id]!) >= 600, !dismissed.contains(c.id), snoozed[c.cause] == nil {
                    alerted.insert(c.id)
                    onAlert?(c)
                }
            }
            firstSeen = firstSeen.filter { ids.contains($0.key) }
            alerted = alerted.filter { ids.contains($0) }
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
