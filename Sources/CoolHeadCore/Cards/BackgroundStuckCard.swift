import Foundation

/// macOS's own work that is stuck (see BackgroundWork.swift): busy for days, or across a restart.
enum BackgroundStuckCard: ProcessCard {
    static let name = "stuck macOS work"
    static let id = "background-stuck"
    static let kind = CardKind.stalled
    static let rule = "BackgroundWork.swift: one of macOS's services still busy long after an update, or again after a restart"
    static let match = Match.name
    static let samples = ["stuck-macos-service", "stuck-after-restart"]

    static func card(_ s: Situation) -> Card? { BackgroundWork.stuckCard(s.e, s.background, now: s.now) }
}
