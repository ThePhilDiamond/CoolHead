import Foundation

/// Spells of tight memory on this Mac, kept 30 days in Cool Head's preferences for one purpose: to tell whether memory is
/// what slows this Mac, and how often, so its memory advice shows when it helps and says how often it has happened. It's
/// Cool Head's one record of the past, so it's disclosed. Each spell keeps when it began and ended, how tight it got, how
/// much was moved to disk, whether the Mac was slowed (see MemoryGate), and the kind of program using the most. No names,
/// and nothing leaves the Mac. Listed in SECURITY.md under what Cool Head stores.
public enum PressureHistory {
    public struct Episode: Codable, Equatable {
        public var start: Date
        public var last: Date                // last seen tight
        public var end: Date?                // nil while it lasts
        public var peak: Level
        public var slowed: Bool              // MemoryGate.slowed held at some point in it
        public var top: Top?                 // the kind of program using the most when it was tightest
        public var startPages: UInt64?       // macOS's count of pages moved to disk when it began
        public var movedMB: Double = 0       // moved to disk during it

        /// How tight: heavy swapping while macOS still said normal, then macOS's own warning and critical.
        public enum Level: Int, Codable, Comparable {
            case swap = 0, warning, critical
            public static func < (a: Level, b: Level) -> Bool { a.rawValue < b.rawValue }
            public init?(_ s: MacState) {
                switch s.memoryLevel {
                case nil: return nil
                case "critical": self = .critical
                default: self = s.memoryPressure == "warning" ? .warning : .swap
                }
            }
        }
        /// The biggest user, as a kind only: Chrome's own advice depends on whether it was Chrome.
        public enum Top: String, Codable {
            case chrome, browser, app, job, macOS, other
            public init(_ g: MemGroup) {
                switch g.kind {
                case .browser: self = g.name == "Google Chrome" ? .chrome : .browser
                case .app: self = .app
                case .job: self = .job
                case .macOS: self = .macOS
                case .other: self = .other
                }
            }
        }

        public var seconds: TimeInterval { (end ?? last).timeIntervalSince(start) }
    }

    public static let key = "pressureEpisodes"
    public static let keep: TimeInterval = 30 * 24 * 3600
    public static let maxEpisodes = 500
    /// Shorter spells aren't kept: a moment of pressure isn't something a person waits on.
    public static let minimum: TimeInterval = 60
    /// Memory fine this long ends a spell, and a new one within it of the last continues it: pressure flickers at its edges.
    public static let endAfter: TimeInterval = 2 * 60
    public static let mergeGap: TimeInterval = 5 * 60
    /// While a spell lasts it's saved this often, so quitting or a crash loses at most this much of it.
    public static let saveEvery: TimeInterval = 5 * 60

    /// Folds one reading into the list: `tight` is nil when memory is fine. Returns whether the list changed enough to save.
    @discardableResult
    public static func note(_ list: inout [Episode], tight: Episode.Level?, slowed: Bool, top: Episode.Top?, swapOutPages: UInt64?,
                            pageSize: Int = Int(getpagesize()), now: Date) -> Bool {
        let open = list.indices.last.flatMap { list[$0].end == nil ? $0 : nil }
        guard let level = tight else {
            guard let i = open, now.timeIntervalSince(list[i].last) >= endAfter else { return false }
            list[i].end = list[i].last
            let kept = list[i].seconds >= minimum
            if !kept { list.remove(at: i) }
            prune(&list, now: now)
            return kept
        }
        if let i = open {
            var e = list[i]
            let before = e
            e.last = now
            if level > e.peak { e.peak = level; if let t = top { e.top = t } }
            if e.top == nil, let t = top { e.top = t }
            if slowed, !e.slowed { e.slowed = true; if let t = top { e.top = t } }
            if let p = swapOutPages, let s = e.startPages, p >= s { e.movedMB = Double(p - s) * Double(pageSize) / 1_048_576 }
            list[i] = e
            let reachedMinimum = before.last.timeIntervalSince(e.start) < minimum && e.seconds >= minimum
            let due = Int(before.last.timeIntervalSince(e.start) / saveEvery) != Int(e.seconds / saveEvery)
            return reachedMinimum || due || e.peak != before.peak || e.slowed != before.slowed || e.top != before.top
        }
        // a spell that starts soon after the last one ended continues it
        if let j = list.indices.last, let end = list[j].end, now.timeIntervalSince(end) <= mergeGap {
            list[j].end = nil
            note(&list, tight: tight, slowed: slowed, top: top, swapOutPages: swapOutPages, pageSize: pageSize, now: now)
            return true
        }
        list.append(Episode(start: now, last: now, end: nil, peak: level, slowed: slowed, top: top, startPages: swapOutPages))
        return false
    }

