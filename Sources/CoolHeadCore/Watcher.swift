import Darwin
import Foundation
import Observation

/// A card on screen, with the facts behind it.
public struct LiveCard: Identifiable {
    public let id: String
    public let pid: pid_t?
    public let card: Card
    public let details: [String]
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
    /// Called on the main thread when a card has needed a look for 10 minutes, once per card.
    @ObservationIgnored public var onAlert: ((LiveCard) -> Void)?

    @ObservationIgnored public var interval: TimeInterval = 10
    @ObservationIgnored private var tracks: [pid_t: Track] = [:]
    @ObservationIgnored private var lastTick: Date?
    @ObservationIgnored private var firstSeen: [String: Date] = [:]
    @ObservationIgnored private var alerted: Set<String> = []
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
        snoozed[card.cause] = until
        cards.removeAll { $0.cause == card.cause }
    }

    public var needsLook: Bool { cards.contains { $0.needsLook } || mac.thermal == "serious" || mac.thermal == "critical" }

    // MARK: - Sampling

    private func tick() {
        let now = Date()
        let dt = lastTick.map { now.timeIntervalSince($0) } ?? 0
        lastTick = now
        let me = getpid()
        var seen = Set<pid_t>()
        var own = 0.0
        for pid in Proc.allPIDs() {
            guard let u = Proc.usage(pid) else { continue }
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
            live.append(LiveCard(id: "\(pid)-\(c.state.rawValue)", pid: pid, card: c, details: e.lines()))
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
                details: s.lines()))
        }
        if s.memoryPressure == "warning" || s.memoryPressure == "critical" {
            let top = tracks.max { $0.value.footprint < $1.value.footprint }
            var who = "One process"
            var size = ""
            var app: String?
            if let (pid, tr) = top, let e = Evidence.gather(pid: pid, measured: (tr.cores, 0)) {
                who = Card.subject(e)
                size = Fmt.bytes(tr.footprint)
                app = e.quittableApp
            }
            var fixes = [Card.wait(until: nil, now: now, recommended: app == nil)]
            if let a = app {
                fixes.append(Fix(id: "quit", title: "Quit \(a)", consequence: "It quits normally and asks you to save anything open.", kind: .quitApp(a), recommended: true))
            }
            out.append(LiveCard(id: "memory-\(s.memoryPressure)", pid: nil, card: Card(
                state: .unknown,
                headline: "Memory is \(s.memoryPressure == "critical" ? "very " : "")tight. \(who) is using the most, \(size).",
                explanation: String(format: "macOS reports memory pressure as %@, and %.1f GB of %.1f GB of swap is in use, so it is moving memory to the disk, which slows everything down.", s.memoryPressure, s.swapUsedMB / 1024, s.swapTotalMB / 1024),
                fixes: fixes), details: s.lines()))
        }
        return out
    }

    private func publish(_ state: MacState, _ live: [LiveCard], own: Double) {
        let now = Date()
        DispatchQueue.main.async { [self] in
            mac = state
            overhead = own
            snoozed = snoozed.filter { $0.value > now }
            cards = live.filter { !dismissed.contains($0.id) && snoozed[$0.cause] == nil }
            // notify once for a card that has needed a look for 10 minutes; forget cards that went away
            let ids = Set(live.filter(\.needsLook).map(\.id))
            for c in live where c.needsLook {
                if firstSeen[c.id] == nil { firstSeen[c.id] = now }
                if !alerted.contains(c.id), now.timeIntervalSince(firstSeen[c.id]!) >= 600, !dismissed.contains(c.id) {
                    alerted.insert(c.id)
                    onAlert?(c)
                }
            }
            firstSeen = firstSeen.filter { ids.contains($0.key) }
            alerted = alerted.filter { ids.contains($0) }
        }
    }
}

extension Evidence {
    /// The facts behind a card, one plain line each, for the card's details.
    public func lines() -> [String] {
        var out: [String] = []
        out.append("Process: \(name), number \(pid)")
        if !args.isEmpty { out.append("Command: \(args.joined(separator: " "))") }
        out.append("Started by: \(startedBy)")
        if let c = launchCommand { out.append("Launched as: \(c)") }
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
