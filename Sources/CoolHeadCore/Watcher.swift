import Darwin
import Foundation
import AppKit
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
    public var needsLook: Bool { card.state == .stalled || (card.state == .unknown && !trusted) }
    /// What trusting this card would trust (see `Trust`), and the name to show; nil for what can't be trusted.
    public var trustKey: String? = nil
    public var trustName = ""
    /// Trusted and within its limits: shown, but calm.
    public var trusted = false
    /// A line about trust for the card: the promise while it is trusted, or why it is flagged anyway.
    public var trustNote: String? = nil
    /// True while the Mac is warm or hot and this card is a cause: a busy process, fast charging, or the heat itself
    /// when nothing explains it. Heat with a cause turns the badge yellow, so the cause is flagged rather than
    /// left green under "Running warm". It doesn't notify on its own.
    public var heatCause = false
    /// What the card is about, whatever its state: the process, or the Mac-wide condition.
    public var cause: String { causeKey ?? pid.map { "pid-\($0)" } ?? id }
    /// Overrides the cause, so a card keeps one identity as it changes (the memory card, warning or critical).
    public var causeKey: String? = nil
    /// How bad it is, to tell whether a card the person chose to wait on has got meaningfully worse:
    /// 2 for stuck or critical memory, 1 for something that needs a look, 0 otherwise.
    public var severity: Int {
        if card.state == .stalled || id.hasPrefix("memory-critical") { return 2 }
        return needsLook || heatCause ? 1 : 0
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
    /// Set to open the "Report a problem" form (from the tools along the bottom, or after a fix).
    public var showReport = false
    /// Set to show the past week from macOS's power log (the Trends tool along the bottom).
    public var showHistory = false
    /// Changes each time the panel closes, so it reopens clean: nothing left expanded, no form left open.
    public private(set) var panelSession = 0
    public func panelClosed() { showReport = false; showHistory = false; panelSession += 1; notices = [] }
    /// Short notes about something Cool Head noticed on its own (an app put a slowed process back to full speed),
    /// shown at the top of the panel until it next closes.
    public private(set) var notices: [String] = []
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
    /// Processes stuck in one of the ways `Hang` looks for: which way, and since when it has been seen that way.
    @ObservationIgnored private var hangSince: [pid_t: (kind: Hang.Kind, since: Date)] = [:]
    /// Process numbers of the jobs Cool Head paused itself, copied for the sampling queue: those aren't hangs.
    @ObservationIgnored private var ownPauses: Set<pid_t> = []
    @ObservationIgnored private let queue = DispatchQueue(label: "coolhead.watcher", qos: .utility)
    @ObservationIgnored private var timer: DispatchSourceTimer?
    /// The running count of swap-outs over about the last 2 minutes, for `MacState.swappedOutMB`.
    @ObservationIgnored private var swapSamples: [(at: Date, pages: UInt64)] = []

    struct Track {
        var cpu: Double            // CPU seconds at the last tick
        var written: UInt64
        var cores = 0.0            // smoothed cores in use
        var lastWritten: UInt64 = 0
        var busySince: Date?
        var footprint: UInt64 = 0
        var gpuTime: UInt64? = nil  // graphics-chip nanoseconds at the last tick
        var gpu = 0.0              // smoothed share of the graphics chip, 0 to 1
    }

    public init() {}
    static let launchUptime = ProcessInfo.processInfo.systemUptime

    // MARK: - Paused jobs and sync reminders (saved, see PauseStore)

    public private(set) var pausedJobs: [PausedJob] = PauseStore.load("pausedJobs")
    public private(set) var syncPauses: [SyncPause] = PauseStore.load("syncPauses")
    /// Chrome's memory limit in MB, while the one Cool Head set is in place: listed at the top of the panel with its
    /// undo. Chrome's settings are read only when Cool Head has set one.
    public private(set) var chromeLimitMB: Int? = nil
    public func refreshChromeLimit() {
        guard UserDefaults.standard.integer(forKey: ChromeLimit.marker) > 0, case .set(let mb) = ChromeLimit.status() else { chromeLimitMB = nil; return }
        chromeLimitMB = mb
    }
    @discardableResult public func removeChromeLimit() -> Bool {
        let ok = ChromeLimit.remove()
        log("Remove Chrome limit pressed: " + (ok ? "removed" : "failed"))
        refreshChromeLimit()
        return ok
    }
    /// Other apps' background helpers Cool Head turned off, and build folders it left out of Time Machine: listed at
    /// the top of the panel with their undo. Read only when Cool Head has done either; helpers at most once a minute,
    /// since that runs launchctl.
    public private(set) var agentsOff: [BackgroundAgents.Agent] = []
    public private(set) var backupExcluded: [String] = []
    @ObservationIgnored private var agentsReadAt = Date.distantPast
    /// macOS's own busy processes, read at most every 30 seconds each (see BackgroundWork).
    @ObservationIgnored private var backgroundReadings: [pid_t: (at: Date, reading: BackgroundWork.Reading)] = [:]
    public func refreshHeldBack(force: Bool = false) {
        if UserDefaults.standard.data(forKey: BackgroundAgents.marker) == nil { agentsOff = [] }
        else if force || Date().timeIntervalSince(agentsReadAt) >= 60 { agentsOff = BackgroundAgents.turnedOff(); agentsReadAt = Date() }
        backupExcluded = UserDefaults.standard.stringArray(forKey: BackupExclusions.marker) == nil ? [] : BackupExclusions.excludedByCoolHead()
    }
    @discardableResult public func turnOffAgent(label: String, plist: String) -> Bool {
        guard let a = BackgroundAgents.agent(plist: plist) ?? BackgroundAgents.disguised(plist: plist), a.label == label else { log("Stop it starting by itself pressed: plist not found"); return false }
        let ok = BackgroundAgents.turnOff(a)
        log("Stop it starting by itself pressed for \(a.label): " + (ok ? "turned off" : "failed"))
        refreshHeldBack(force: true)
        return ok
    }
    /// For one of macOS's own processes: its priority, a recent update, and whether it is stuck (see BackgroundWork).
    func background(_ e: Evidence, _ busySince: Date?, _ state: MacState, _ now: Date) -> BackgroundWork.Reading? {
        guard e.script == nil, let p = e.path, CaseReport.isMacOS(p) else { return nil }
        if let r = backgroundReadings[e.pid], now.timeIntervalSince(r.at) < 30 { return r.reading }
        let r = BackgroundWork.read(e, busySince: busySince, efficiencyCores: state.efficiencyCores, now: now, track: true)
        backgroundReadings = backgroundReadings.filter { now.timeIntervalSince($0.value.at) < 600 }
        backgroundReadings[e.pid] = (now, r)
        return r
    }

    @discardableResult public func turnOnAgent(_ a: BackgroundAgents.Agent) -> Bool {
        let ok = BackgroundAgents.turnOn(a)
        log("Turn back on pressed for \(a.label): " + (ok ? "turned on" : "failed"))
        refreshHeldBack(force: true)
        return ok
    }
    @discardableResult public func keepOutOfBackup(_ path: String) -> Bool {
        let ok = BackupExclusions.exclude(path)
        log("Keep out of Time Machine pressed: " + (ok ? "excluded" : "failed"))
        refreshHeldBack()
        return ok
    }
    @discardableResult public func backUpAgain(_ path: String) -> Bool {
        let ok = BackupExclusions.include(path)
        log("Back it up again pressed: " + (ok ? "included" : "failed"))
        refreshHeldBack()
        return ok
    }
    /// Called on the main thread with a short line to show as a notification (a sync reminder, low battery).
    @ObservationIgnored public var onReminder: ((String) -> Void)?
    private var batteryAlerted: Set<String> = []

    /// Freezes a job until the Mac is plugged in. Checked by reading back the process's state.
    public func pauseJob(_ c: LiveCard) -> Outcome {
        guard let p = c.pid, sameProcess(c) else { log("Pause pressed for \(c.reportSubject): it had already gone"); return .gone }
        guard kill(p, SIGSTOP) == 0 else {
            let why = String(cString: strerror(errno)); log("Pause pressed for \(c.reportSubject): failed (\(why))"); return .failed(why)
        }
        usleep(150_000)
        guard Proc.bsd(p)?.stopped == true else {
            kill(p, SIGCONT); log("Pause pressed for \(c.reportSubject): it didn't stay paused"); return .failed("it didn't stay paused")
        }
        let name = c.displaySubject.isEmpty ? "It" : c.displaySubject
        pausedJobs.append(PausedJob(key: Watcher.key(c), pid: p, start: c.start?.timeIntervalSince1970, name: name,
                                    reportSubject: c.reportSubject, since: Date()))
        PauseStore.save(pausedJobs, "pausedJobs")
        cards.removeAll { $0.cause == c.cause }
        log("Paused \(c.reportSubject) until plugged in")
        return .done("Paused \(name). It carries on by itself when you plug in, and it's listed at the top to resume sooner.")
    }

    /// Lets a paused job carry on. Only the same process is ever resumed (its number and start time match).
    @discardableResult
    public func resumeJob(_ j: PausedJob, why: String) -> Outcome {
        pausedJobs.removeAll { $0.key == j.key }
        PauseStore.save(pausedJobs, "pausedJobs")
        guard let b = Proc.bsd(j.pid), j.start.map({ abs(b.start.timeIntervalSince1970 - $0) < 1 }) ?? true else {
            log("\(j.reportSubject) had gone while paused"); return .gone
        }
        let ok = kill(j.pid, SIGCONT) == 0
        log("Resumed \(j.reportSubject) (\(why))" + (ok ? "" : ": failed"))
        return ok ? .done("\(j.name) carries on.") : .failed(String(cString: strerror(errno)))
    }

    /// Resumes every paused job: on plugging in, when Cool Head quits, and when it starts (in case it last quit
    /// without the chance), so nothing is ever left frozen.
    public func resumeAllPaused(why: String) {
        for j in pausedJobs { resumeJob(j, why: why) }
    }

    /// The person paused a sync app from Cool Head; remind them to resume it at `until`.
    public func addSyncPause(name: String, bundle: String, until: Date) {
        syncPauses.removeAll { $0.name == name }
        syncPauses.append(SyncPause(name: name, bundle: bundle, until: until))
        PauseStore.save(syncPauses, "syncPauses")
        log("Sync pause reminder set for \(name) until \(Fmt.clock(until))")
        onPublish?()
    }

    public func syncResumed(_ name: String) {
        syncPauses.removeAll { $0.name == name }
        PauseStore.save(syncPauses, "syncPauses")
        log("\(name) marked resumed")
        onPublish?()
    }

    public func start() {
        guard timer == nil else { return }
        resumeAllPaused(why: "Cool Head started")
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: interval, leeway: .seconds(2))
        t.setEventHandler { [weak self] in self?.tick() }
        timer = t
        t.resume()
    }

    /// Marks a card trusted, or flagged anyway with the reason, from the trust list and its limits.
    static func applyTrust(_ lc: inout LiveCard, thermal: String, busyFor: TimeInterval) {
        guard Trust.contains(lc.trustKey) else { lc.trusted = false; lc.trustNote = nil; return }
        if let why = Trust.overLimit(state: lc.card.state, thermal: thermal, busyFor: busyFor) {
            lc.trusted = false
            lc.trustNote = "You trust \(lc.trustName), but \(why)."
        } else {
            lc.trusted = true
            lc.heatCause = false
            lc.trustNote = Trust.promise
        }
    }

    /// Trusts what a card is about, or stops trusting it. Applies at once; the limits are checked again each sample.
    public func setTrusted(_ c: LiveCard, _ on: Bool) {
        guard let k = c.trustKey else { return }
        if on { Trust.add(k, name: c.trustName) } else { Trust.remove(k) }
        log((on ? "Trusted " : "Stopped trusting ") + c.reportSubject)
        refreshTrust()
    }

    public func untrust(key: String) {
        Trust.remove(key)
        log("Stopped trusting an item from the trusted list")
        refreshTrust()
    }

    /// Trusts an app chosen with the Trusted list's + button. macOS's own apps can't be trusted (they're explained
    /// instead), so this says no to them.
    public func trust(appPath: String) -> Bool {
        guard !CaseReport.isMacOS(appPath), appPath.hasSuffix(".app") else { return false }
        let name = (FileManager.default.displayName(atPath: appPath) as NSString).deletingPathExtension
        Trust.add(Trust.key(appPath: appPath), name: name)
        log("Trusted an app from the trusted list")
        refreshTrust()
        return true
    }

    private func refreshTrust() {
        cards = cards.map { c in
            var c = c
            if c.trustKey != nil, c.causeKey != "memory" {
                c.heatCause = mac.thermal != "nominal" && [.working, .starting, .unknown].contains(c.card.state) && c.card.hasAction
                Watcher.applyTrust(&c, thermal: mac.thermal, busyFor: 0)
            } else if c.causeKey == "memory" {
                c.trusted = Trust.contains(c.trustKey) && mac.memoryPressure != "critical"
                c.trustNote = Trust.contains(c.trustKey) ? (c.trusted ? Trust.promise : "You trust \(c.trustName), but memory is very tight.") : nil
            }
            return c
        }
        onPublish?()
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
        // a paused process can't act on the signal until it carries on
        if ok, Proc.bsd(p)?.stopped == true { kill(p, SIGCONT) }
        let why = ok ? "" : String(cString: strerror(errno))
        log("Stop pressed for \(c.reportSubject): " + (ok ? "stopped" : "failed (\(why))"))
        return ok ? .done("Stopped \(c.displaySubject.isEmpty ? "it" : c.displaySubject).") : .failed(why)
    }

    /// For a program pretending to be macOS's (see Disguise): turns off the Apple-labelled launch item that starts it (yours
    /// only), stops it, and moves its files to the Trash, where they can be put back. Never anything in macOS's own
    /// folders or signed by Apple. Only after the person confirms.
    public func stopAndTrash(_ c: LiveCard, paths: [String], launchItem: String?) -> Outcome {
        guard !Disguise.refusesTrash(paths) else {
            log("Stop and delete pressed for \(c.reportSubject): refused, part of macOS"); return .failed("it's part of macOS after all")
        }
        if let plist = launchItem, let a = BackgroundAgents.disguised(plist: plist) { BackgroundAgents.turnOff(a); refreshHeldBack(force: true) }
        if let p = c.pid, sameProcess(c) { kill(p, SIGTERM) }
        let failed = Disguise.moveToTrash(paths)
        log("Stop and delete pressed for \(c.reportSubject): " + (failed.isEmpty ? "stopped and moved to the Trash" : "stopped; \(failed.count) file(s) not moved"))
        if failed.isEmpty { cards.removeAll { $0.cause == c.cause } }
        return failed.isEmpty ? .done("Stopped it and moved it to the Trash. You can put it back from there.")
            : .failed("macOS didn't let Cool Head move \(failed.joined(separator: " and ")) to the Trash; drag it there in Finder, which asks for your password")
    }

    /// Lets a process carry on that something other than Cool Head paused. Checked by reading back its state.
    public func resumeStopped(_ c: LiveCard) -> Outcome {
        guard let p = c.pid, sameProcess(c) else { log("Resume pressed for \(c.reportSubject): it had already gone"); return .gone }
        guard kill(p, SIGCONT) == 0 else {
            let why = String(cString: strerror(errno)); log("Resume pressed for \(c.reportSubject): failed (\(why))"); return .failed(why)
        }
        usleep(200_000)
        if Proc.bsd(p)?.stopped == true {
            log("Resume pressed for \(c.reportSubject): it was paused again at once")
            return .failed("it was paused again straight away, so something is pausing it on purpose")
        }
        log("Resumed \(c.reportSubject), which something else had paused")
        cards.removeAll { $0.cause == c.cause }
        return .done("Resumed \(c.displaySubject.isEmpty ? "it" : c.displaySubject). It carries on from where it stopped.")
    }

    /// Ends an app that isn't responding, as Force Quit in the Apple menu does. Only after the person confirms.
    public func forceQuit(_ c: LiveCard) -> Outcome {
        guard let p = c.pid, sameProcess(c) else { log("Force quit pressed for \(c.reportSubject): it had already gone"); return .gone }
        let ok = kill(p, SIGKILL) == 0
        let why = ok ? "" : String(cString: strerror(errno))
        log("Force quit pressed for \(c.reportSubject): " + (ok ? "ended" : "failed (\(why))"))
        if ok { cards.removeAll { $0.cause == c.cause } }
        return ok ? .done("Force quit \(c.displaySubject.isEmpty ? "it" : c.displaySubject). Open it again when you need it.") : .failed(why)
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
            return .done("Slowing \(name)\(change) to keep your Mac cool. It's still working, just more slowly. Speed it up any time from the top of this panel.")
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
        // a warm Mac with a cause on screen needs a look; a cause already running cooler has been dealt with
        if cards.contains(where: { $0.needsLook || ($0.heatCause && !isCooled($0)) }) { return .warning }
        if syncPauses.contains(where: { $0.until <= Date() }) { return .warning }          // time to resume syncing
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
            tracks[pid] = tr
        }
        // processes owned by other users (root, _mds_stores, _windowserver): macOS doesn't let us read their usage
        // directly, but ps can; its figure is a recent average, which is what a lasting load needs. The same run of ps
        // gives every process's state, for the hang cards.
        let table = Proc.psTable()
        if !unreadable.isEmpty {
            for pid in unreadable {
                guard let pc = table[pid]?.cpu else { continue }
                seen.insert(pid)
                var tr = tracks[pid] ?? Track(cpu: 0, written: 0)
                tr.cores = pc / 100
                tracks[pid] = tr
            }
        }
        tracks = tracks.filter { seen.contains($0.key) }
        // the graphics chip, for every process whoever owns it (macOS's WindowServer draws the screen as another user)
        let gpuTimes = GPU.times()
        for pid in Array(tracks.keys) {
            guard var tr = tracks[pid] else { continue }
            if let t = gpuTimes[pid] {
                if dt > 0, let last = tr.gpuTime {
                    let g = GPU.share(from: last, to: t, seconds: dt)
                    tr.gpu = tr.gpu == 0 ? g : 0.5 * tr.gpu + 0.5 * g
                }
                tr.gpuTime = t
            } else { tr.gpuTime = nil; tr.gpu = 0 }
            // busy: half a core, or half the graphics chip; quiet again under a quarter of both
            if tr.cores >= 0.5 || tr.gpu >= GPU.busyShare { tr.busySince = tr.busySince ?? now }
            else if tr.cores < 0.25 && tr.gpu < GPU.quietShare { tr.busySince = nil }
            tracks[pid] = tr
        }
        var state = MacState.read()
        // for screenshots: COOLHEAD_SNAPSHOT_WARM shows the Mac as warm, so a card shows what it recommends then
        if ProcessInfo.processInfo.environment["COOLHEAD_SNAPSHOT_WARM"] != nil { state.thermal = "fair" }
        // for screenshots and tests: COOLHEAD_TEST_MEMORY shows memory as tight, so the memory card and its options show
        if ProcessInfo.processInfo.environment["COOLHEAD_TEST_MEMORY"] != nil, state.memoryPressure == "normal" { state.memoryPressure = "warning" }
        // memory moved to the disk over about the last 2 minutes, from the running count of swap-outs
        if let pages = state.swapOutPages {
            swapSamples.append((now, pages))
            swapSamples.removeAll { now.timeIntervalSince($0.at) > 125 }
            if let first = swapSamples.first, now.timeIntervalSince(first.at) >= 100, pages >= first.pages {
                state.swappedOutMB = Double(pages - first.pages) * Double(getpagesize()) / 1_048_576
            }
        }
        guard dt > 0 else { publish(state, [], own: 0); return }

        let warm = state.thermal != "nominal"
        // suspects: using half a core or half the graphics chip, for over a minute
        let busy = tracks.filter { $0.key != me && ($0.value.cores >= 0.5 || $0.value.gpu >= GPU.busyShare)
                && now.timeIntervalSince($0.value.busySince ?? now) >= 60 }
            .sorted { max($0.value.cores, $0.value.gpu) > max($1.value.cores, $1.value.gpu) }.prefix(5)
        var live: [LiveCard] = []
        let gathered = busy.compactMap { pid, tr in
            Evidence.gather(pid: pid, measured: (tr.cores, tr.lastWritten), gpu: gpuTimes[pid] != nil ? tr.gpu : nil).map { (pid, tr, $0) }
        }
        // a game being played comes first: other busy work is offered to run cooler to leave it more room
        let game = gathered.first { $0.2.gameBundle != nil }.flatMap { $0.2.gameBundle }
            .map { (($0 as NSString).lastPathComponent as NSString).deletingPathExtension }
        let front = NSWorkspace.shared.frontmostApplication?.bundleURL?.path
        let battery = BatteryMode.enabled && !state.onPower ? state.batteryPercent : nil       // a desktop has no battery
        // processes writing lots to disk right now (over 100 KB a second), for a busy sync app: a build in a folder it
        // syncs makes it upload every file (see SyncFeed). Read only when a sync app is on the list.
        lazy var writers: [(cwd: String, who: String, bytes: UInt64)] = tracks.compactMap { pid, tr in
            guard pid != me, dt > 0, Double(tr.lastWritten) / dt >= 100_000, let cwd = Proc.cwd(pid), cwd != "/",
                  let b = Proc.bsd(pid), b.uid == getuid(), SyncApps.app(bundle: Evidence.bundle(Proc.path(pid))) == nil else { return nil }
            return (cwd, b.name, tr.lastWritten)
        }
        // the same, with the files each is writing, for a busy Time Machine: a build's output is the cause to fix (see
        // BackupExclusions). Read only when Time Machine is on the list.
        lazy var fileWriters: [(who: String, files: [String], bytes: UInt64)] = tracks.compactMap { pid, tr in
            guard pid != me, dt > 0, Double(tr.lastWritten) / dt >= 100_000, let b = Proc.bsd(pid), b.uid == getuid() else { return nil }
            return (b.name, Proc.openFiles(pid).filter(\.writable).map(\.path), tr.lastWritten)
        }
        for (pid, tr, e) in gathered {
            let feed = SyncApps.app(bundle: e.appBundle).flatMap { SyncFeed.find(sync: $0, writers: writers) }
            let backup = Pattern.match(name: e.name, path: e.path, pid: e.pid)?.id == "time-machine" ? BackupExclusions.find(writers: fileWriters) : nil
            // another app's background helper, by its program or a program that started it, up to the first regular app
            // (an app you use is quit, never turned off)
            let programs = ([(pid, e.path)] + e.ancestors.map { ($0.pid, $0.path) })
                .prefix { NSRunningApplication(processIdentifier: $0.0)?.activationPolicy != .regular }.compactMap(\.1)
            let agent = e.mine ? BackgroundAgents.owner(of: Array(programs)) : nil
            let c = Card.make(e, now: now, busySince: tr.busySince, warm: warm, gameRunning: game, frontApp: front, battery: battery,
                              syncFeed: feed, agent: agent, backupFeed: backup, disguise: Disguise.find(e), background: background(e, tr.busySince, state, now))
            guard c.state != .quiet else { continue }
            var lc = LiveCard(id: "\(pid)-\(c.state.rawValue)", pid: pid, start: e.start, card: c, details: e.lines())
            lc.reportSubject = CaseReport.subject(e)
            lc.displaySubject = Card.subject(e)
            // flagged only when there's something to press; normal macOS work is still shown, as the explanation
            lc.heatCause = (warm && [.working, .starting, .unknown].contains(c.state) && c.hasAction)
                || c.fixes.contains { $0.kind == .pauseJob }                  // draining the battery counts too
            lc.trustKey = Trust.key(e)
            lc.trustName = e.browserPart != nil ? (e.app ?? Card.subject(e)) : Card.subject(e)   // trusting a tab trusts the browser
            Watcher.applyTrust(&lc, thermal: state.thermal, busyFor: now.timeIntervalSince(tr.busySince ?? now))
            if let pr = Proc.schedulingPriority(pid), pr > 4 { lastPriority[pid] = pr }
            if c.fixes.contains(where: { $0.kind == .share }) {
                lc.report = (CaseReport.title(e, card: c), CaseReport.make(e, card: c, mac: state, busySince: tr.busySince, now: now))
            }
            live.append(lc)
        }
        let explained = !live.isEmpty
        // a stuck process has its own card, in place of a busy one for the same process (an app not responding while busy)
        let hung = hangCards(table, now: now, mac: state)
        live.removeAll { c in hung.contains { $0.pid == c.pid } }
        live += hung
        live += macCards(state, now: now, explained: explained)
        if ProcessInfo.processInfo.environment["COOLHEAD_DEBUG"] != nil {
            let top = tracks.sorted { $0.value.cores > $1.value.cores }.prefix(3)
                .map { "\($0.key):\(String(format: "%.2f", $0.value.cores)) gpu \(String(format: "%.2f", $0.value.gpu)) since \($0.value.busySince.map { Int(now.timeIntervalSince($0)) } ?? -1)s" }
            FileHandle.standardError.write("t+\(Int(ProcessInfo.processInfo.systemUptime - Watcher.launchUptime))s tick busy=\(busy.count) cards=\(live.map { $0.card.headline.prefix(50) }) top=\(top)\n".data(using: .utf8)!)
        }

        publish(state, live, own: own / Double(max(1, state.cores)))
    }

    /// Cards for processes that are stuck while using almost nothing (see `Hang`), once each has been stuck long enough.
    private func hangCards(_ table: [pid_t: Proc.PS], now: Date, mac: MacState) -> [LiveCard] {
        let me = getpid()
        var current: [pid_t: Hang.Kind] = [:]
        for (pid, row) in table where pid > 1 && pid != me && !ownPauses.contains(pid) {
            if let k = Hang.kind(psState: row.state) { current[pid] = k }
        }
        for pid in Hang.notResponding() where pid != me { current[pid] = .notResponding }
        // keep the time each was first seen stuck, as long as it stays stuck the same way
        hangSince = current.reduce(into: [:]) { out, kv in
            if let was = hangSince[kv.key], was.kind == kv.value { out[kv.key] = was } else { out[kv.key] = (kv.value, now) }
        }
        var out: [LiveCard] = []
        var pids: [pid_t]?
        for (pid, h) in hangSince.sorted(by: { $0.value.since < $1.value.since }).prefix(5) {
            let stuckFor = now.timeIntervalSince(h.since)
            // the first look is cheap: nothing is gathered until it has been stuck at least the shortest threshold
            guard stuckFor >= min(Hang.threshold(h.kind, suspendedInShell: false), Hang.threshold(h.kind, suspendedInShell: true)) else { continue }
            let cores = tracks[pid]?.cores ?? (table[pid]?.cpu ?? 0) / 100
            // touching the files of a process waiting on a drive could leave Cool Head waiting too
            guard let e = Evidence.gather(pid: pid, measured: (cores, 0), readFiles: h.kind != .diskWait) else { continue }
            let terminal = h.kind == .paused ? Hang.terminalApp(e, pid: pid) : nil
            guard stuckFor >= Hang.threshold(h.kind, suspendedInShell: terminal != nil) else { continue }
            if pids == nil { pids = Proc.allPIDs() }
            let waiting = Proc.children(of: pid, among: pids).compactMap { Proc.bsd($0)?.name }
            let card = Hang.card(h.kind, e, stuckFor: stuckFor, waiting: waiting, volumes: h.kind == .diskWait ? Hang.volumes(pid) : [],
                                  terminal: terminal, now: now)
            var lc = LiveCard(id: "hang-\(h.kind.rawValue)-\(pid)", pid: pid, start: e.start, card: card,
                              details: e.lines() + ["Stuck: \(Hang.words(h.kind)), since \(Fmt.time(h.since))"]
                                + (waiting.isEmpty ? [] : ["Programs it started: \(waiting.count)"]))
            lc.reportSubject = CaseReport.subject(e) + ", " + Hang.words(h.kind)
            lc.displaySubject = Card.subject(e)
            if card.fixes.contains(where: { $0.kind == .share }) {
                lc.report = (CaseReport.title(e, card: card) + ", " + Hang.words(h.kind),
                             CaseReport.make(e, card: card, mac: mac, busySince: h.since, now: now) + "\n**Stuck:** " + Hang.words(h.kind))
            }
            out.append(lc)
        }
        return out
    }

    /// Cards about the Mac as a whole, which no single process explains.
    private func macCards(_ s: MacState, now: Date, explained: Bool) -> [LiveCard] {
        var out: [LiveCard] = []
        let warm = s.thermal != "nominal"
        let fastCharging = s.charging && (s.batteryWatts ?? 0) > 15
        if fastCharging, let w = s.batteryWatts, warm {
            var lc = LiveCard(id: "charging", pid: nil, card: Card(
                state: .working,
                headline: "Fast charging is adding heat.",
                explanation: "It's charging at about \(Int(w.rounded())) W. That slows down after 80%.",
                fixes: [Card.wait(until: nil, now: now, recommended: true),
                        Fix.guide("unplug", "Unplug for a bit", "Charging stops adding heat until you plug back in.",
                                  steps: ["Unplug the charger.", "Plug it back in once your Mac feels cooler."], recommended: true)]),
                details: s.lines(), reportSubject: "fast charging adding heat")
            lc.heatCause = true
            out.append(lc)
        }
        // warm, and no busy process or charging to point to: say so, and what usually explains it
        if warm && !explained && !fastCharging {
            let me = getpid()
            let top = tracks.filter { $0.key != me && $0.value.cores >= 0.25 }.max { $0.value.cores < $1.value.cores }
            let busiest = top.flatMap { t in Proc.path(t.key).map { (($0 as NSString).lastPathComponent, t.value.cores) } }
            var lc = LiveCard(id: "heat", pid: nil, card: Card(
                state: .working,
                headline: "Your Mac is warm, but nothing is working hard right now.",
                explanation: (busiest.map { "The busiest is \($0.0), at about \(Fmt.cores($0.1)). " } ?? "")
                    + (s.memoryLevel != nil
                       ? "Memory is tight too, so your Mac is moving data to and from its disk, which adds work and some heat. "
                       : "")
                    + "Heat can linger after heavy work, or come from a warm room or a soft surface.",
                fixes: [Card.wait(until: nil, now: now, recommended: true),
                        Fix.guide("air", "Give it air", "A hard surface, out of the sun, helps it cool.",
                                  steps: ["Move it onto a hard, flat surface: a bed, sofa or lap traps heat.", "Keep it out of the sun, with nothing over its vents.", "If you have a stand that lifts it, use it."], recommended: true)]),
                details: s.lines(), reportSubject: "warm with no single cause")
            lc.heatCause = true
            out.append(lc)
        }
        if let level = s.memoryLevel {
            // count memory the way a person thinks of it: each app with all its helpers, each job on its own
            var groups = MemoryAdvice.merge(tracks.compactMap { pid, tr in
                MemoryAdvice.group(pid: pid, path: Proc.path(pid), args: Proc.args(pid), footprint: tr.footprint)
            })
            for i in groups.indices.prefix(3) where groups[i].kind == .job {
                if let p = groups[i].pid { groups[i].evidence = Evidence.gather(pid: p, measured: (tracks[p]?.cores ?? 0, 0), gpu: tracks[p].flatMap { $0.gpuTime != nil ? $0.gpu : nil }) }
            }
            let card = MemoryAdvice.card(groups, mac: s, now: now)
            let top = groups.first
            let subject = top.map { g -> String in
                if let e = g.evidence { return "memory running short (\(level)); most used by \(CaseReport.subject(e))" }
                return "memory running short (\(level)); most used by " + (g.kind == .macOS || g.bundle != nil ? g.name : "a program (its name is withheld)")
            } ?? "memory running short (\(level))"
            var mc = LiveCard(id: "memory-\(level)", pid: top?.kind == .job ? top?.pid : nil,
                              start: top?.kind == .job ? top?.evidence?.start : nil,
                              card: card, details: s.lines(), reportSubject: subject)
            mc.causeKey = "memory"
            if let e = top?.evidence { mc.displaySubject = Card.subject(e) }
            // trusting the biggest user calms tight memory, but never critical memory
            if let t = top {
                mc.trustKey = t.bundle.map { Trust.key(appPath: $0) } ?? t.evidence.flatMap { Trust.key($0) }
                mc.trustName = t.evidence.map { Card.subject($0) } ?? t.name
                if Trust.contains(mc.trustKey) {
                    if s.memoryPressure == "critical" { mc.trustNote = "You trust \(mc.trustName), but memory is very tight." }
                    else { mc.trusted = true; mc.trustNote = Trust.promise }
                }
            }
            out.append(mc)
        }
        return out
    }

    private func publish(_ state: MacState, _ live: [LiveCard], own: Double) {
        let now = Date()
        DispatchQueue.main.async { [self] in
            mac = state
            overhead = own
            let pausedPIDs = Set(pausedJobs.map(\.pid))
            queue.async { [self] in ownPauses = pausedPIDs }
            refreshChromeLimit()
            refreshHeldBack()
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
            // battery under 20% while a job drains it: say so once per job
            let low = (state.batteryPercent ?? 100) < 20 && !state.onPower
            let draining = live.filter { c in c.card.fixes.contains { $0.kind == .pauseJob } && !waitingOn(c) && !c.trusted }
            for c in draining where low && batteryAlerted.insert(c.id).inserted {
                onReminder?("Your battery is low and a job is draining it. Open Cool Head to pause it until you plug in.")
            }
            batteryAlerted = batteryAlerted.filter { id in draining.contains { $0.id == id } }
            // plugged in: paused jobs carry on
            if state.onPower && !pausedJobs.isEmpty {
                let names = pausedJobs.map(\.name)
                resumeAllPaused(why: "plugged in")
                notices.append(ListFormatter.localizedString(byJoining: names) + (names.count == 1 ? " carries" : " carry") + " on: you plugged in.")
            }
            // paused jobs that have ended are forgotten
            let pausedBefore = pausedJobs.count
            pausedJobs.removeAll { j in Proc.bsd(j.pid).map { b in j.start.map { abs(b.start.timeIntervalSince1970 - $0) >= 1 } ?? false } ?? true }
            if pausedJobs.count != pausedBefore { PauseStore.save(pausedJobs, "pausedJobs") }
            // sync reminders that are due: notify once
            var reminded = false
            for i in syncPauses.indices where syncPauses[i].until <= now && !syncPauses[i].reminded {
                syncPauses[i].reminded = true; reminded = true
                onReminder?("Time to resume \(syncPauses[i].name) syncing.")
            }
            if reminded { PauseStore.save(syncPauses, "syncPauses") }
            alerted = alerted.filter { ids.contains($0) }
            // a pinned (cooled) process that has ended is unpinned; so is one its app put back to full speed (Chrome
            // sets its own tabs' priority, and may when you switch to the tab)
            for (k, item) in cooled {
                let alive = Proc.bsd(item.pid).map { b in item.start.map { abs(b.start.timeIntervalSince($0)) < 1 } ?? true } ?? false
                if !alive { cooled.removeValue(forKey: k); log("\(item.reportSubject) finished while running cooler"); continue }
                if let pri = Proc.schedulingPriority(item.pid), pri > 4 {
                    cooled.removeValue(forKey: k)
                    log("\(item.reportSubject) was put back to full speed by its app (priority \(pri))")
                    notices.append("\(item.name) is back to full speed: its app sped it up again, probably because you're using it.")
                }
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
        if let g = gpuShare { out.append("Graphics chip: \(Fmt.share(g)) of it now") }
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
        if let mb = swappedOutMB { out.append(String(format: "Moved to disk in the last 2 minutes: %.0f MB", mb)) }
        if let d = diskFreeBytes { out.append("Startup disk free: \(MemoryAdvice.diskGB(d))") }
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
