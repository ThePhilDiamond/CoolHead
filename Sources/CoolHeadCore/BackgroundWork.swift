import Darwin
import Foundation

/// How to read macOS's own background work (research rules 13, 16 and 17): by the priority its threads run at and how
/// long it has gone on, not by % CPU.
///
/// - **Priority (rule 13).** Threads at priority 4 or lower are macOS's background band (background and maintenance
///   quality of service, which XNU's `thread_policy.c` maps to MAXPRI_THROTTLE): they run on the efficiency cores near
///   their lowest speed and make little heat however busy they look (Howard Oakley, Eclectic Light, 9 May 2025 and
///   17 February 2026, measured). Heat comes from work at 31 and above. Exception: chips with only two efficiency cores
///   (M1 Pro, M1 Max) speed them up once two or more background threads are busy, so nothing is said there.
///   Other users' threads can't be read with `proc_pidinfo` (denied without root); /bin/ps, which runs as root, shows
///   them (`ps -M`), so that is what is read.
/// - **After an update (rule 17).** Spotlight re-indexes and Photos re-analyses for hours or days after a macOS update
///   (Apple 102321; Howard Oakley). The last update is read from /Library/Receipts/InstallHistory.plist.
/// - **Stuck (rule 16).** macOS's background work busy for over a day is a fault, not work; still busy after a restart
///   is a fault only Apple can fix (dasd on macOS 27 for days; spotlightknowledged on 26.1; OS X Daily, 26 October
///   2026; MacRumors). To know it survived a restart, Cool Head keeps the names of macOS's own services that are busy,
///   with when they started and when they were last busy, and nothing else.
public enum BackgroundWork {
    /// What is known about one of macOS's own processes, for its card.
    public struct Reading: Equatable {
        /// True when its busy threads are in macOS's background band (and the chip keeps that cool); nil when unknown.
        public var cool: Bool?
        /// The last macOS update, when it was recent enough to explain indexing and analysis.
        public var update: Update?
        /// When it is stuck: busy since then, and whether a restart came in between.
        public var stuck: Stuck?
        public init(cool: Bool? = nil, update: Update? = nil, stuck: Stuck? = nil) { self.cool = cool; self.update = update; self.stuck = stuck }
    }

    public struct Update: Equatable {
        public let version: String
        public let date: Date
        public init(version: String, date: Date) { self.version = version; self.date = date }
    }

    public struct Stuck: Equatable {
        public let since: Date
        public let afterRestart: Bool
        public init(since: Date, afterRestart: Bool) { self.since = since; self.afterRestart = afterRestart }
    }

    /// Busy this long, macOS's own work is stuck.
    public static let stuckAfter: TimeInterval = 24 * 3600
    /// Indexing and analysis are expected for this long after an update ("hours or days"; about a week is the limit).
    public static let afterUpdate: TimeInterval = 7 * 24 * 3600

    // MARK: priority

    /// One thread: its recent CPU (percent of one core) and scheduling priority.
    public struct Thread: Equatable {
        public let cpu: Double
        public let priority: Int
        public init(cpu: Double, priority: Int) { self.cpu = cpu; self.priority = priority }
    }

    /// Whether busy threads like these run cool: at least 90% of their CPU in the background band (priority 4 or lower),
    /// and not two or more of them on a chip with only two efficiency cores. Nil when too little is busy to tell.
    public static func cool(_ threads: [Thread], efficiencyCores: Int) -> Bool? {
        let total = threads.reduce(0) { $0 + $1.cpu }
        guard total >= 5 else { return nil }
        let low = threads.filter { $0.priority <= 4 }
        if efficiencyCores == 2 && low.filter({ $0.cpu >= 5 }).count >= 2 { return false }
        return low.reduce(0) { $0 + $1.cpu } / total >= 0.9
    }

    /// The threads of a process, from `ps -M` (lines like "  560   0.0 S     4T   0:00.08   0:00.59": %CPU, state,
    /// priority with its policy letter).
    public static func parseThreads(_ text: String) -> [Thread] {
        text.split(separator: "\n").compactMap { line in
            guard let m = line.firstMatch(of: #/\s(\d+(?:\.\d+)?)\s+\S+\s+(\d+)[A-Z]\s/#),
                  let cpu = Double(m.1), let pri = Int(m.2) else { return nil }
            return Thread(cpu: cpu, priority: pri)
        }
    }

    public static func threads(_ pid: pid_t) -> [Thread] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-M", "-p", "\(pid)"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        guard (try? task.run()) != nil else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        return parseThreads(String(decoding: data, as: UTF8.self))
    }

