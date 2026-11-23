import Foundation

/// Checks for the CPU limit (CPUCap): the levels offered, the option on a card, and the card once it's limited.
extension Fixture {
    /// A made-up app already running cooler and still busy, offered the limit; and the same app at half speed, still
    /// adding to the heat (for screenshots: COOLHEAD_SNAPSHOT_SAMPLES).
    static func cpuCapSamples(_ now: Date) -> [(String, Card)] {
        let app = Evidence.sample(name: "Huddle", path: "/Applications/Huddle.app/Contents/MacOS/Huddle", start: now.addingTimeInterval(-3 * 3600), cores: 3)
        return [("cap-offered", Card.make(app, now: now, busySince: now.addingTimeInterval(-3600), warm: true).offeringCap(app: true, cores: 3)),
                ("cap-half", Card.stillHotUnderCap(subject: "Huddle", app: true, level: .half, before: 3, now: 1.5))]
    }

    static func cpuCapChecks(_ now: Date) -> [(String, Bool, String)] {
        var review: [(String, Bool, String)] = []
        func offer(_ c: Card) -> CPUCap.Offer? { c.fixes.compactMap { if case .cpuCap(let o) = $0.kind { return o }; return nil }.first }
        let app = Evidence.sample(name: "Huddle", path: "/Applications/Huddle.app/Contents/MacOS/Huddle", start: now.addingTimeInterval(-3 * 3600), cores: 3)
        let c = Card.make(app, now: now, busySince: now.addingTimeInterval(-3600), warm: true).offeringCap(app: true, cores: 3)
        let o = offer(c)
        let ok = c.recommended.map { if case .cpuCap = $0.kind { return true }; return false } == true
            && !c.fixes.contains { $0.kind == .cooler } && c.fixes.filter(\.recommended).count == 1
            && c.explanation.hasSuffix("It's already running cooler and still using about 3 cores.")
            && o?.current == .full && o?.suggested == .half && o?.levels == [.barely, .steady, .half, .full]
        review.append(("cpu-cap-offered", ok, "recommended \(c.recommended?.title ?? "none"); \(c.explanation)"))

        // levels: Slow and steady only from about 3 cores; half speed is half of the use before the limit
        let two = CPUCap.levels(before: 2), three = CPUCap.levels(before: 3)
        let amounts = CPUCap.Level.barely.cores(before: 3) == 0.2 && CPUCap.Level.steady.cores(before: 3) == 1
            && CPUCap.Level.half.cores(before: 3) == 1.5 && CPUCap.Level.full.cores(before: 3) == nil
        review.append(("cpu-cap-levels", two == [.barely, .half, .full] && three.count == 4 && amounts,
                       "at 2 cores \(two.map(\.name)); at 3 \(three.map(\.name))"))

        // already at half speed and still hot: the next level down is recommended, and the words compare with before
        let h = Card.stillHotUnderCap(subject: "Huddle", app: true, level: .half, before: 3, now: 1.5)
        let ho = offer(h)
        let hotOK = ho?.current == .half && ho?.suggested == .steady && h.explanation.hasPrefix("It's at half speed and still using about 1.5 cores.")
            && CPUCap.Level.steady.line(before: 3, app: true, limited: true) == "Slow and steady: about a third of its pace before the limit, and about a third of the heat."
        review.append(("cpu-cap-still-hot", hotOK, "\(h.headline) \(h.explanation) suggested \(ho?.suggested.name ?? "none")"))
        return review
    }
}
