import Foundation

/// On a busy WindowServer, apps with an Electron that lags macOS 26.0 and 26.1 (see AppBuild): updating them is the
/// fix, so it's put first and recommended.
enum ElectronExtra: CardExtra {
    static let id = "electron"
    static let rule = "AppBuild.swift: older Electron apps keep WindowServer busy on macOS 26.0 and 26.1"

    static func add(to c: Card, _ s: Situation) -> Card? {
        let e = s.e
        guard let f = s.apps, s.disguise == nil, c.state != .quiet,
              Pattern.match(name: e.name, path: e.path, pid: e.pid)?.id == "windowserver",
              let add = AppBuild.electronAddition(f) else { return nil }
        let others = c.fixes.map { f -> Fix in var f = f; f.recommended = false; return f }
        return Card(state: c.state, headline: c.headline, explanation: c.explanation + add.sentence, fixes: [add.fix] + others)
    }
}