    // MARK: the last update

    /// The latest full macOS update in the install history (not Rapid Security Responses or background security fixes).
    public static func lastUpdate(history: [[String: Any]]) -> Update? {
        history.compactMap { e -> Update? in
            guard let name = e["displayName"] as? String, name.hasPrefix("macOS "), !name.contains("Security"),
                  let version = e["displayVersion"] as? String, version.first?.isNumber == true,
                  let date = e["date"] as? Date else { return nil }
            return Update(version: version, date: date)
        }.max { $0.date < $1.date }
    }

    /// Read again at most once an hour.
    public static func lastUpdate(now: Date = Date()) -> Update? {
        updateCache.with { c in
            if let read = c.read, now.timeIntervalSince(read) < 3600 { return c.value }
            let data = FileManager.default.contents(atPath: "/Library/Receipts/InstallHistory.plist")
            let list = data.flatMap { try? PropertyListSerialization.propertyList(from: $0, format: nil) } as? [[String: Any]]
            c = (now, list.flatMap { lastUpdate(history: $0) })
            return c.value
        }
    }
    static let updateCache = Locked<(read: Date?, value: Update?)>((nil, nil))

    // MARK: stuck

    /// What is kept per service: when it began, when it was last seen busy, and the boot it was seen in.
    public struct Record: Codable, Equatable {
        public var since: Date
        public var last: Date
        public var boot: Date
        public var restarted: Bool
    }

    /// Notes that a macOS service is busy now, and says whether it is stuck. A record from an earlier boot counts only if
    /// it was busy within the hour before this boot: it carried on until the restart and started again after it.
    public static func note(_ name: String, busySince: Date, now: Date, boot: Date, records: inout [String: Record]) -> Stuck? {
        var since = busySince, restarted = false
        if let r = records[name] {
            if r.boot < boot.addingTimeInterval(-60) {
                if r.last >= boot.addingTimeInterval(-3600) { since = min(r.since, busySince); restarted = true }
            } else {
                since = min(r.since, busySince); restarted = r.restarted
            }
        }
        records[name] = Record(since: since, last: now, boot: boot, restarted: restarted)
        // forget services not busy for two days
        records = records.filter { now.timeIntervalSince($0.value.last) < 2 * 24 * 3600 }
        return now.timeIntervalSince(since) >= stuckAfter ? Stuck(since: since, afterRestart: restarted) : nil
    }

    public static let recordsKey = "macOSBusy"

    /// The same, with the records kept in Cool Head's preferences.
    public static func note(_ name: String, busySince: Date, now: Date = Date()) -> Stuck? {
        var records = (UserDefaults.standard.data(forKey: recordsKey).flatMap { try? JSONDecoder().decode([String: Record].self, from: $0) }) ?? [:]
        let stuck = note(name, busySince: busySince, now: now, boot: boot, records: &records)
        UserDefaults.standard.set(try? JSONEncoder().encode(records), forKey: recordsKey)
        return stuck
    }

    /// When this Mac last started (`kern.boottime`).
    public static let boot: Date = {
        var tv = timeval()
        var size = MemoryLayout<timeval>.size
        guard sysctlbyname("kern.boottime", &tv, &size, nil, 0) == 0 else { return Date.distantPast }
        return Date(timeIntervalSince1970: Double(tv.tv_sec) + Double(tv.tv_usec) / 1e6)
    }()

    // MARK: the card

    /// "2 days ago", "yesterday", "5 hours ago", "under an hour ago".
    public static func ago(_ d: Date, now: Date) -> String {
        let s = now.timeIntervalSince(d)
        if s < 3600 { return "under an hour ago" }
        if s < 24 * 3600 { let h = Int(s / 3600); return h == 1 ? "an hour ago" : "\(h) hours ago" }
        if s < 48 * 3600 { return "yesterday" }
        return "\(Int(s / (24 * 3600))) days ago"
    }

    /// "over a day", "3 days".
    static func span(_ s: TimeInterval) -> String { s < 48 * 3600 ? "over a day" : "\(Int(s / (24 * 3600))) days" }

