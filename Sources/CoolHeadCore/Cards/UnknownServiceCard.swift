import Foundation

/// One of macOS's own services that isn't in the catalogue (see BackgroundWork.unknownCard, research rule 6): names
/// change every release, so an unknown one is part of macOS, working in the background.
enum UnknownServiceCard: ProcessCard {
    static let name = "an unfamiliar part of macOS"
    static let id = "unknown-service"
    static let kind = CardKind.catchAll
    static let rule = "Research rule 6: a macOS service nobody catalogued is part of macOS; never silence, never alarm"
    static func confidence(_ s: Situation) -> Confidence { .type("it's part of macOS, though not a part we know by name") }
    static let samples = ["macos-unknown-low-priority", "macos-unknown-normal-priority"]

    static func card(_ s: Situation) -> Card? {
        guard var c = made(s) else { return nil }
        c.diagnosis = Diagnosis(saw: "it's part of macOS, working in the background")
        return c
    }

    static func made(_ s: Situation) -> Card? {
        guard BackgroundWork.isService(s.e) else { return nil }
        return BackgroundWork.unknownCard(s.e, s.background, busyFor: s.busyFor, active: s.active,
                                          reading: .coresFor(s.e.coresNow, s.busyFor),
                                          evidence: [s.graphics].compactMap { $0 },
                                          effect: [CardTemplate.it([s.warm && s.heating ? "adds heat" : nil])].compactMap { $0 }, now: s.now)
    }
}