    /// A spell left open by quitting or a crash ends when it was last seen tight: at launch, and at quit.
    public static func closeOpen(_ list: inout [Episode], now: Date = Date()) {
        guard let i = list.indices.last, list[i].end == nil else { return }
        list[i].end = list[i].last
        if list[i].seconds < minimum { list.remove(at: i) }
        prune(&list, now: now)
    }

    static func prune(_ list: inout [Episode], now: Date) {
        list.removeAll { now.timeIntervalSince($0.end ?? $0.last) > keep }
        if list.count > maxEpisodes { list.removeFirst(list.count - maxEpisodes) }
    }

    public static func load(_ d: UserDefaults = .standard) -> [Episode] {
        d.data(forKey: key).flatMap { try? JSONDecoder().decode([Episode].self, from: $0) } ?? []
    }

    public static func save(_ list: [Episode], _ d: UserDefaults = .standard, now: Date = Date()) {
        var l = list
        prune(&l, now: now)
        if l.isEmpty { d.removeObject(forKey: key) } else { d.set(try? JSONEncoder().encode(l), forKey: key) }
    }

    /// The last 7 days: spells in which memory slowed the Mac, their minutes in all, and how many Chrome used the most in;
    /// and every spell of tight memory, slowed or not, with its minutes in all.
    public struct Week: Equatable {
        public let count: Int
        public let minutes: Int
        public let chromeCount: Int
        public var tightCount = 0
        public var tightMinutes = 0
        public init(count: Int, minutes: Int, chromeCount: Int, tightCount: Int = 0, tightMinutes: Int = 0) {
            self.count = count; self.minutes = minutes; self.chromeCount = chromeCount; self.tightCount = tightCount; self.tightMinutes = tightMinutes
        }
    }

    public static func week(_ list: [Episode], now: Date) -> Week {
        let tight = list.filter { now.timeIntervalSince($0.start) <= 7 * 24 * 3600 && $0.seconds >= minimum }
        let w = tight.filter(\.slowed)
        func total(_ l: [Episode]) -> Int { l.isEmpty ? 0 : max(1, Int((l.reduce(0) { $0 + $1.seconds } / 60).rounded())) }
        return Week(count: w.count, minutes: total(w), chromeCount: w.filter { $0.top == .chrome }.count, tightCount: tight.count, tightMinutes: total(tight))
    }

    /// For the This Mac page: how often memory slowed the Mac this week, and for how long in all.
    /// With no slowed spells it says how often memory was tight, never that memory didn't slow the Mac: the gate counts
    /// only memory moved to disk, and a Mac was slowed badly at warning with nothing moved (23 November 2026).
    public static func weekLine(_ w: Week) -> String {
        let time = Fmt.duration(Double(w.minutes) * 60)
        switch w.count {
        case 0 where w.tightCount == 0: return "Memory hasn't been tight this week."
        case 0 where w.tightCount == 1: return "Memory was tight once this week, for about \(Fmt.duration(Double(w.tightMinutes) * 60))."
        case 0: return "Memory was tight \(w.tightCount) times this week, about \(Fmt.duration(Double(w.tightMinutes) * 60)) in all."
        case 1: return "Memory slowed your Mac once this week, for about \(time)."
        default: return "Memory slowed your Mac \(w.count) times this week, about \(time) in all."
        }
    }

