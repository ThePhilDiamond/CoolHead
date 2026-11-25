import AppKit

/// The CPU limit, the step after Run it cooler for an app or job that's still busy (notes/cpu-cap.md): it's stopped
/// and continued many times a second so it uses no more than a level's share of CPU time, counted as Activity Monitor
/// counts it (100% is one core in full use). An app is limited only while you aren't using it, and never while it
/// plays sound, records from a microphone, or downloads (see BusyWith).
///
/// The levels, their words, and the option on a card are here; CPULimiter does the stopping and continuing.
public enum CPUCap {
    /// The stops on the slider, slowest first. Cooler is Run it cooler with no limit; Full speed is neither. Each limit
    /// is a fixed amount of CPU time, the same every launch, so nothing is measured or stored but the level (25 November
    /// 2026: a share of what it used needed a measurement that a rule, a relaunch, or a second change got wrong).
    public enum Level: String, CaseIterable, Equatable {
        case barely, slow, easy, cooler, full

        /// A level as stored by a rule, including the names 0.21.0 stored: its one-core "steady" and its relative
        /// "half" (the lightest limit then, half of what it used) are both the one-core level now.
        public init?(stored: String) {
            switch stored {
            case "steady", "half": self = .easy
            default: self.init(rawValue: stored)
            }
        }

        public var name: String {
            switch self {
            case .barely: return "Barely running"
            case .slow: return "Slow and steady"
            case .easy: return "Easy pace"
            case .cooler: return "Cooler"
            case .full: return "Full speed"
            }
        }

        /// How many cores' worth of CPU time it may use, as Activity Monitor counts it (1 is 100%); nil for no limit.
        public var cores: Double? {
            switch self {
            case .barely: return 0.2
            case .slow: return 0.5
            case .easy: return 1
            case .cooler, .full: return nil
            }
        }

        /// What this level does, under the gauge. `now` is what it uses now, before any limit, when that's known (on a
        /// card offering the limit), so the words can compare; nil says only what the level allows.
        public func line(now: Double?, app: Bool) -> String { name + ": " + effect(now: now, app: app) }

