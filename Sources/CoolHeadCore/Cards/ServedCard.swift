import Foundation

/// A macOS service working for an app (see Served.swift, research rule 4): the work is the app's, so the card names it
/// and quitting it is the advice.
enum ServedCard: ProcessCard {
    static let name = "macOS working for an app"
    static let id = "served"
    static let kind = CardKind.explanation
    static let rule = "Research rule 4: a macOS service's work is credited to the app it's working for"
    static func confidence(_ s: Situation) -> Confidence { .type("macOS says which app this part of macOS is working for") }
    static let samples = ["macos-service-for-app"]

    static func card(_ s: Situation) -> Card? {
        let e = s.e
        guard let b = e.servedBy, !s.webkit, s.active else { return nil }
        let app = Served.name(b)
        return Card(state: s.busyFor > 20 * 60 ? .unknown : .working,
                    headline: Served.doing(e).map { "macOS is \($0) for \(app)." } ?? "A part of macOS is busy working for \(app).",
                    explanation: "The macOS process doing it, \(e.name), \(s.used)" + Fmt.its([s.gpuLed ? nil : s.gpuClause, s.warm && s.heating ? "adding to the heat" : nil]),
                    fixes: [Served.quit(b), Card.lookUp(e.name, recommended: false), Card.wait(until: nil, now: s.now, recommended: false)])
    }
}
