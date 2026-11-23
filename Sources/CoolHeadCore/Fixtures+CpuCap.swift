import Foundation

/// Checks for the CPU limit (CPUCap): for now, the option on a card.
extension Fixture {
    /// A made-up app already running cooler and still busy, offered the limit (for screenshots: COOLHEAD_SNAPSHOT_SAMPLES).
    static func cpuCapSamples(_ now: Date) -> [(String, Card)] {
        let app = Evidence.sample(name: "Huddle", path: "/Applications/Huddle.app/Contents/MacOS/Huddle", start: now.addingTimeInterval(-3 * 3600), cores: 3)
        return [("cap-offered", Card.make(app, now: now, busySince: now.addingTimeInterval(-3600), warm: true).offeringCap(app: true, cores: 3))]
    }

    static func cpuCapChecks(_ now: Date) -> [(String, Bool, String)] {
        let app = Evidence.sample(name: "Huddle", path: "/Applications/Huddle.app/Contents/MacOS/Huddle", start: now.addingTimeInterval(-3 * 3600), cores: 3)
        let c = Card.make(app, now: now, busySince: now.addingTimeInterval(-3600), warm: true).offeringCap(app: true, cores: 3)
        let ok = c.recommended?.kind == .cpuCap && !c.fixes.contains { $0.kind == .cooler } && c.fixes.filter(\.recommended).count == 1
            && c.explanation.hasSuffix("It's already running cooler and still using about 3 cores.") && CPUCap.choices == [10, 20, 30]
        return [("cpu-cap-offered", ok, "recommended \(c.recommended?.title ?? "none"); \(c.explanation)")]
    }
}
