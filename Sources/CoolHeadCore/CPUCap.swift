import Foundation

/// The CPU limit, the step after Run it cooler for an app or job that's still busy (notes/cpu-cap.md): it's stopped
/// and continued many times a second so it uses no more than a level's share of CPU time, counted as Activity Monitor
/// counts it (100% is one core in full use). An app is limited only while you aren't using it, and never while it
/// plays sound, records from a microphone, or downloads (see BusyWith).
///
/// The levels, their words, and the option on a card are here; CPULimiter does the stopping and continuing.
public enum CPUCap {
    /// The stops on the slider, slowest first. Cooler is Run it cooler with no limit; Full speed is neither.
    public enum Level: String, CaseIterable, Equatable {
        case barely, steady, half, cooler, full

        public var name: String {
            switch self {
            case .barely: return "Barely running"
            case .steady: return "Slow and steady"
            case .half: return "Half speed"
            case .cooler: return "Cooler"
            case .full: return "Full speed"
            }
        }

        /// How many cores' worth of CPU time it may use, given what it used before the limit (measured fresh for each
        /// launch, never stored); nil for no limit.
        public func cores(before: Double) -> Double? {
            switch self {
            case .barely: return 0.2
            case .steady: return 1
            case .half: return before / 2
            case .cooler, .full: return nil
            }
        }

        /// What this level does, under the gauge. `limited` says whether it's already under a limit, so its pace is
        /// compared with before the limit rather than now.
        public func line(before: Double, app: Bool, limited: Bool) -> String { name + ": " + effect(before: before, app: app, limited: limited) }

        /// The same without its name: "half its pace now, and about half the heat."
        public func effect(before: Double, app: Bool, limited: Bool) -> String {
            let ref = limited ? "before the limit" : "now"
            switch self {
            case .barely: return "stays open with nothing lost, but its work all but stops, and it makes almost no heat."
            case .steady: return "about \(CPUCap.share(1 / max(before, 1))) of its pace \(ref), and about \(CPUCap.share(1 / max(before, 1))) of the heat."
            case .half: return "half its pace \(ref), and about half the heat."
            case .cooler: return "no limit; it runs on the efficiency cores, a little slower and cooler."
            case .full: return "back to normal, with nothing slowing it."
            }
        }
    }

    /// When the limit is offered: still using this many cores this long after Run it cooler.
    public static let offerCores = 1.0
    public static let offerAfter: TimeInterval = 180

    /// Call and meeting apps, by Trust key: a stall drops the call. (Chat apps with calls, such as Slack, play sound
    /// during one, which holds them at full speed anyway.)
    static let callApps: Set<String> = ["app:us.zoom.xos", "app:com.microsoft.teams", "app:com.microsoft.teams2",
                                        "app:com.apple.FaceTime", "app:com.cisco.webexmeetingsapp", "app:com.webex.meetingmanager",
                                        "app:com.skype.skype"]

    /// Never offered the limit, however busy: a virtual machine, whose clock falls behind and whose whole system stalls
    /// with it; an extension (.appex) that Finder and other apps wait on, such as a file provider, where a stall can
    /// hang Finder; and call and meeting apps. Games, security software, and macOS's own programs are never offered Run
    /// it cooler, so never get this far.
    public static func neverLimited(path: String?, key: String?, virtualMachine: Bool) -> Bool {
        virtualMachine || (path?.contains(".appex/") ?? false) || key.map(callApps.contains) == true
    }
    public static func neverLimited(_ e: Evidence) -> Bool {
        neverLimited(path: e.path, key: Trust.key(e), virtualMachine: RunCooler.isVirtualMachine(e))
    }

    /// The levels offered: Slow and steady (one core) only for something using about 3 cores or more, since below that
    /// it's no slower than Half speed.
    public static func levels(before cores: Double) -> [Level] {
        cores >= 2.5 ? [.barely, .steady, .half, .cooler, .full] : [.barely, .half, .cooler, .full]
    }

