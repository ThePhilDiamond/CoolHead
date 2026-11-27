import Foundation

/// A macOS service working for an app (see Served.swift, research rule 4): the work is the app's, so the card names it
/// and quitting it is the advice.
enum ServedCard: ProcessCard {
    static let name = "macOS working for an app"
    static let id = "served"
    static let kind = CardKind.explanation
    static let rule = "Research rule 4: a macOS service's work is credited to the app it's working for"
    static func confidence(_ s: Situation) -> Confidence { .named("macOS says which app this part of macOS is working for") }
    static let samples = ["macos-service-for-app"]

    static func card(_ s: Situation) -> Card? {
        guard var c = made(s) else { return nil }
        if let b = s.e.servedBy {
            let app = Served.name(b)
            c.diagnosis = Diagnosis(saw: "macOS is doing this work for \(app)")
            let sync = SyncApps.app(bundle: b) != nil
            let words = sync ? "nothing syncs until you open \(app) again" : MemoryAdvice.quitCost(app)
            c.optionFacts["quit"] = OptionFacts(helps: "ends the work macOS is doing for it", cost: words,
                                                stakes: words == nil ? .protected("\(app) asks about anything unsaved first") : nil)
        }
        return c
    }

    static func made(_ s: Situation) -> Card? {
        let e = s.e
        guard let b = e.servedBy, !s.webkit, s.active else { return nil }
        let app = Served.name(b)
        // what it does for the app, in the simple present ("It decodes video for IINA."); work macOS names, such as
        // decoding video for a player, is normal, and anything else costs more than a part of macOS usually does
        let doing = Served.doing(e)
        return Card(state: s.busyFor > 20 * 60 ? .unknown : .working,
                    CardTemplate("a part of macOS", doing != nil ? (s.gpuLed ? .words("is keeping the graphics chip busy") : .coresNow(s.e.coresNow)) : s.reading, doing != nil ? .normal : .moreThanUsual,
                                 evidence: ["It \(doing ?? "works") for \(app).", "Its name is \(e.name).", s.gpuLed ? nil : s.graphics].compactMap { $0 },
                                 effect: [CardTemplate.it([s.warm && s.heating ? "adds heat" : nil])].compactMap { $0 }),
                    fixes: [Served.quit(b), Card.lookUp(e.name, recommended: false), Card.wait(until: nil, now: s.now, recommended: false)])
    }
}