        /// The same without its name: "up to half of one core (50% in Activity Monitor): about a third of its pace now,
        /// and about a third of the heat."
        public func effect(now: Double?, app: Bool) -> String {
            switch self {
            case .barely: return "stays open with nothing lost, but its work all but stops, and it makes almost no heat."
            case .slow, .easy:
                let c = cores ?? 1
                let amount = (self == .slow ? "up to half of one core" : "up to one core") + " (\(Int((c * 100).rounded()))% in Activity Monitor)"
                guard let now, now > 0 else { return amount + "." }
                // at or above what it uses now, it isn't held back at all; anything under is said as a share
                if c >= now { return amount + ": at least what it uses now, so nothing changes." }
                let f = CPUCap.share(c / now)
                return amount + ": about \(f) of its pace now, and about \(f) of the heat."
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

    /// The stops on every slider, the same for everything, so each sits in the same place on a card and on a Managed line.
    public static let levels: [Level] = Level.allCases

    /// The limit recommended for something using `cores`: the lightest that at least halves it, else Barely running.
    public static func suggested(cores: Double) -> Level {
        [Level.easy, .slow].first { ($0.cores ?? 0) <= cores / 2 } ?? .barely
    }

    /// The slider over the levels: macOS's own, not continuous, so it reports once, where it's let go, and never the
    /// stops a drag passes (25 November 2026: a drag from Slow and steady to Full speed applied each stop it passed, and
    /// passing Cooler cleared a rule's level). A click reports where it lands; a key or VoiceOver step reports at once.
    /// Not SwiftUI's Slider: during a drag macOS doesn't let SwiftUI redraw, and says the drag ended before its last
    /// move, so a drag back to where it started could still apply a stop it passed (an independent review's replay).
    public final class Slider: NSSlider {
        /// True while the mouse is down on it, so a redraw doesn't move the thumb back under the pointer.
        public private(set) var tracking = false
        /// The stop under the thumb as the mouse went down: a release there didn't move it, so it isn't a change.
        public private(set) var grabbed: Int?
        /// The level it stands for, from the page: where the thumb rests whenever it isn't held.
        public private(set) var level = 0
        public static func make(levels: Int, at stop: Int) -> Slider {
            let s = Slider(value: Double(stop), minValue: 0, maxValue: Double(max(levels - 1, 1)), target: nil, action: nil)
            s.numberOfTickMarks = levels
            s.allowsTickMarkValuesOnly = true
            s.isContinuous = false
            return s
        }
        /// The stop it reports, from where it was let go.
        public var stop: Int { min(max(Int(doubleValue.rounded()), 0), numberOfTickMarks - 1) }
        /// The page's level: the thumb goes there at once unless it's held (then it stays under the pointer).
        public func show(_ stop: Int) {
            level = stop
            if !tracking, self.stop != stop { doubleValue = Double(stop) }
        }
        /// After each release, the thumb goes back to the page's level on the next turn of the main queue: where a pick
        /// took, the page has moved the level there by then; where it didn't (an app that quit, a failure, or a release
        /// that applies nothing), the thumb doesn't stay on a stop that isn't so, whether or not the page redraws
        /// (an independent review: the same message twice didn't redraw, and left it there).
        public func settle() { DispatchQueue.main.async { [weak self] in self?.putBack() } }
        public func putBack() { show(level) }
        /// What to apply from the action it just sent, or nil: nothing where it's let go on its level or where it was
        /// grabbed (a release that didn't move it, even if the level changed meanwhile).
        public var toApply: Int? { Slider.apply(released: stop, grabbed: grabbed, level: level) }
        public static func apply(released: Int, grabbed: Int?, level: Int) -> Int? {
            released == level || released == grabbed ? nil : released
        }
        override public func mouseDown(with event: NSEvent) {
            grabbed = stop
            tracking = true
            defer { tracking = false; grabbed = nil }
            super.mouseDown(with: event)  // macOS tracks the drag here, then sends the action once
        }
    }

    /// What the gauge on a card shows: the levels, where it is now, and the one recommended.
    public struct Offer: Equatable {
        public var levels: [Level]
        public var current: Level
        public var suggested: Level
        /// Cores it uses now, before any limit, for the words; nil once limited or where it isn't known.
        public var now: Double?
        public var app: Bool
        public init(levels: [Level] = CPUCap.levels, current: Level, suggested: Level, now: Double?, app: Bool) {
            self.levels = levels; self.current = current; self.suggested = suggested; self.now = now; self.app = app
        }
    }

    /// The option on a card.
    public static func fix(_ o: Offer) -> Fix {
        Fix(id: "cpucap", title: "Limit it",
            consequence: o.app ? "Choose how much it may use while you aren't using it. Full speed when you switch to it. Undo any time."
                               : "Choose how much it may use. Undo any time.",
            kind: .cpuCap(o), recommended: true)
    }

    /// A limited app's level as the end of a sentence: "Huddle is running slow and steady".
    public static func phrase(_ l: Level) -> String {
        switch l {
        case .barely: return "is barely running"
        case .slow: return "is running slow and steady"
        case .easy: return "is at an easy pace"
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
    /// cooler, at Cooler now, with the lightest limit that at least halves its use recommended.
    public func offeringCap(app: Bool, cores: Double) -> Card {
        let o = CPUCap.Offer(current: .cooler, suggested: CPUCap.suggested(cores: cores), now: cores, app: app)
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
    public func runningCooler(subject: String, app: Bool, since: Date, level: CPUCap.Level?,
                              cores: Double, now: Date, neverLimited: Bool = false) -> Card {
        if let level { return Card.stillHotUnderCap(subject: subject, app: app, level: level, now: cores) }
        if !neverLimited, cores >= CPUCap.offerCores, now.timeIntervalSince(since) >= CPUCap.offerAfter { return offeringCap(app: app, cores: cores) }
        return self
    }

    /// The card for something already limited that's still adding to the heat: the gauge shows where it is, and the
    /// next level down is recommended.
    public static func stillHotUnderCap(subject: String, app: Bool, level: CPUCap.Level, now: Double) -> Card {
        let levels = CPUCap.levels
        let i = levels.firstIndex(of: level) ?? levels.count - 1
        let o = CPUCap.Offer(current: level, suggested: levels[max(i - 1, 0)], now: nil, app: app)
        // at the slowest level there's no further to go, so it says what's left rather than recommending where it is
        let next = i > 0 ? "Slowing it further cuts the heat more" + (app ? "; full speed when you switch to it." : ".")
                         : "It's at the slowest level, so if you don't need it now, quitting it stops the heat."
        return Card(state: .unknown, headline: "\(subject) is still adding to the heat.",
                    explanation: "It's limited to \(level.name) and still using \(CPUCap.cores(now)). " + next,
                    fixes: [CPUCap.fix(o)])
    }
}
