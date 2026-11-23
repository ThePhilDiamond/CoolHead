import Foundation

/// Holds apps and jobs to a CPU limit (CPUCap.Level) by stopping and continuing them: every `period`, a group's
/// processes run for a share of it and are stopped (SIGSTOP) for the rest, then continued (SIGCONT). Once a second the
/// CPU time they actually used is measured and the share moved toward the level's amount, so an app using four cores
/// is held to its target as surely as one using one. A group is an app and its helpers, stopped and continued
/// together so one isn't left waiting on another.
///
/// Only your own processes, as with Run it cooler. A group can be set aside (`hold(_:_:)`) while you're using the app
/// or it plays sound or downloads: it runs freely until then. Everything stopped is continued when a group is removed,
/// when Cool Head quits (`removeAll`), and, after a crash, when Cool Head next starts (`recover`), since the processes
/// limited are saved with their start times.
public final class CPULimiter {
    public struct Group {
        public var pids: Set<pid_t>
        /// What it is, to find its processes again each sample: an app's Trust key (all its helpers), else the
        /// process it started from (with what that started).
        public var trust: String?
        public var root: pid_t
        public var level: CPUCap.Level
        /// Cores' worth it used before the limit, measured once for this launch (never stored).
        public var before: Double
        /// The share of each period it runs, from 0.05 to 1.
        public var share: Double = 1
        /// Running freely for now: you're using it, or it plays sound or downloads.
        public var held = false
        var lastCPU: [pid_t: Double] = [:]
        var lastAt: Date?
        /// Cores' worth used in the last measured second, for the panel and the checks.
        public var used: Double?
    }

    public static let period: TimeInterval = 0.1
    static let minShare = 0.05
    static let defaultsKey = "cpuLimited"

    private let queue = DispatchQueue(label: "coolhead.cpulimit", qos: .userInitiated)
    private var groups: [String: Group] = [:]
    private var cycle: DispatchSourceTimer?
    private var measure: DispatchSourceTimer?
    private var ticks = 0

    public init() {}

    // MARK: Deciding the share

    /// The next share of each period to run: moved toward the target by how far the last second's use was from it,
    /// a step at a time so it settles instead of swinging, and kept between `minShare` and all of it.
    public static func nextShare(_ share: Double, target: Double, used: Double) -> Double {
        guard used > 0.01 else { return min(1, share * 1.5) }
        let ratio = max(0.5, min(2, target / used))
        return max(minShare, min(1, share * ratio))
    }

    // MARK: Groups

    public var isEmpty: Bool { queue.sync { groups.isEmpty } }
    public var snapshot: [String: Group] { queue.sync { groups } }

    /// Starts or changes a group's limit. Full speed removes it.
    public func set(_ key: String, pids: Set<pid_t>, trust: String?, root: pid_t, level: CPUCap.Level, before: Double) {
        guard level != .full else { remove(key); return }
        queue.sync {
            var g = groups[key] ?? Group(pids: pids, trust: trust, root: root, level: level, before: before)
            let gone = g.pids.subtracting(pids)
            for p in gone { kill(p, SIGCONT) }
            g.pids = pids; g.level = level; g.before = before
            groups[key] = g
            saveLocked()
            startLocked()
        }
    }

    /// New helpers join, ones that quit leave.
    public func update(_ key: String, pids: Set<pid_t>) {
        queue.sync {
            guard var g = groups[key] else { return }
            for p in g.pids.subtracting(pids) { kill(p, SIGCONT) }
            g.pids = pids
            groups[key] = g
            saveLocked()
        }
    }

    /// Runs a group freely (continued) while `on`, and limits it again after.
    public func hold(_ key: String, _ on: Bool) {
        queue.sync {
            guard var g = groups[key], g.held != on else { return }
            g.held = on
            if on { for p in g.pids { kill(p, SIGCONT) } }
            groups[key] = g
        }
    }

    public func remove(_ key: String) {
        queue.sync {
            if let g = groups.removeValue(forKey: key) { for p in g.pids { kill(p, SIGCONT) } }
            saveLocked()
            if groups.isEmpty { stopLocked() }
        }
    }

    public func removeAll() {
        queue.sync {
            for g in groups.values { for p in g.pids { kill(p, SIGCONT) } }
            groups = [:]
            saveLocked()
            stopLocked()
        }
    }

    // MARK: The cycle

    private func startLocked() {
        guard cycle == nil else { return }
        let c = DispatchSource.makeTimerSource(queue: queue)
        c.schedule(deadline: .now(), repeating: CPULimiter.period, leeway: .milliseconds(2))
        c.setEventHandler { [weak self] in self?.runCycle() }
        c.resume()
        cycle = c
    }

    private func stopLocked() {
        cycle?.cancel(); cycle = nil
    }

    /// Continue every limited group; stop each again after its share of the period. Once a second, measure.
    private func runCycle() {
        ticks += 1
        if ticks % Int(1 / CPULimiter.period) == 0 { measureLocked() }
        for (key, g) in groups where !g.held {
            for p in g.pids { kill(p, SIGCONT) }
            guard g.share < 0.995 else { continue }
            queue.asyncAfter(deadline: .now() + CPULimiter.period * g.share) { [weak self] in
                guard let self, let now = self.groups[key], !now.held else { return }
                for p in now.pids { kill(p, SIGSTOP) }
            }
        }
    }

    private func measureLocked() {
        let now = Date()
        var changed = false
        for (key, var g) in groups {
            var cpu: [pid_t: Double] = [:]
            for p in g.pids { if let u = Proc.usage(p) { cpu[p] = u.cpuSeconds } }
            // a process that's gone leaves the group; a group with none left is done
            if Set(cpu.keys) != g.pids { changed = true }
            g.pids = Set(cpu.keys)
            if g.pids.isEmpty { groups.removeValue(forKey: key); continue }
            if let at = g.lastAt, !g.held, now.timeIntervalSince(at) > 0.2 {
                let spent = cpu.reduce(0.0) { $0 + max(0, $1.value - (g.lastCPU[$1.key] ?? $1.value)) }
                let used = spent / now.timeIntervalSince(at)
                g.used = used
                if let target = g.level.cores(before: g.before) { g.share = CPULimiter.nextShare(g.share, target: target, used: used) }
            }
            g.lastCPU = cpu; g.lastAt = now
            groups[key] = g
        }
        if changed { saveLocked() }
        if groups.isEmpty { stopLocked() }
    }

    // MARK: After a crash

    struct Saved: Codable { let pid: Int32; let start: Double }

    private func saveLocked() {
        let all = groups.values.flatMap(\.pids).compactMap { p in Proc.bsd(p).map { Saved(pid: p, start: $0.start.timeIntervalSince1970) } }
        PauseStore.save(all, CPULimiter.defaultsKey)
    }

    /// On start: continue anything a previous run left limited (it may have stopped mid-period), only the same process.
    public static func recover() {
        let saved: [Saved] = PauseStore.load(defaultsKey)
        for s in saved {
            if let b = Proc.bsd(s.pid), abs(b.start.timeIntervalSince1970 - s.start) < 1 { kill(s.pid, SIGCONT) }
        }
        PauseStore.save([Saved](), defaultsKey)
    }
}