    /// What the gauge on a card shows: the levels, where it is now, and the one recommended.
    public struct Offer: Equatable {
        public var levels: [Level]
        public var current: Level
        public var suggested: Level
        /// Cores it used before the limit, for the words.
        public var before: Double
        public var app: Bool
        public init(levels: [Level], current: Level, suggested: Level, before: Double, app: Bool) {
            self.levels = levels; self.current = current; self.suggested = suggested; self.before = before; self.app = app
        }
    }

    /// The option on a card.
    public static func fix(_ o: Offer) -> Fix {
        Fix(id: "cpucap", title: "Limit it",
            consequence: o.app ? "Choose how much it may use while you aren't using it. Full speed when you switch to it. Undo any time."
                               : "Choose how much it may use. Undo any time.",
            kind: .cpuCap(o), recommended: true)
    }

    /// A limited app's level as the end of a sentence: "Huddle is at half speed".
    public static func phrase(_ l: Level) -> String {
        switch l {
        case .barely: return "is barely running"
        case .steady: return "is running slow and steady"
        case .half: return "is at half speed"
        case .cooler: return "is running cooler"
        case .full: return "is at full speed"
        }
    }

    /// A share in words: "a third", "a quarter", or a percentage.
    static func share(_ f: Double) -> String {
        switch f {
        case 0.45...0.55: return "half"
        case 0.3..<0.45: return "a third"
        case 0.22..<0.3: return "a quarter"
        default: return "\(Int((f * 100).rounded()))%"
        }
    }

    /// "about 3 cores", "about 1.5 cores", to the nearest half.
    static func cores(_ c: Double) -> String {
        let r = (c * 2).rounded() / 2
        return r >= 1.5 ? "about \(r == r.rounded() ? String(Int(r)) : String(format: "%.1f", r)) cores" : r >= 1 ? "about a core" : "under a core"
    }
}

extension Card {
    /// This card for something already running cooler and still busy: the limit is offered first, in place of Run it
    /// cooler, at Full speed now, with Half speed recommended as the lightest step.
    public func offeringCap(app: Bool, cores: Double) -> Card {
        let o = CPUCap.Offer(levels: CPUCap.levels(before: cores), current: .cooler, suggested: .half, before: cores, app: app)
        var rest = fixes.filter { $0.kind != .cooler }.map { f -> Fix in var f = f; f.recommended = false; return f }
        rest.insert(CPUCap.fix(o), at: 0)
        var c = Card(state: state, headline: headline,
                     explanation: explanation + " It's already running cooler and still using \(CPUCap.cores(cores)).", fixes: rest)
        c.names = names; c.facts = facts; c.cardID = cardID; c.diagnosis = diagnosis
        c.optionFacts = optionFacts.filter { $0.key != "cooler" }
        return c
    }

    /// This card for something Run it cooler is already slowing, without a rule: once limited, where it is and the next
    /// level down; otherwise, if it's still using `offerCores` or more `offerAfter` after and isn't `neverLimited`, the
    /// limit offered; else as it is.
    public func runningCooler(subject: String, app: Bool, since: Date, level: CPUCap.Level?, before: Double?,
                              cores: Double, now: Date, neverLimited: Bool = false) -> Card {
        if let level { return Card.stillHotUnderCap(subject: subject, app: app, level: level, before: before ?? cores, now: cores) }
        if !neverLimited, cores >= CPUCap.offerCores, now.timeIntervalSince(since) >= CPUCap.offerAfter { return offeringCap(app: app, cores: cores) }
        return self
    }

    /// The card for something already limited that's still adding to the heat: the gauge shows where it is, and the
    /// next level down is recommended.
    public static func stillHotUnderCap(subject: String, app: Bool, level: CPUCap.Level, before: Double, now: Double) -> Card {
        let levels = CPUCap.levels(before: before)
        let i = levels.firstIndex(of: level) ?? levels.count - 1
        let o = CPUCap.Offer(levels: levels, current: level, suggested: levels[max(i - 1, 0)], before: before, app: app)
        return Card(state: .unknown, headline: "\(subject) is still adding to the heat.",
                    explanation: "It's at \(level.name.lowercased()) and still using \(CPUCap.cores(now)). Slowing it further cuts the heat more"
                        + (app ? "; full speed when you switch to it." : "."),
                    fixes: [CPUCap.fix(o)])
    }
}
