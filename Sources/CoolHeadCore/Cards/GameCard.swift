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
        if !s.active { return Card(state: .quiet, CardTemplate(name, .quiet, nil), fixes: []) }
        return Card(state: .working,
                    // rule 7: in full screen, Game Mode gives the game priority over background work (Apple, macOS 14)
                    CardTemplate(name, .words("is a game"), .normal,
                                 // the graphics chip's share is in Nerdy stuff, as on the catalogue cards
                                 evidence: ["Games keep your Mac busy while they run. In full screen, Game Mode in macOS gives it priority over background work."],
                                 effect: [CardTemplate.it([s.warm ? "adds heat" : nil])].compactMap { $0 }),
                    fixes: [Fix.openApp("settings", "Lower its graphics settings", bundle: game, steps: "In its settings, lower the quality or frame rate. It makes less heat and still plays smoothly.", recommended: s.warm),
                            Fix(id: "quit", title: "Quit \(name)", consequence: "This closes the game. Save your game first, or you may lose progress.", kind: .quitApp(game)).losingWork()])
    }
}
