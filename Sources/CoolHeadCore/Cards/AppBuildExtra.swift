import Foundation

/// What the app is built on, where that matters on this macOS (see AppBuild): an Intel app, or one set to open using
/// Rosetta. Never on a disguised program, macOS's own, or a quiet card.
enum AppBuildExtra: CardExtra {
    static let id = "app-build"
    static let rule = "AppBuild.swift: Intel apps and Rosetta, as macOS 26 and 27 treat them"

    static func add(to c: Card, _ s: Situation) -> Card? {
        let e = s.e
        guard let f = s.apps, s.disguise == nil, c.state != .quiet,
              let name = e.quittableApp ?? e.app, e.path.map({ !CaseReport.isMacOS($0) }) == true,
              let add = AppBuild.addition(f, app: name) else { return nil }
        return Card(state: c.state, headline: c.headline, explanation: c.explanation + add.sentence, fixes: c.fixes + [add.fix])
    }
}
