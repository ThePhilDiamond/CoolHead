import Foundation

/// The CPU limit, the step after Run it cooler for an app or job that's still busy (notes/cpu-cap.md): it's stopped
/// and continued many times a second so it uses no more than the chosen share of one core, the way Activity Monitor
/// counts (100% is one core in full use). An app is limited only while you aren't using it, and never while it plays
/// sound or downloads (see BusyWith).
///
/// So far, the words and the option on a card; the limiting itself comes next.
public enum CPUCap {
    /// The shares offered: as little as possible, or some room for work you still want done.
    public static let choices = [10, 20, 30]

    /// The option on a card, offered once running it cooler wasn't enough.
    public static func fix(app: Bool) -> Fix {
        Fix(id: "cpucap", title: "Limit its CPU",
            consequence: app ? "Held to a small share of one core while you aren't using it. Full speed when you switch to it. Undo any time."
                             : "Held to a small share of one core, so it takes longer and makes far less heat. Undo any time.",
            kind: .cpuCap, recommended: true)
    }

    /// On the card: why it's offered.
    public static func cardLine(cores: Double) -> String {
        "It's already running cooler and still using \(cores >= 1.5 ? "about \(Int(cores.rounded())) cores" : "a whole core")."
    }
}

extension Card {
    /// This card for something already running cooler and still busy: the limit is offered first, in place of Run it
    /// cooler, and the card says why.
    public func offeringCap(app: Bool, cores: Double) -> Card {
        var rest = fixes.filter { $0.kind != .cooler }.map { f -> Fix in var f = f; f.recommended = false; return f }
        rest.insert(CPUCap.fix(app: app), at: 0)
        var c = Card(state: state, headline: headline, explanation: explanation + " " + CPUCap.cardLine(cores: cores), fixes: rest)
        c.names = names; c.facts = facts; c.cardID = cardID; c.diagnosis = diagnosis
        c.optionFacts = optionFacts.filter { $0.key != "cooler" }
        return c
    }
}
