import Foundation

/// One of macOS's own services that isn't in the catalogue (see BackgroundWork.unknownCard, research rule 6): names
/// change every release, so an unknown one is part of macOS, working in the background.
enum UnknownServiceCard: ProcessCard {
    static let name = "an unfamiliar part of macOS"
    static let id = "unknown-service"
    static let kind = CardKind.catchAll
    static let rule = "Research rule 6: a macOS service nobody catalogued is part of macOS; never silence, never alarm"
    static func confidence(_ s: Situation) -> Confidence { .type("it's one of macOS's own programs, though not one Cool Head knows by name") }
    static let samples = ["macos-unknown-low-priority", "macos-unknown-normal-priority"]

    static func card(_ s: Situation) -> Card? {
        guard BackgroundWork.isService(s.e) else { return nil }
        return BackgroundWork.unknownCard(s.e, s.background, busyFor: s.busyFor, active: s.active,
                                          used: "has used about \(Fmt.cores(s.e.coresNow)) for \(Fmt.duration(s.busyFor))",
                                          extra: Fmt.its([s.gpuClause, s.warm && s.heating ? "adding to the heat" : nil]), now: s.now)
    }
}
