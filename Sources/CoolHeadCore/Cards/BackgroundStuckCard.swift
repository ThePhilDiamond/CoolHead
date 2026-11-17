import Foundation

/// macOS's own work that is stuck (see BackgroundWork.swift): busy for days, or across a restart.
enum BackgroundStuckCard: ProcessCard {
    static let name = "stuck macOS work"
    static let id = "background-stuck"
    static let kind = CardKind.stalled
    static let rule = "BackgroundWork.swift: one of macOS's services still busy long after an update, or again after a restart"
    static func confidence(_ s: Situation) -> Confidence { .named("we know this part of macOS and have watched it stay busy") }
    static let samples = ["stuck-macos-service", "stuck-after-restart"]

    static func card(_ s: Situation) -> Card? {
        guard var c = made(s) else { return nil }
        if s.background?.stuck?.afterRestart == true {
            c.diagnosis = Diagnosis(saw: "it's stayed busy even after a restart", means: "it's likely a macOS fault that only an update can fix")
            c.optionFacts["update"] = OptionFacts(helps: "gets Apple's fix, if there is one yet")
        } else {
            c.diagnosis = Diagnosis(saw: "it's been busy far longer than macOS's background work usually runs", means: "it may be stuck")
            c.optionFacts["restart"] = OptionFacts(helps: "starts macOS's background work fresh", cost: "you need to save your work first")
        }
        return c
    }

    static func made(_ s: Situation) -> Card? { BackgroundWork.stuckCard(s.e, s.background, now: s.now) }
}
