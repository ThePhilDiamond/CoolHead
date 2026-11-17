import Foundation

/// Games are protected (Phil, 15 November 2026: "if we "run it cooler" with a game, couldn't it adversely impact
/// performance? We may wish to protect games as a class we know will usually be busy and suggest killing other tasks
/// first to improve game performance"): busy is what a game does, so it's calm and never slowed down; when the Mac is
/// warm, lower settings is the fix that keeps play smooth.
enum GameCard: ProcessCard {
    static let name = "a game"
    static let id = "game"
    static let kind = CardKind.explanation
    static let rule = "Phil, 15 November 2026: games are protected, never slowed"
    static func confidence(_ s: Situation) -> Confidence { .named("the app itself says it is a game") }
    static let samples = ["game"]

    static func card(_ s: Situation) -> Card? {
        guard let game = s.e.gameBundle else { return nil }
        let name = ((game as NSString).lastPathComponent as NSString).deletingPathExtension
        if !s.active { return Card(state: .quiet, headline: "\(name) is quiet now.", explanation: "", fixes: []) }
        return Card(state: .working, headline: "\(name) is a game. Games keep your Mac busy while they run.",
                    // rule 7: in full screen, Game Mode gives the game priority over background work (Apple, macOS 14)
                    explanation: "That's normal while you play. In full screen, macOS's Game Mode gives it priority over background work." + Fmt.its([s.gpuClause, s.warm ? "adding to the heat" : nil]),
                    fixes: [Fix.openApp("settings", "Lower its graphics settings", bundle: game, steps: "In its settings, lower quality or frame rate. Less heat, still smooth.", recommended: s.warm),
                            Fix(id: "quit", title: "Quit \(name)", consequence: "Save your game first. Unsaved progress may be lost.", kind: .quitApp(game)).losingWork()])
    }
}
