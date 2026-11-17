import AppKit
import CoolHeadCore
import Observation

/// Keeps the power cards (see PowerState.swift) current: Low Power Mode and what's holding the Mac awake every 5
/// minutes and when the panel opens (at most once a minute), each under a hundredth of a second; the sleep log, about 2
/// seconds of work, at launch and after each wake only.
@MainActor @Observable
final class PowerWatch {
    static let shared = PowerWatch()

    private(set) var cards: [LiveCard] = []
    @ObservationIgnored private var lowPower: PowerState.LowPower?
    @ObservationIgnored private var holds: [PowerState.Hold] = []
    @ObservationIgnored private var night: PowerState.Night?
    @ObservationIgnored private var lastRead: Date?
    @ObservationIgnored private var reading = false
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private weak var watcher: Watcher?
    /// For each program holding the Mac awake for hours: the chip time it and the programs it started had used at the
    /// last reading, when that was, when it last did real work, and when Cool Head started watching it.
    @ObservationIgnored private var activity: [Int32: (at: Date, cpu: Double, busyAt: Date?, since: Date)] = [:]

    private var snapshot: Bool { ProcessInfo.processInfo.environment["COOLHEAD_SNAPSHOT"] != nil }

    func start(_ watcher: Watcher) {
        self.watcher = watcher
        guard !snapshot else { return }
        refresh(force: true, log: true)
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { _ in Task { @MainActor in PowerWatch.shared.refresh(force: true) } }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in PowerWatch.shared.refresh(force: true, log: true) }
        }
    }

    func refresh(force: Bool = false, log: Bool = false) {
        guard !reading, !snapshot else { return }
        let now = Date()
        if !force, let last = lastRead, now.timeIntervalSince(last) < 60 { return }
        reading = true
        DispatchQueue.global(qos: .utility).async {
            let (lp, holds, night) = PowerState.read(log: log)
            let cpu = PowerWatch.treeCPU(Set(holds.filter { $0.seconds >= 3600 }.map { $0.forPID ?? $0.pid }))
            DispatchQueue.main.async {
                let w = PowerWatch.shared
                w.track(cpu, now: now)
                w.lowPower = lp; w.holds = holds
                if log { w.night = night }
                w.lastRead = now
                w.reading = false
                w.rebuild(now: now)
            }
        }
    }

    /// The cards, from the last readings and the watcher's view of the Mac now.
    func rebuild(now: Date = Date()) {
        guard let watcher else { return }
        let mac = watcher.mac
        // busy: something is working hard, or the Mac is warm; that's when Low Power Mode explains slowness
        let busy = mac.thermal != "nominal" || watcher.cards.contains { $0.pid != nil && $0.card.state != .quiet }
        cards = PowerState.cards(lowPower: lowPower, lowPowerNow: ProcessInfo.processInfo.isLowPowerModeEnabled, onPower: mac.onPower,
                                 busy: busy, holds: holds, who: PowerWatch.who, idleFor: { self.idleFor($0, now: now) }, night: night, now: now)
    }

    /// The chip time, in seconds, each program and every program it started (and they started) have used so far.
    nonisolated static func treeCPU(_ owners: Set<Int32>) -> [Int32: Double] {
        guard !owners.isEmpty else { return [:] }
        var kids: [pid_t: [pid_t]] = [:]
        for p in Proc.allPIDs() { if let b = Proc.bsd(p) { kids[b.ppid, default: []].append(p) } }
        var out: [Int32: Double] = [:]
        for owner in owners {
            var total = 0.0, queue = [owner], seen: Set<pid_t> = []
            while let p = queue.popLast() {
                guard seen.insert(p).inserted else { continue }
                total += Proc.usage(p)?.cpuSeconds ?? 0
                queue += kids[p] ?? []
            }
            out[owner] = total
        }
        return out
    }

    /// Notes which programs did real work since the last reading: more than `PowerState.idleShare` of one core.
    func track(_ cpu: [Int32: Double], now: Date) {
        for (pid, c) in cpu {
            if var a = activity[pid] {
                let share = max(0, c - a.cpu) / max(1, now.timeIntervalSince(a.at))
                if share >= PowerState.idleShare { a.busyAt = now }
                a.at = now; a.cpu = c
                activity[pid] = a
            } else {
                activity[pid] = (now, c, nil, now)
            }
        }
        activity = activity.filter { cpu[$0.key] != nil }
    }

    /// How long a program has done almost nothing, as far as Cool Head has seen: nil until it has two readings.
    func idleFor(_ pid: Int32, now: Date) -> TimeInterval? {
        guard let a = activity[pid], a.at > a.since else { return nil }
        return now.timeIntervalSince(a.busyAt ?? a.since)
    }

    /// A process's app name and bundle, as the cards name it: the app's own name where it's an installed app.
    nonisolated static func who(_ pid: Int32) -> PowerState.Who? {
        guard let path = Proc.path(pid) else { return nil }
        var bundle: String?
        if let r = path.range(of: ".app/") {
            let b = String(path[..<r.lowerBound]) + ".app"
            if b.hasPrefix("/Applications/") || b.hasPrefix(NSHomeDirectory() + "/Applications/") { bundle = b }
        }
        let name = bundle.map { (($0 as NSString).lastPathComponent as NSString).deletingPathExtension } ?? (path as NSString).lastPathComponent
        return PowerState.Who(name: name, bundle: bundle, protected: SecuritySoftware.product(path: path, name: name) != nil)
    }

    /// The cards to show: those the person hasn't chosen to wait on (the clock in a card's corner).
    func visible(_ watcher: Watcher, now: Date = Date()) -> [LiveCard] {
        cards.filter { c in watcher.snoozed[c.cause].map { $0.until <= now || c.severity > $0.severity } ?? true }
    }
}

extension PowerWatch: CardSource {
    func panelOpened() { refresh() }       // at most once a minute
    func cards(for watcher: Watcher) -> [LiveCard] { visible(watcher) }
}
