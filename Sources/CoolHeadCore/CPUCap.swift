import Foundation

/// The CPU limit, the step after Run it cooler for an app or job that's still busy (notes/cpu-cap.md): it's stopped
/// and continued many times a second so it uses no more than a level's share of CPU time, counted as Activity Monitor
/// counts it (100% is one core in full use). An app is limited only while you aren't using it, and never while it
/// plays sound or downloads (see BusyWith).
///
/// So far, the levels, their words, and the option on a card; the limiting itself comes next.
public enum CPUCap {
    /// The stops on the gauge, slowest first. Full speed is no limit: it still runs cooler.
    public enum Level: String, CaseIterable, Equatable {
        case barely, steady, half, full

        public var name: String {
            switch self {
            case .barely: return "Barely running"
            case .steady: return "Slow and steady"
            case .half: return "Half speed"
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
            case .full: return nil
            }
        }

        /// What this level does, under the gauge. `limited` says whether it's already under a limit, so its pace is
        /// compared with before the limit rather than now.
        public func line(before: Double, app: Bool, limited: Bool) -> String {
            let ref = limited ? "before the limit" : "now"
            switch self {
            case .barely: return "Barely running: stays open with nothing lost, but its work all but stops, and it makes almost no heat."
            case .steady: return "Slow and steady: about \(CPUCap.share(1 / max(before, 1))) of its pace \(ref), and about \(CPUCap.share(1 / max(before, 1))) of the heat."
            case .half: return "Half speed: half its pace \(ref), and about half the heat."
            case .full: return app ? "Full speed: no limit while you aren't using it; it still runs cooler." : "Full speed: no limit; it still runs cooler."
            }
        }
    }

    /// The levels offered: Slow and steady (one core) only for something using about 3 cores or more, since below that
    /// it's no slower than Half speed.
    public static func levels(before cores: Double) -> [Level] {
        cores >= 2.5 ? [.barely, .steady, .half, .full] : [.barely, .half, .full]
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
        let o = CPUCap.Offer(levels: CPUCap.levels(before: cores), current: .full, suggested: .half, before: cores, app: app)
        var rest = fixes.filter { $0.kind != .cooler }.map { f -> Fix in var f = f; f.recommended = false; return f }
        rest.insert(CPUCap.fix(o), at: 0)
        var c = Card(state: state, headline: headline,
                     explanation: explanation + " It's already running cooler and still using \(CPUCap.cores(cores)).", fixes: rest)
        c.names = names; c.facts = facts; c.cardID = cardID; c.diagnosis = diagnosis
        c.optionFacts = optionFacts.filter { $0.key != "cooler" }
        return c
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