    static let feedbackAssistant = "/System/Library/CoreServices/Applications/Feedback Assistant.app"
    static let systemSettings = "/System/Applications/System Settings.app"

    /// The card for macOS's own work that is stuck, in place of the usual one; nil when it isn't, or when it's work macOS
    /// expects after an update and the update was recent. What Cool Head thinks, a brief disclaimer, then its advice: a
    /// restart first; once a restart hasn't cleared it, a macOS update or telling Apple, since only Apple can fix it.
    /// One of macOS's own background services: a program in macOS's folders that launchd started (or whose parents
    /// can't be read, as for root's services), not a command someone ran from a shell (/usr/bin/zip from Terminal).
    public static func isService(_ e: Evidence) -> Bool {
        guard e.script == nil, let p = e.path, CaseReport.isMacOS(p) else { return false }
        return e.ancestors.first.map { $0.pid == 1 } ?? true
    }

    /// A macOS service nobody catalogued (research rule 6): names change every release, so an unknown one is "part of
    /// macOS, working in the background", normal when it runs at background priority; never silence, never alarm.
    /// Nothing to press but Look it up (waiting is the card's clock); a day or more busy is the stuck card's (rule 16).
    static func unknownCard(_ e: Evidence, _ r: Reading?, busyFor: TimeInterval, active: Bool, used: String, extra: String, now: Date) -> Card {
        if !active { return Card(state: .quiet, headline: "\(e.name), part of macOS, is quiet now.", explanation: "", fixes: []) }
        let low = r?.cool == true
        let how = low ? "It runs at low priority, on the chip's efficiency cores, so it uses little power even though it looks busy."
            : "It " + used + (r?.cool == false ? " at normal priority." : ".")
        // an hour or more above background priority: worth watching, and the stuck card takes over after a day
        let watch = !low && busyFor >= 3600
        return Card(state: watch ? .unknown : .working,
                    headline: "\(e.name) is part of macOS, working in the background.",
                    explanation: "We don't know this one by name. " + how + extra
                        + (watch ? " If it runs for a day, we'll say what to try." : e.mine ? "" : " macOS needs it, so stopping it would only start it again."),
                    fixes: [Card.lookUp(e.name, recommended: false)])
    }

    public static func stuckCard(_ e: Evidence, _ r: Reading?, now: Date) -> Card? {
        guard let s = r?.stuck, let path = e.path, CaseReport.isMacOS(path), e.script == nil else { return nil }
        if r?.update != nil, Pattern.match(name: e.name, path: e.path, pid: e.pid)?.afterUpdate == true { return nil }
        let long = span(now.timeIntervalSince(s.since))
        if !s.afterRestart {
            return Card(state: .unknown, headline: "\(e.name), part of macOS, seems stuck: it's been busy for \(long).",
                        explanation: "macOS's background work doesn't usually run this long. We can't be certain it's stuck.",
                        fixes: [Fix.guide("restart", "Restart your Mac", "Save your work first.", steps: ["Save your work.", "Choose \(Fmt.path("Apple menu", "Restart"))."], recommended: true),
                                Card.share])
        }
        return Card(state: .unknown, headline: "\(e.name), part of macOS, is stuck: a restart didn't clear it.",
                    explanation: "It's been busy for \(long): a macOS fault only Apple can fix. We can't be certain of the cause.",
                    fixes: [Fix.openApp("update", "Check for a macOS update", bundle: systemSettings, steps: "Choose \(Fmt.path("General", "Software Update")).", recommended: true),
                            Fix.openApp("feedback", "Tell Apple", bundle: feedbackAssistant, steps: "Choose New Feedback, then macOS, and say \(e.name) has been busy for \(long)."),
                            Card.share])
    }

    // MARK: reading one process

    /// Everything above, for one of macOS's own processes on this Mac. `track` keeps the record that tells a restart
    /// apart (the watcher); a one-off look (`coolhead why`) doesn't.
    public static func read(_ e: Evidence, busySince: Date?, efficiencyCores: Int, now: Date = Date(), track: Bool) -> Reading {
        var r = Reading()
        r.cool = cool(threads(e.pid), efficiencyCores: efficiencyCores)
        if let u = lastUpdate(now: now), now.timeIntervalSince(u.date) < afterUpdate { r.update = u }
        if track, let s = busySince { r.stuck = note(e.name, busySince: s, now: now) }
        return r
    }
}
