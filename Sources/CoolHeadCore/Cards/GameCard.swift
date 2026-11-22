import Foundation

/// Games are protected: busy is what a game does, and running it cooler would hurt its performance, so it's calm and
/// never slowed down, and other busy work is offered to run cooler first, to leave the game more power. When the Mac is
/// warm, lower settings is the fix that keeps play smooth.
enum GameCard: ProcessCard {
    static let name = "a game"
    static let id = "game"
    static let kind = CardKind.explanation
    static let rule = "Games are protected, never slowed"
    static func confidence(_ s: Situation) -> Confidence { .named("the app itself says it's a game") }
    static let samples = ["game"]

    static func card(_ s: Situation) -> Card? {
        guard var c = made(s) else { return nil }
        if let game = s.e.gameBundle {
            let name = ((game as NSString).lastPathComponent as NSString).deletingPathExtension
            c.diagnosis = Diagnosis(saw: s.warm ? "\(name) is adding to the heat" : "\(name) is a game, and games keep your Mac busy while they run")
            c.optionFacts["settings"] = OptionFacts(helps: "cools the Mac while you keep playing")
            c.optionFacts["quit"] = OptionFacts(helps: "ends the load completely", cost: "unsaved progress may be lost, so save your game first")
        }
        return c
    }

    static func made(_ s: Situation) -> Card? {
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