    /// Whether Chrome was the biggest user then, so the person knows whether Chrome's advice is worth their effort; nil
    /// when it wasn't, in any of them.
    public static func chromeLine(_ w: Week) -> String? {
        guard w.chromeCount > 0 else { return nil }
        if w.count == 1 { return "Chrome was using the most memory." }
        return w.chromeCount == w.count ? "Chrome was using the most memory each time." : "Chrome was using the most memory in \(w.chromeCount) of them."
    }

    /// Made-up spells for screenshots (COOLHEAD_SNAPSHOT_PRESSURE): three this week, 40 minutes in all, Chrome in two.
    public static func sample(now: Date = Date()) -> [Episode] {
        func e(_ daysAgo: Double, _ minutes: Double, _ top: Episode.Top, _ peak: Episode.Level = .warning) -> Episode {
            let s = now.addingTimeInterval(-daysAgo * 24 * 3600)
            let end = s.addingTimeInterval(minutes * 60)
            return Episode(start: s, last: end, end: end, peak: peak, slowed: true, top: top, startPages: nil, movedMB: minutes * 60)
        }
        return [e(5, 18, .chrome), e(3, 9, .app), e(1, 13, .chrome, .critical)]
    }
}

/// When memory is what slows the Mac (research synthesis, "The ladder", step 1; node N-019's gate): macOS has said warning
/// or critical for at least a minute, and memory is being moved to disk now. It decides what acts by itself (Cool Head for
/// Chrome's Auto) and what counts as "slowed" in the week. Pressure without disk moves doesn't show the Mac is coping: a
/// Mac was slowed badly at warning with nothing moved (23 November 2026), so no card or line says it is (see MemoryAdvice).
public enum MemoryGate {
    public static let minimumSpell: TimeInterval = 60
    /// Moved to disk in about the last 2 minutes. N-019 proposes about 250 MB in 5 minutes, the same rate; not yet tested.
    public static let writingMB = 100.0

    public static func slowed(_ s: MacState, tightSince: Date?, now: Date) -> Bool {
        guard s.memoryPressure == "warning" || s.memoryPressure == "critical", let since = tightSince,
              now.timeIntervalSince(since) >= minimumSpell, let mb = s.swappedOutMB, mb >= writingMB else { return false }
        return true
    }
}

/// What the memory card knows beyond the Mac's state now. Each field nil means "not judged", and the card behaves as it
/// did before it existed (the selftests' cards, and `coolhead memory`).
public struct MemoryContext: Equatable {
    public var slowed: Bool? = nil                    // MemoryGate.slowed
    public var week: PressureHistory.Week? = nil      // PressureHistory.week
    public var chrome: ChromeParts? = nil             // Chrome's memory by part, when Chrome is among the biggest
    public var memorySaver: ChromeMemorySaver.State? = nil
    public var offerSaverMaximum = false              // ChromeMemorySaver.shouldOffer
    public var companion: ChromeCompanion.Status? = nil
    /// How many tabs Cool Head for Chrome would sleep now (its own count: out of sight, not protected); nil when unknown.
    public var tabsToSleep: Int? = nil
    /// The link's count, every profile's together (ChromeLinkServer.Summary.toSleep), only while the extension is linked.
    public mutating func take(_ link: ChromeLinkServer.Summary) { tabsToSleep = companion == .connected ? link.toSleep : nil }
    public init(slowed: Bool? = nil, week: PressureHistory.Week? = nil, chrome: ChromeParts? = nil,
                memorySaver: ChromeMemorySaver.State? = nil, offerSaverMaximum: Bool = false, companion: ChromeCompanion.Status? = nil) {
        self.slowed = slowed; self.week = week; self.chrome = chrome; self.memorySaver = memorySaver; self.offerSaverMaximum = offerSaverMaximum
        self.companion = companion
    }
}
